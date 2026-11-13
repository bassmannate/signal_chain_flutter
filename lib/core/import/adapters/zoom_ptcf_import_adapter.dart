import 'dart:convert';
import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../protocols/zoom_ms_plus_protocol.dart';
import '../import_adapter.dart';
import '../import_batch_result.dart';
import '../import_format.dart';
import '../imported_patch_entry.dart';

/// Imports standard binary Zoom `PTCF` (`.zptc`) patch files.
class ZoomPtcfImportAdapter extends ImportAdapter {
  const ZoomPtcfImportAdapter();

  static const int minPtcfBytes = 36;

  @override
  ImportFormat get format => ImportFormat.zoomPtcf;

  /// Returns true when [bytes] starts with the 4-byte ASCII `PTCF` header.
  static bool hasPtcfMagic(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 && // 'P'
        bytes[1] == 0x54 && // 'T'
        bytes[2] == 0x43 && // 'C'
        bytes[3] == 0x46; // 'F'
  }

  @override
  bool canHandle({required Uint8List bytes, String? fileName}) {
    return hasPtcfMagic(bytes);
  }

  @override
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  }) {
    return decodePtcfBytes(
      bytes,
      detectedFormat: format,
      sourceName: sourceName,
      sourcePath: sourcePath,
      targetDeviceHint: targetDeviceHint,
    );
  }

  /// Shared PTCF binary decoder used by [ZoomPtcfImportAdapter],
  /// [SymbiosisImportAdapter], and [ZoomMultistompStudioImportAdapter].
  static ImportBatchResult decodePtcfBytes(
    Uint8List bytes, {
    required ImportFormat detectedFormat,
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
    DeviceFamily? forcedFamily,
    int? fallbackProgramNumber,
  }) {
    if (bytes.length < minPtcfBytes || !hasPtcfMagic(bytes)) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: bytes.length < minPtcfBytes
                ? 'PTCF file is too short (${bytes.length} bytes, minimum $minPtcfBytes).'
                : 'Invalid PTCF header: expected "PTCF" magic bytes.',
          ),
        ],
      );
    }

    final warnings = <String>[];
    final bd = ByteData.sublistView(bytes);
    final declaredLength = bd.getUint32(4, Endian.little);
    final numEffects = bd.getUint32(12, Endian.little);
    final targetMask = bd.getUint32(16, Endian.little);

    if (declaredLength < minPtcfBytes) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Corrupted PTCF length field ($declaredLength bytes).',
          ),
        ],
      );
    }

    if (bytes.length < declaredLength) {
      warnings.add(
        'PTCF payload is truncated (${bytes.length} bytes present, header declares $declaredLength); attempting partial decode.',
      );
    }

    if (numEffects == 0 || numEffects > ZoomMsPlusProtocol.defaultMaxSlots) {
      warnings.add('Unusual PTCF effect slot count ($numEffects).');
    }

    // Resolve Zoom MS Plus family from explicit override, target mask, or hint.
    final DeviceFamily defaultFamily;
    if (forcedFamily != null && forcedFamily.isZoomMsPlus) {
      defaultFamily = forcedFamily;
      if ((targetMask & ZoomMsPlusProtocol.ptcfTargetMs60bPlus) != 0 &&
          forcedFamily != DeviceFamily.zoomMs60bPlus) {
        warnings.add(
          'PTCF target mask indicates MS-60B+, but filename specifies ${forcedFamily.displayName}; using ${forcedFamily.displayName}.',
        );
      } else if ((targetMask & ZoomMsPlusProtocol.ptcfTargetMs50gPlus) != 0 &&
          forcedFamily == DeviceFamily.zoomMs60bPlus) {
        warnings.add(
          'PTCF target mask indicates MS-50G+/70CDR+/200D+, but filename specifies MS-60B+; using MS-60B+.',
        );
      }
    } else if ((targetMask & ZoomMsPlusProtocol.ptcfTargetMs60bPlus) != 0) {
      defaultFamily = DeviceFamily.zoomMs60bPlus;
    } else if ((targetMask & ZoomMsPlusProtocol.ptcfTargetMs50gPlus) != 0) {
      if (targetDeviceHint == DeviceFamily.zoomMs70cdrPlus ||
          targetDeviceHint == DeviceFamily.zoomMs200dPlus) {
        defaultFamily = targetDeviceHint!;
      } else {
        defaultFamily = DeviceFamily.zoomMs50gPlus;
        if (targetDeviceHint == null || targetDeviceHint == DeviceFamily.zoomMs60bPlus) {
          warnings.add(
            'PTCF target mask 0x00040000 is shared by MS-50G+, MS-70CDR+, and MS-200D+; inferred ${defaultFamily.displayName}.',
          );
        }
      }
    } else {
      defaultFamily = (targetDeviceHint != null && targetDeviceHint.isZoomMsPlus)
          ? targetDeviceHint
          : DeviceFamily.zoomMs60bPlus;
      warnings.add(
        'PTCF target mask (0x${targetMask.toRadixString(16)}) is unrecognized; defaulted to ${defaultFamily.displayName}.',
      );
    }

    try {
      final protocol = ZoomMsPlusProtocol(defaultFamily: defaultFamily);
      var patch = protocol.decodePtcf(
        bytes,
        programNumber: fallbackProgramNumber,
      );

      // Ensure forcedFamily (e.g. Symbiosis suffix) overrides decodePtcf's target-mask guess.
      if (forcedFamily != null && patch.deviceFamily != forcedFamily) {
        patch = patch.copyWith(deviceFamily: forcedFamily);
      }

      if (patch.slots.isEmpty) {
        return ImportBatchResult(
          totalSourcesScanned: 1,
          diagnostics: [
            ImportDiagnostic(
              severity: ImportDiagnosticSeverity.error,
              sourceName: sourceName,
              sourcePath: sourcePath,
              message: 'PTCF container decoded 0 effect slots (missing or truncated EDTB chunk).',
            ),
          ],
        );
      }

      // Check ASCII magic sanity in case name is empty
      if (patch.name.trim().isEmpty) {
        patch = patch.copyWith(name: _fallbackNameFromSource(sourceName));
      }

      return ImportBatchResult(
        totalSourcesScanned: 1,
        entries: [
          ImportedPatchEntry(
            patch: patch,
            detectedFormat: detectedFormat,
            inferredDeviceFamily: patch.deviceFamily,
            sourceName: sourceName,
            sourcePath: sourcePath,
            warnings: warnings,
          ),
        ],
      );
    } catch (e) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Failed to decode PTCF payload: $e',
          ),
        ],
      );
    }
  }

  static String _fallbackNameFromSource(String sourceName) {
    final dot = sourceName.indexOf('.');
    final stem = dot > 0 ? sourceName.substring(0, dot) : sourceName;
    final clean = utf8.decode(utf8.encode(stem)).trim();
    return clean.isEmpty ? 'Imported Patch' : clean;
  }
}

