import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../export_adapter.dart';
import '../export_format.dart';
import '../export_payload.dart';
import 'zoom_ptcf_export_adapter.dart';

/// Exports Zoom MS Plus patches for Symbiosis (`https://sym.bios.is/`).
///
/// Single patches use model-suffixed `.zptc` filenames (`.60bp.zptc`, `.50gp.zptc`,
/// `.70cdrp.zptc`, `.200dp.zptc`) containing the 848-byte `PTCF` binary container.
/// Full library/bank backups export as a folder of individual model-suffixed `.zptc` files.
class SymbiosisExportAdapter extends ExportAdapter {
  const SymbiosisExportAdapter();

  @override
  ExportFormat get format => ExportFormat.symbiosisZptc;

  @override
  bool supportsDevice(DeviceFamily family) => family.isZoomMsPlus;

  /// Returns the Symbiosis model suffix for [family].
  static String modelSuffixFor(DeviceFamily family) {
    switch (family) {
      case DeviceFamily.zoomMs60bPlus:
        return '.60bp.zptc';
      case DeviceFamily.zoomMs50gPlus:
        return '.50gp.zptc';
      case DeviceFamily.zoomMs70cdrPlus:
        return '.70cdrp.zptc';
      case DeviceFamily.zoomMs200dPlus:
        return '.200dp.zptc';
      case DeviceFamily.line6BassPodPro:
      case DeviceFamily.unknown:
        return '.zptc';
    }
  }

  @override
  ExportPayload exportPatch(Patch patch) {
    if (!supportsDevice(patch.deviceFamily)) {
      throw UnsupportedError(
        '${format.displayName} only supports Zoom MS Plus patches (got ${patch.deviceFamily.displayName}).',
      );
    }

    final bytes = ZoomPtcfExportAdapter.encodePaddedPtcf(patch);
    final suffix = modelSuffixFor(patch.deviceFamily);
    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: patch.id);

    return ExportPayload(
      format: format,
      suggestedName: '$stem$suffix',
      fileExtension: suffix,
      isBinary: true,
      bytes: bytes,
      previewText:
          'Symbiosis ZPTC ($suffix, ${bytes.length} bytes)\n'
          '${ZoomPtcfExportAdapter.formatHexPreview(bytes)}',
      exportedPatchCount: 1,
    );
  }

  @override
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'symbiosis_backup',
  }) {
    final entries = <ExportFileEntry>[];
    int skipped = 0;

    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      if (!supportsDevice(patch.deviceFamily)) {
        skipped++;
        continue;
      }
      final slotPrefix = (patch.programNumber ?? i).toString().padLeft(2, '0');
      final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: 'patch_$slotPrefix');
      final suffix = modelSuffixFor(patch.deviceFamily);
      entries.add(ExportFileEntry(
        fileName: '${slotPrefix}_$stem$suffix',
        bytes: ZoomPtcfExportAdapter.encodePaddedPtcf(patch),
      ));
    }

    final warnings = <String>[
      if (skipped > 0)
        'Skipped $skipped non-Zoom patch${skipped == 1 ? '' : 'es'} (incompatible with Symbiosis ZPTC).',
    ];
    final folderStem = ExportAdapter.sanitizeFileStem(libraryName, fallback: 'symbiosis_backup');

    return ExportPayload(
      format: format,
      suggestedName: folderStem,
      fileExtension: '',
      isBinary: true,
      isDirectoryExport: true,
      bytes: Uint8List(0),
      folderEntries: entries,
      previewText:
          'Symbiosis Batch Folder: $folderStem/\n'
          '${entries.length} model-suffixed .zptc file(s) ready'
          '${skipped > 0 ? ' ($skipped non-Zoom skipped)' : ''}',
      exportedPatchCount: entries.length,
      skippedPatchCount: skipped,
      warnings: warnings,
    );
  }
}

