import 'dart:convert';
import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../../../protocols/ptcf_codec.dart';
import '../../../protocols/zoom_four_protocol.dart';
import '../export_adapter.dart';
import '../export_format.dart';
import '../export_payload.dart';

/// Exports Zoom Four patches (`B1X FOUR`, `B1 FOUR`, `G1X FOUR`, `G1 FOUR`) in
/// ToneLib Zoom `.zb1f` (bass) / `.zg1f` (guitar) XML + Base64 `PTCF` format.
class ZoomFourZb1fExportAdapter extends ExportAdapter {
  const ZoomFourZb1fExportAdapter();

  @override
  ExportFormat get format => ExportFormat.zoomFourZb1f;

  @override
  bool supportsDevice(DeviceFamily family) => family.isZoomFour;

  /// Preferred ToneLib extension for [family] (`.zb1f` for bass, `.zg1f` for guitar).
  static String extensionForFamily(DeviceFamily family) =>
      family.zoomFourProfile?.patchExtension ?? '.zb1f';

  /// Encodes [patch] into a UTF-8 XML document embedding the 848-byte `PTCF` payload.
  static ({String xml, List<String> warnings}) buildXmlDocument(Patch patch) {
    final profile = patch.deviceFamily.zoomFourProfile ?? ZoomFourProfile.b1xFour;
    final warnings = <String>[];
    if (patch.slots.length > ZoomFourProtocol.maxSlots) {
      warnings.add(
        'Patch "${patch.name}" has ${patch.slots.length} slots; Zoom Four supports a maximum of ${ZoomFourProtocol.maxSlots}. Truncated trailing slots.',
      );
    }

    final ptcfBytes = PtcfCodec(defaultFamily: profile.deviceFamily).encodePadded(patch);
    final b64 = base64Encode(ptcfBytes);
    final safeName = _escapeXml(patch.name);
    final description = _escapeXml((patch.notes ?? patch.metadata['description']?.toString() ?? '').trim());
    final author = _escapeXml((patch.author ?? '').trim());
    final tempo = patch.tempo;

    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<ZoomPatch version="1.0" device="${_escapeXml(profile.displayName)}" '
        'generation="${DeviceGeneration.zoomFour.name}" '
        'slots="${ZoomFourProtocol.maxSlots}" '
        'hasExpressionPedal="${profile.hasExpressionPedal}" '
        'tempo="$tempo">',
      )
      ..writeln('  <Name>$safeName</Name>');

    if (description.isNotEmpty) {
      buffer.writeln('  <Description>$description</Description>');
    }
    if (author.isNotEmpty) {
      buffer.writeln('  <Author>$author</Author>');
    }

    buffer
      ..writeln(
        '  <PatchData encoding="base64" length="${ptcfBytes.length}" '
        'target="0x${profile.ptcfTargetMask.toRadixString(16).padLeft(8, '0').toUpperCase()}">$b64</PatchData>',
      )
      ..writeln('</ZoomPatch>');

    return (xml: buffer.toString(), warnings: warnings);
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  @override
  ExportPayload exportPatch(Patch patch) {
    if (!supportsDevice(patch.deviceFamily)) {
      throw UnsupportedError(
        '${format.displayName} only supports Zoom Four patches (got ${patch.deviceFamily.displayName}).',
      );
    }

    final ext = extensionForFamily(patch.deviceFamily);
    final built = buildXmlDocument(patch);
    final bytes = Uint8List.fromList(utf8.encode(built.xml));
    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: patch.id);

    return ExportPayload(
      format: format,
      suggestedName: '$stem$ext',
      fileExtension: ext,
      isBinary: false,
      bytes: bytes,
      previewText: built.xml,
      exportedPatchCount: 1,
      warnings: built.warnings,
    );
  }

  @override
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'zoom_four_tonelib_bank',
  }) {
    final entries = <ExportFileEntry>[];
    final warnings = <String>[];
    int skipped = 0;

    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      if (!supportsDevice(patch.deviceFamily)) {
        skipped++;
        continue;
      }
      final prefix = patch.deviceFamily.formatHardwarePatchLabel(patch.programNumber ?? i);
      final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: 'patch_$prefix');
      final ext = extensionForFamily(patch.deviceFamily);
      final built = buildXmlDocument(patch);
      warnings.addAll(built.warnings);
      entries.add(ExportFileEntry(
        fileName: '${prefix}_$stem$ext',
        bytes: Uint8List.fromList(utf8.encode(built.xml)),
      ));
    }

    if (skipped > 0) {
      warnings.add(
        'Skipped $skipped non-Zoom Four patch${skipped == 1 ? '' : 'es'} (incompatible with .zb1f/.zg1f).',
      );
    }

    final folderStem = ExportAdapter.sanitizeFileStem(libraryName, fallback: 'zoom_four_tonelib_bank');

    return ExportPayload(
      format: format,
      suggestedName: folderStem,
      fileExtension: '',
      isBinary: false,
      isDirectoryExport: true,
      bytes: Uint8List(0),
      folderEntries: entries,
      previewText:
          'ToneLib Zoom Four Folder: $folderStem/\n'
          '${entries.length} .zb1f/.zg1f file(s) ready'
          '${skipped > 0 ? ' ($skipped skipped)' : ''}',
      exportedPatchCount: entries.length,
      skippedPatchCount: skipped,
      warnings: warnings,
    );
  }
}

