import 'dart:convert';
import 'dart:typed_data';

import '../../models/device_family.dart';
import 'adapters/native_json_import_adapter.dart';
import 'adapters/raw_sysex_import_adapter.dart';
import 'adapters/symbiosis_import_adapter.dart';
import 'adapters/zoom_multistomp_studio_import_adapter.dart';
import 'adapters/zoom_ptcf_import_adapter.dart';
import 'import_adapter.dart';
import 'import_batch_result.dart';
import 'import_file_system.dart';
import 'import_format.dart';
import 'imported_patch_entry.dart';

/// Orchestrates format auto-detection, decoding, batch directory scanning, and
/// device-mismatch validation across all registered [ImportAdapter]s.
class PatchImporter {
  /// Supported file extensions for file browser filtering and folder batch scans.
  static const Set<String> supportedExtensions = {'.json', '.zptc', '.syx'};

  final List<ImportAdapter> adapters;

  const PatchImporter({required this.adapters});

  /// Standard built-in importer with all supported format adapters ordered
  /// from most specific to most general.
  factory PatchImporter.standard() {
    return const PatchImporter(
      adapters: [
        SymbiosisImportAdapter(),
        ZoomMultistompStudioImportAdapter(),
        ZoomPtcfImportAdapter(),
        NativeJsonImportAdapter(),
        RawSysExImportAdapter(),
      ],
    );
  }

  /// Auto-detects the [ImportFormat] from binary/text magic headers and [fileName].
  ImportFormat detectFormat({
    required Uint8List bytes,
    String? fileName,
  }) {
    for (final adapter in adapters) {
      if (adapter.canHandle(bytes: bytes, fileName: fileName)) {
        return adapter.format;
      }
    }
    return ImportFormat.unknown;
  }

  ImportAdapter? _adapterForFormat(ImportFormat format) {
    for (final adapter in adapters) {
      if (adapter.format == format) return adapter;
    }
    return null;
  }

  /// Decodes raw [bytes] using auto-detection (or [formatOverride]).
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
    DeviceFamily? activeDeviceFamily,
    ImportFormat? formatOverride,
  }) {
    ImportAdapter? selected;
    if (formatOverride != null && formatOverride != ImportFormat.unknown) {
      selected = _adapterForFormat(formatOverride);
    } else {
      for (final adapter in adapters) {
        if (adapter.canHandle(bytes: bytes, fileName: sourceName)) {
          selected = adapter;
          break;
        }
      }
    }

    if (selected == null) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Unrecognized file format (expected JSON, PTCF .zptc, or SysEx .syx).',
          ),
        ],
      );
    }

    final rawResult = selected.importBytes(
      bytes,
      sourceName: sourceName,
      sourcePath: sourcePath,
      targetDeviceHint: targetDeviceHint ?? activeDeviceFamily,
    );

    return _applyDeviceMismatchWarnings(rawResult, activeDeviceFamily);
  }

  /// Decodes pasted text (Signal Chain JSON or ASCII hex SysEx `F0 ... F7`).
  ImportBatchResult importText(
    String text, {
    String sourceName = 'clipboard',
    DeviceFamily? targetDeviceHint,
    DeviceFamily? activeDeviceFamily,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            message: 'Input text is empty.',
          ),
        ],
      );
    }

    // Try ASCII hex SysEx first if text begins with F0
    final hexBytes = RawSysExImportAdapter.tryParseHexSysExText(trimmed);
    if (hexBytes != null) {
      return importBytes(
        hexBytes,
        sourceName: '$sourceName.syx',
        targetDeviceHint: targetDeviceHint,
        activeDeviceFamily: activeDeviceFamily,
        formatOverride: ImportFormat.rawSysEx,
      );
    }

    // Otherwise decode as UTF-8 JSON
    return importBytes(
      Uint8List.fromList(utf8.encode(trimmed)),
      sourceName: '$sourceName.json',
      targetDeviceHint: targetDeviceHint,
      activeDeviceFamily: activeDeviceFamily,
      formatOverride: ImportFormat.signalChainJson,
    );
  }

  /// Reads and imports a single file from [fileSystem].
  Future<ImportBatchResult> importFile(
    String filePath, {
    required ImportFileSystem fileSystem,
    DeviceFamily? targetDeviceHint,
    DeviceFamily? activeDeviceFamily,
  }) async {
    final sourceName = ImportFileSystem.baseName(filePath);
    try {
      final bytes = await fileSystem.readFileBytes(filePath);
      return importBytes(
        bytes,
        sourceName: sourceName,
        sourcePath: filePath,
        targetDeviceHint: targetDeviceHint,
        activeDeviceFamily: activeDeviceFamily,
      );
    } catch (e) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: filePath,
            message: 'Failed to read file: $e',
          ),
        ],
      );
    }
  }

  /// Scans [dirPath] for supported patch files (`.zptc`, `.json`, `.syx`)
  /// and aggregates all decoded patches and diagnostics.
  Future<ImportBatchResult> importDirectory(
    String dirPath, {
    required ImportFileSystem fileSystem,
    bool recursive = false,
    DeviceFamily? targetDeviceHint,
    DeviceFamily? activeDeviceFamily,
  }) async {
    List<ImportFsEntry> entries;
    try {
      entries = await fileSystem.listDirectory(dirPath);
    } catch (e) {
      return ImportBatchResult(
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: ImportFileSystem.baseName(dirPath),
            sourcePath: dirPath,
            message: 'Failed to scan folder: $e',
          ),
        ],
      );
    }

    var aggregate = const ImportBatchResult();

    for (final entry in entries) {
      if (entry.isDirectory) {
        if (recursive) {
          final sub = await importDirectory(
            entry.path,
            fileSystem: fileSystem,
            recursive: true,
            targetDeviceHint: targetDeviceHint,
            activeDeviceFamily: activeDeviceFamily,
          );
          aggregate = aggregate.merge(sub);
        }
        continue;
      }

      if (!ImportFileSystem.matchesAllowedExtension(
        entry.name,
        supportedExtensions,
      )) {
        aggregate = aggregate.merge(ImportBatchResult(
          totalSourcesScanned: 1,
          diagnostics: [
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.skipped,
              sourceName: entry.name,
              sourcePath: entry.path,
              message: 'Skipped unsupported file type.',
            ),
          ],
        ));
        continue;
      }

      final fileResult = await importFile(
        entry.path,
        fileSystem: fileSystem,
        targetDeviceHint: targetDeviceHint,
        activeDeviceFamily: activeDeviceFamily,
      );
      aggregate = aggregate.merge(fileResult);
    }

    return aggregate;
  }

  ImportBatchResult _applyDeviceMismatchWarnings(
    ImportBatchResult result,
    DeviceFamily? activeDeviceFamily,
  ) {
    if (activeDeviceFamily == null || activeDeviceFamily == DeviceFamily.unknown) {
      return result;
    }

    final updatedEntries = <ImportedPatchEntry>[];
    for (final entry in result.entries) {
      if (entry.isDeviceMismatch(activeDeviceFamily)) {
        final mismatchMsg =
            'Targets ${entry.inferredDeviceFamily.displayName} (active device is ${activeDeviceFamily.displayName}).';
        updatedEntries.add(entry.copyWith(
          warnings: [...entry.warnings, mismatchMsg],
        ));
      } else {
        updatedEntries.add(entry);
      }
    }

    return ImportBatchResult(
      entries: updatedEntries,
      diagnostics: result.diagnostics,
      totalSourcesScanned: result.totalSourcesScanned,
    );
  }
}

