import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../export_adapter.dart';
import '../export_format.dart';
import '../export_payload.dart';
import 'zoom_ptcf_export_adapter.dart';

/// Exports Zoom MS Plus patches for Zoom MultiStomp Studio (`https://zoommultistompstudio.tongatron.org/`).
///
/// Defaults to standard 848-byte `PTCF` (`.zptc`) output, isolated behind its own
/// [ExportAdapter] so custom Tongatron wrapper fields can be added cleanly if needed.
class ZoomMultistompStudioExportAdapter extends ExportAdapter {
  const ZoomMultistompStudioExportAdapter();

  @override
  ExportFormat get format => ExportFormat.zoomMultistompStudio;

  @override
  bool supportsDevice(DeviceFamily family) => family.isZoomMsPlus;

  @override
  ExportPayload exportPatch(Patch patch) {
    if (!supportsDevice(patch.deviceFamily)) {
      throw UnsupportedError(
        '${format.displayName} only supports Zoom MS Plus patches (got ${patch.deviceFamily.displayName}).',
      );
    }

    final bytes = ZoomPtcfExportAdapter.encodePaddedPtcf(patch);
    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: patch.id);
    return ExportPayload(
      format: format,
      suggestedName: '$stem.zptc',
      fileExtension: fileExtension,
      isBinary: true,
      bytes: bytes,
      previewText:
          'Zoom MultiStomp Studio (.zptc, ${bytes.length} bytes)\n'
          '${ZoomPtcfExportAdapter.formatHexPreview(bytes)}',
      exportedPatchCount: 1,
    );
  }

  @override
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'tongatron_studio_backup',
  }) {
    final entries = <ExportFileEntry>[];
    int skipped = 0;

    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      if (!supportsDevice(patch.deviceFamily)) {
        skipped++;
        continue;
      }
      final prefix = (patch.programNumber ?? i).toString().padLeft(2, '0');
      final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: 'patch_$prefix');
      entries.add(ExportFileEntry(
        fileName: '${prefix}_$stem.zptc',
        bytes: ZoomPtcfExportAdapter.encodePaddedPtcf(patch),
      ));
    }

    final warnings = <String>[
      if (skipped > 0)
        'Skipped $skipped non-Zoom patch${skipped == 1 ? '' : 'es'} (incompatible with Zoom MultiStomp Studio).',
    ];
    final folderStem = ExportAdapter.sanitizeFileStem(libraryName, fallback: 'tongatron_studio_backup');

    return ExportPayload(
      format: format,
      suggestedName: folderStem,
      fileExtension: '',
      isBinary: true,
      isDirectoryExport: true,
      bytes: Uint8List(0),
      folderEntries: entries,
      previewText:
          'Zoom MultiStomp Studio Folder: $folderStem/\n'
          '${entries.length} .zptc file(s) ready'
          '${skipped > 0 ? ' ($skipped non-Zoom skipped)' : ''}',
      exportedPatchCount: entries.length,
      skippedPatchCount: skipped,
      warnings: warnings,
    );
  }
}

