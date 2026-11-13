import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../../../protocols/zoom_ms_plus_protocol.dart';
import '../export_adapter.dart';
import '../export_format.dart';
import '../export_payload.dart';

/// Exports Zoom MS Plus patches as standard 848-byte binary `PTCF` (`.zptc`) files.
class ZoomPtcfExportAdapter extends ExportAdapter {
  const ZoomPtcfExportAdapter();

  @override
  ExportFormat get format => ExportFormat.zoomPtcf;

  @override
  bool supportsDevice(DeviceFamily family) => family.isZoomMsPlus;

  /// Encodes [patch] into a fixed 848-byte zero-padded `PTCF` binary buffer.
  static Uint8List encodePaddedPtcf(Patch patch) {
    final protocol = ZoomMsPlusProtocol(defaultFamily: patch.deviceFamily);
    final rawPtcf = protocol.encodePtcf(patch);
    final padded = Uint8List(ZoomMsPlusProtocol.msPlusPtcfSlotLength);
    final copyLen = rawPtcf.length < padded.length ? rawPtcf.length : padded.length;
    padded.setRange(0, copyLen, rawPtcf);
    return padded;
  }

  /// Formats a concise hex preview of [bytes] for UI inspection.
  static String formatHexPreview(Uint8List bytes, {int maxBytes = 128}) {
    final limit = bytes.length < maxBytes ? bytes.length : maxBytes;
    final hex = bytes
        .sublist(0, limit)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    return bytes.length > maxBytes
        ? '$hex ... (${bytes.length} bytes total)'
        : '$hex (${bytes.length} bytes)';
  }

  @override
  ExportPayload exportPatch(Patch patch) {
    if (!supportsDevice(patch.deviceFamily)) {
      throw UnsupportedError(
        '${format.displayName} only supports Zoom MS Plus patches (got ${patch.deviceFamily.displayName}).',
      );
    }

    final bytes = encodePaddedPtcf(patch);
    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: patch.id);
    return ExportPayload(
      format: format,
      suggestedName: '$stem.zptc',
      fileExtension: fileExtension,
      isBinary: true,
      bytes: bytes,
      previewText: 'PTCF Binary (${bytes.length} bytes)\n${formatHexPreview(bytes)}',
      exportedPatchCount: 1,
    );
  }

  @override
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'zoom_ptcf_library',
  }) {
    final entries = <ExportFileEntry>[];
    int skipped = 0;

    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      if (!supportsDevice(patch.deviceFamily)) {
        skipped++;
        continue;
      }
      final prefix = (i + 1).toString().padLeft(2, '0');
      final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: 'patch_$prefix');
      entries.add(ExportFileEntry(
        fileName: '${prefix}_$stem.zptc',
        bytes: encodePaddedPtcf(patch),
      ));
    }

    final warnings = <String>[
      if (skipped > 0)
        'Skipped $skipped non-Zoom patch${skipped == 1 ? '' : 'es'} (incompatible with PTCF).',
    ];
    final folderStem = ExportAdapter.sanitizeFileStem(libraryName, fallback: 'zoom_ptcf_library');

    return ExportPayload(
      format: format,
      suggestedName: folderStem,
      fileExtension: '',
      isBinary: true,
      isDirectoryExport: true,
      bytes: Uint8List(0),
      folderEntries: entries,
      previewText:
          'Folder Export: $folderStem/\n'
          '${entries.length} .zptc file(s) ready'
          '${skipped > 0 ? ' ($skipped non-Zoom skipped)' : ''}',
      exportedPatchCount: entries.length,
      skippedPatchCount: skipped,
      warnings: warnings,
    );
  }
}

