import 'dart:convert';
import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../export_adapter.dart';
import '../export_format.dart';
import '../export_payload.dart';

/// Exports single patches or full libraries in Signal Chain Native JSON (`.json`).
class NativeJsonExportAdapter extends ExportAdapter {
  const NativeJsonExportAdapter();

  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  ExportFormat get format => ExportFormat.nativeJson;

  @override
  bool supportsDevice(DeviceFamily family) => true;

  @override
  ExportPayload exportPatch(Patch patch) {
    final jsonStr = _encoder.convert(patch.toJson());
    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: patch.id);
    return ExportPayload(
      format: format,
      suggestedName: '$stem.json',
      fileExtension: fileExtension,
      isBinary: false,
      bytes: Uint8List.fromList(utf8.encode(jsonStr)),
      previewText: jsonStr,
      exportedPatchCount: 1,
    );
  }

  @override
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'signal_chain_library',
  }) {
    final bundle = {
      'format': 'signal_chain_library',
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'patchCount': patches.length,
      'patches': patches.map((p) => p.toJson()).toList(),
    };
    final jsonStr = _encoder.convert(bundle);
    final stem = ExportAdapter.sanitizeFileStem(libraryName, fallback: 'signal_chain_library');
    return ExportPayload(
      format: format,
      suggestedName: '$stem.json',
      fileExtension: fileExtension,
      isBinary: false,
      bytes: Uint8List.fromList(utf8.encode(jsonStr)),
      previewText: jsonStr,
      exportedPatchCount: patches.length,
    );
  }
}

