import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../../../protocols/device_protocol.dart';
import '../../../protocols/line6_bass_pod_pro_protocol.dart';
import '../../../protocols/zoom_ms_plus_protocol.dart';
import '../export_adapter.dart';
import '../export_format.dart';
import '../export_payload.dart';

/// Exports patches as standard `F0 ... F7` MIDI SysEx (`.syx`) dumps.
///
/// Uses Zoom 989-byte `0x45` memory slot SysEx for Zoom MS Plus patches and
/// Line 6 170-byte `0x02` program SysEx for Line 6 Bass POD Pro patches.
class RawSysExExportAdapter extends ExportAdapter {
  const RawSysExExportAdapter();

  @override
  ExportFormat get format => ExportFormat.rawSysEx;

  @override
  bool supportsDevice(DeviceFamily family) =>
      family.isZoomMsPlus || family.isLine6BassPodPro;

  static DeviceProtocol _protocolFor(DeviceFamily family) {
    if (family.isLine6BassPodPro) {
      return const Line6BassPodProProtocol();
    }
    return ZoomMsPlusProtocol(defaultFamily: family);
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  @override
  ExportPayload exportPatch(Patch patch) {
    final protocol = _protocolFor(patch.deviceFamily);
    final slot = patch.programNumber ?? 0;
    final bytes = protocol.encodePatch(patch, programNumber: slot).data;
    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: patch.id);

    return ExportPayload(
      format: format,
      suggestedName: '$stem.syx',
      fileExtension: fileExtension,
      isBinary: true,
      bytes: bytes,
      previewText: _toHex(bytes),
      exportedPatchCount: 1,
    );
  }

  @override
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'signal_chain_sysex_bank',
  }) {
    final combined = BytesBuilder(copy: false);
    final previewLines = <String>[];
    int exported = 0;
    int skipped = 0;

    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      if (!supportsDevice(patch.deviceFamily)) {
        skipped++;
        continue;
      }
      final protocol = _protocolFor(patch.deviceFamily);
      final slot = patch.programNumber ?? i;
      final bytes = protocol.encodePatch(patch, programNumber: slot).data;
      combined.add(bytes);
      exported++;
      if (previewLines.length < 5) {
        previewLines.add('#${slot.toString().padLeft(2, '0')} ${patch.name}: ${bytes.length} bytes');
      }
    }

    final allBytes = combined.takeBytes();
    if (exported > 5) {
      previewLines.add('... and ${exported - 5} more SysEx message(s) (${allBytes.length} bytes total)');
    }

    final stem = ExportAdapter.sanitizeFileStem(libraryName, fallback: 'signal_chain_sysex_bank');
    return ExportPayload(
      format: format,
      suggestedName: '$stem.syx',
      fileExtension: fileExtension,
      isBinary: true,
      bytes: allBytes,
      previewText: previewLines.isEmpty ? 'No compatible patches' : previewLines.join('\n'),
      exportedPatchCount: exported,
      skippedPatchCount: skipped,
      warnings: skipped > 0
          ? ['Skipped $skipped unsupported device patch${skipped == 1 ? '' : 'es'}.']
          : const [],
    );
  }
}

