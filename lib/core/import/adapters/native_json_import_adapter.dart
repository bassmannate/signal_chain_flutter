import 'dart:convert';
import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../import_adapter.dart';
import '../import_batch_result.dart';
import '../import_format.dart';
import '../imported_patch_entry.dart';

/// Imports single patches and library bundles in Signal Chain Native JSON (`.json`).
class NativeJsonImportAdapter extends ImportAdapter {
  const NativeJsonImportAdapter();

  static const int currentSchemaVersion = 1;

  @override
  ImportFormat get format => ImportFormat.signalChainJson;

  static String? _tryDecodeLeadingText(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }
      return text.trimLeft();
    } catch (_) {
      return null;
    }
  }

  @override
  bool canHandle({required Uint8List bytes, String? fileName}) {
    final trimmed = _tryDecodeLeadingText(bytes);
    if (trimmed != null && (trimmed.startsWith('{') || trimmed.startsWith('['))) {
      return true;
    }
    if (fileName != null && fileName.toLowerCase().endsWith('.json')) {
      return trimmed != null && trimmed.isNotEmpty;
    }
    return false;
  }

  @override
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  }) {
    if (bytes.isEmpty) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'JSON input is empty.',
          ),
        ],
      );
    }

    String text;
    try {
      text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }
    } catch (e) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Invalid UTF-8 text: $e',
          ),
        ],
      );
    }

    final dynamic decoded;
    try {
      decoded = json.decode(text);
    } catch (e) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Malformed JSON: $e',
          ),
        ],
      );
    }

    if (decoded is List) {
      return _decodePatchList(
        decoded,
        sourceName: sourceName,
        sourcePath: sourcePath,
        extraWarnings: const [],
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Expected a JSON object or array of patches.',
          ),
        ],
      );
    }

    // Library bundle format: { "format": "signal_chain_library", "patches": [...] }
    if (decoded['patches'] is List || decoded['format'] == 'signal_chain_library') {
      final warnings = <String>[];
      final rawVersion = decoded['schemaVersion'];
      if (rawVersion != null) {
        if (rawVersion is! int) {
          return ImportBatchResult(
            totalSourcesScanned: 1,
            diagnostics: [
              ImportDiagnostic(
                severity: ImportDiagnosticSeverity.error,
                sourceName: sourceName,
                sourcePath: sourcePath,
                message: 'Invalid schemaVersion "$rawVersion" in library bundle.',
              ),
            ],
          );
        }
        if (rawVersion > currentSchemaVersion) {
          warnings.add(
            'Library bundle uses newer schemaVersion ($rawVersion); some fields may not load.',
          );
        }
      }

      final patchesList = decoded['patches'];
      if (patchesList is! List) {
        return ImportBatchResult(
          totalSourcesScanned: 1,
          diagnostics: [
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.error,
              sourceName: sourceName,
              sourcePath: sourcePath,
              message: 'Library bundle is missing a valid "patches" array.',
            ),
          ],
        );
      }

      return _decodePatchList(
        patchesList,
        sourceName: sourceName,
        sourcePath: sourcePath,
        extraWarnings: warnings,
      );
    }

    // Single patch JSON
    final singleResult = _decodeSinglePatchMap(
      decoded,
      sourceName: sourceName,
      sourcePath: sourcePath,
    );
    return ImportBatchResult(
      entries: singleResult.entry != null ? [singleResult.entry!] : const [],
      diagnostics: singleResult.diagnostic != null ? [singleResult.diagnostic!] : const [],
      totalSourcesScanned: 1,
    );
  }

  ImportBatchResult _decodePatchList(
    List<dynamic> list, {
    required String sourceName,
    String? sourcePath,
    required List<String> extraWarnings,
  }) {
    final entries = <ImportedPatchEntry>[];
    final diagnostics = <ImportDiagnostic>[
      for (final w in extraWarnings)
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.warning,
          sourceName: sourceName,
          sourcePath: sourcePath,
          message: w,
        ),
    ];

    if (list.isEmpty) {
      diagnostics.add(ImportDiagnostic(
        severity: ImportDiagnosticSeverity.warning,
        sourceName: sourceName,
        sourcePath: sourcePath,
        message: 'Library bundle contains 0 patches.',
      ));
      return ImportBatchResult(
        entries: entries,
        diagnostics: diagnostics,
        totalSourcesScanned: 1,
      );
    }

    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map<String, dynamic>) {
        diagnostics.add(ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: '$sourceName [#${i + 1}]',
          sourcePath: sourcePath,
          message: 'Expected patch JSON object at index $i.',
        ));
        continue;
      }

      final res = _decodeSinglePatchMap(
        item,
        sourceName: sourceName,
        sourcePath: sourcePath,
        messageIndex: i,
      );
      if (res.entry != null) {
        entries.add(res.entry!);
      }
      if (res.diagnostic != null) {
        diagnostics.add(res.diagnostic!);
      }
    }

    return ImportBatchResult(
      entries: entries,
      diagnostics: diagnostics,
      totalSourcesScanned: 1,
    );
  }

  ({ImportedPatchEntry? entry, ImportDiagnostic? diagnostic}) _decodeSinglePatchMap(
    Map<String, dynamic> map, {
    required String sourceName,
    String? sourcePath,
    int? messageIndex,
  }) {
    final label = messageIndex != null ? '$sourceName [#${messageIndex + 1}]' : sourceName;
    final warnings = <String>[];

    if (map['name'] is! String && map['slots'] is! List) {
      return (
        entry: null,
        diagnostic: ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: label,
          sourcePath: sourcePath,
          message: 'JSON object is missing required "name" or "slots" fields.',
        ),
      );
    }

    if (map['slots'] != null && map['slots'] is! List) {
      return (
        entry: null,
        diagnostic: ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: label,
          sourcePath: sourcePath,
          message: '"slots" must be a JSON array.',
        ),
      );
    }

    try {
      final patch = Patch.fromJson(map);
      if (patch.deviceFamily == DeviceFamily.unknown) {
        final rawFamily = map['deviceFamily'];
        warnings.add(
          rawFamily == null
              ? 'Patch JSON does not specify a deviceFamily; defaulted to Unknown.'
              : 'Unrecognized deviceFamily "$rawFamily"; defaulted to Unknown.',
        );
      }

      return (
        entry: ImportedPatchEntry(
          patch: patch,
          detectedFormat: format,
          inferredDeviceFamily: patch.deviceFamily,
          sourceName: sourceName,
          sourcePath: sourcePath,
          messageIndex: messageIndex,
          warnings: warnings,
        ),
        diagnostic: null,
      );
    } catch (e) {
      return (
        entry: null,
        diagnostic: ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: label,
          sourcePath: sourcePath,
          message: 'Failed to decode patch JSON: $e',
        ),
      );
    }
  }
}

