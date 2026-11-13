import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../import_adapter.dart';
import '../import_batch_result.dart';
import '../import_format.dart';
import 'zoom_ptcf_import_adapter.dart';

/// Imports Zoom MultiStomp Studio (`.zptc`) patch files.
///
/// MultiStomp Studio `.zptc` files use the standard binary `PTCF` container;
/// this adapter delegates decoding to [ZoomPtcfImportAdapter.decodePtcfBytes]
/// while preserving [ImportFormat.zoomMultiStompStudio] when selected explicitly
/// or identified by filename hints.
class ZoomMultistompStudioImportAdapter extends ImportAdapter {
  const ZoomMultistompStudioImportAdapter();

  @override
  ImportFormat get format => ImportFormat.zoomMultiStompStudio;

  @override
  bool canHandle({required Uint8List bytes, String? fileName}) {
    if (!ZoomPtcfImportAdapter.hasPtcfMagic(bytes)) return false;
    final lower = fileName?.toLowerCase() ?? '';
    return lower.contains('multistomp') || lower.contains('tongatron');
  }

  @override
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  }) {
    return ZoomPtcfImportAdapter.decodePtcfBytes(
      bytes,
      detectedFormat: format,
      sourceName: sourceName,
      sourcePath: sourcePath,
      targetDeviceHint: targetDeviceHint,
    );
  }
}

