import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../import_adapter.dart';
import '../import_batch_result.dart';
import '../import_format.dart';
import 'zoom_ptcf_import_adapter.dart';

/// Imports Symbiosis model-suffixed `.zptc` files (`.60bp.zptc`, `.50gp.zptc`,
/// `.70cdrp.zptc`, `.200dp.zptc`).
class SymbiosisImportAdapter extends ImportAdapter {
  const SymbiosisImportAdapter();

  static const Map<String, DeviceFamily> suffixToFamily = {
    '.60bp.zptc': DeviceFamily.zoomMs60bPlus,
    '.50gp.zptc': DeviceFamily.zoomMs50gPlus,
    '.70cdrp.zptc': DeviceFamily.zoomMs70cdrPlus,
    '.200dp.zptc': DeviceFamily.zoomMs200dPlus,
  };

  @override
  ImportFormat get format => ImportFormat.symbiosisPtcf;

  /// Infers the exact Zoom MS Plus [DeviceFamily] from a Symbiosis filename suffix,
  /// or returns null if [fileName] does not carry a recognized Symbiosis suffix.
  static DeviceFamily? inferFamilyFromFileName(String? fileName) {
    if (fileName == null || fileName.isEmpty) return null;
    final lower = fileName.toLowerCase();
    for (final entry in suffixToFamily.entries) {
      if (lower.endsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Extracts a leading two-digit slot index from Symbiosis batch filenames such as
  /// `03_Slap_Funk.60bp.zptc`.
  static int? extractSlotPrefix(String fileName) {
    final match = RegExp(r'^(\d{2})_').firstMatch(fileName);
    if (match == null) return null;
    final parsed = int.tryParse(match.group(1)!);
    if (parsed == null || parsed < 0 || parsed > 99) return null;
    return parsed;
  }

  @override
  bool canHandle({required Uint8List bytes, String? fileName}) {
    return ZoomPtcfImportAdapter.hasPtcfMagic(bytes) &&
        inferFamilyFromFileName(fileName) != null;
  }

  @override
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  }) {
    final inferredFamily = inferFamilyFromFileName(sourceName);
    final slotPrefix = extractSlotPrefix(sourceName);
    return ZoomPtcfImportAdapter.decodePtcfBytes(
      bytes,
      detectedFormat: format,
      sourceName: sourceName,
      sourcePath: sourcePath,
      targetDeviceHint: targetDeviceHint,
      forcedFamily: inferredFamily,
      fallbackProgramNumber: slotPrefix,
    );
  }
}

