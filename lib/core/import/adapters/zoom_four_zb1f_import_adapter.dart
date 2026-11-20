import 'dart:convert';
import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../../../protocols/ptcf_codec.dart';
import '../../../protocols/zoom_four_protocol.dart';
import '../import_adapter.dart';
import '../import_batch_result.dart';
import '../import_format.dart';
import '../imported_patch_entry.dart';
import 'zoom_ptcf_import_adapter.dart';

/// Imports ToneLib Zoom `.zb1f` (B1X FOUR / B1 FOUR) and `.zg1f` (G1X FOUR / G1 FOUR)
/// XML/PTCF patch files as well as raw `.ptcf` binary containers named `.zb1f`/`.zg1f`.
class ZoomFourZb1fImportAdapter extends ImportAdapter {
  const ZoomFourZb1fImportAdapter();

  @override
  ImportFormat get format => ImportFormat.zoomFourZb1f;

  static bool hasZb1fExtension(String? fileName) {
    if (fileName == null || fileName.isEmpty) return false;
    final lower = fileName.toLowerCase();
    return lower.endsWith('.zb1f') || lower.endsWith('.zg1f');
  }

  static bool looksLikeToneLibXml(Uint8List bytes) {
    try {
      final sampleLen = bytes.length < 512 ? bytes.length : 512;
      final head = utf8.decode(bytes.sublist(0, sampleLen), allowMalformed: true);
      return head.contains('<ZoomPatch') || head.contains('<PatchData');
    } catch (_) {
      return false;
    }
  }

  @override
  bool canHandle({required Uint8List bytes, String? fileName}) {
    if (hasZb1fExtension(fileName)) return true;
    return looksLikeToneLibXml(bytes);
  }

  static String? _extractAttribute(String xml, String attrName) {
    final match = RegExp(
      '$attrName\\s*=\\s*["\']([^"\']*)["\']',
      caseSensitive: false,
    ).firstMatch(xml);
    return match == null ? null : _unescapeXml(match.group(1)!.trim());
  }

  static String? _extractTagText(String xml, String tagName) {
    final match = RegExp(
      '<$tagName(?:\\s[^>]*)?>([\\s\\S]*?)</$tagName>',
      caseSensitive: false,
    ).firstMatch(xml);
    return match == null ? null : _unescapeXml(match.group(1)!.trim());
  }

  static String _unescapeXml(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  static Uint8List? _decodeHex(String hexText) {
    final clean = hexText.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty || clean.length.isOdd) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) return null;
    final out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  }) {
    // Support raw binary PTCF containers saved directly with a .zb1f / .zg1f extension.
    if (ZoomPtcfImportAdapter.hasPtcfMagic(bytes)) {
      final fallback = sourceName.toLowerCase().endsWith('.zg1f')
          ? DeviceFamily.zoomG1xFour
          : DeviceFamily.zoomB1xFour;
      final hint = (targetDeviceHint != null && targetDeviceHint.isZoomFour)
          ? targetDeviceHint
          : fallback;
      final forced = (PtcfCodec.detectGeneration(bytes) == DeviceGeneration.zoomFour)
          ? null
          : hint;
      return ZoomPtcfImportAdapter.decodePtcfBytes(
        bytes,
        detectedFormat: format,
        sourceName: sourceName,
        sourcePath: sourcePath,
        forcedFamily: forced,
        targetDeviceHint: hint,
      );
    }

    final String xml;
    try {
      xml = utf8.decode(bytes);
    } catch (e) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Unable to decode ToneLib .zb1f UTF-8 content: $e',
          ),
        ],
      );
    }

    final warnings = <String>[];
    final declaredDevice =
        _extractAttribute(xml, 'device') ?? _extractTagText(xml, 'Device');
    final profileFromXml =
        declaredDevice != null ? ZoomFourProfile.fromPortName(declaredDevice) : null;
    final profileFromHint =
        targetDeviceHint != null ? ZoomFourProfile.fromDeviceFamily(targetDeviceHint) : null;
    final fallbackFamily = sourceName.toLowerCase().endsWith('.zg1f')
        ? DeviceFamily.zoomG1xFour
        : DeviceFamily.zoomB1xFour;

    // Extract Base64 or Hex PTCF payload inside <PatchData>, <PTCF>, or <data>.
    final encodingAttr = (_extractAttribute(xml, 'encoding') ?? '').toLowerCase();
    final rawPayload = _extractTagText(xml, 'PatchData') ??
        _extractTagText(xml, 'PTCF') ??
        _extractTagText(xml, 'data');

    if (rawPayload == null || rawPayload.isEmpty) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'Missing <PatchData> or <PTCF> payload inside ToneLib file.',
          ),
        ],
      );
    }

    Uint8List? ptcfBytes;
    if (encodingAttr == 'hex') {
      ptcfBytes = _decodeHex(rawPayload);
    } else {
      final normalizedB64 = rawPayload.replaceAll(RegExp(r'\s+'), '');
      try {
        ptcfBytes = Uint8List.fromList(base64Decode(normalizedB64));
      } catch (_) {
        ptcfBytes = _decodeHex(rawPayload);
      }
    }

    if (ptcfBytes == null || !PtcfCodec.isPtcfBuffer(ptcfBytes)) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'ToneLib XML payload does not contain a valid PTCF header.',
          ),
        ],
      );
    }

    final ptcfTarget = ByteData.sublistView(ptcfBytes).getUint32(16, Endian.little);
    final ptcfProfile = ZoomFourProfile.fromPtcfTarget(ptcfTarget);

    final resolvedFamily = profileFromXml?.deviceFamily ??
        ptcfProfile?.deviceFamily ??
        profileFromHint?.deviceFamily ??
        fallbackFamily;

    final slotPrefix = RegExp(r'^(\d{2})_').firstMatch(sourceName)?.group(1);
    final rawIndex = slotPrefix != null ? int.tryParse(slotPrefix) : null;
    final int? programNumber = rawIndex != null && resolvedFamily.isZoomFour
        ? (rawIndex >= ZoomFourProfile.defaultPatchDisplayOffset
            ? rawIndex - ZoomFourProfile.defaultPatchDisplayOffset
            : rawIndex)
        : rawIndex;

    final protocol = ZoomFourProtocol.forFamily(resolvedFamily);
    Patch decoded = protocol.decodePtcf(ptcfBytes, programNumber: programNumber);

    // Ensure ToneLib zoomFour files tag DeviceGeneration.zoomFour cleanly.
    if (!decoded.deviceFamily.isZoomFour) {
      decoded = decoded.copyWith(deviceFamily: resolvedFamily);
    }
    if (decoded.slots.length > ZoomFourProtocol.maxSlots) {
      warnings.add(
        'Truncated ${decoded.slots.length} slots to Zoom Four max of ${ZoomFourProtocol.maxSlots}.',
      );
      decoded = decoded.copyWith(slots: decoded.slots.sublist(0, ZoomFourProtocol.maxSlots));
    }

    final xmlName = _extractTagText(xml, 'Name');
    final xmlDescription = _extractTagText(xml, 'Description');
    final xmlAuthor = _extractTagText(xml, 'Author');
    final xmlTempo = int.tryParse(_extractAttribute(xml, 'tempo') ?? '');

    final enriched = decoded.copyWith(
      name: (xmlName != null && xmlName.isNotEmpty) ? xmlName : decoded.name,
      notes: (xmlDescription != null && xmlDescription.isNotEmpty)
          ? xmlDescription
          : decoded.notes,
      author: (xmlAuthor != null && xmlAuthor.isNotEmpty) ? xmlAuthor : decoded.author,
      metadata: {
        ...decoded.metadata,
        if (xmlTempo != null && xmlTempo >= 40 && xmlTempo <= 250) 'tempo': xmlTempo,
        'generation': DeviceGeneration.zoomFour.name,
        'sourceFormat': 'zb1f',
      },
    );

    if (PtcfCodec.detectGeneration(ptcfBytes) == DeviceGeneration.zoomMsPlus) {
      warnings.add(
        'Embedded PTCF carried an MS Plus target mask inside a .zb1f/.zg1f container; tagged as ${enriched.deviceFamily.displayName}.',
      );
    }

    return ImportBatchResult(
      totalSourcesScanned: 1,
      entries: [
        ImportedPatchEntry(
          patch: enriched,
          detectedFormat: format,
          inferredDeviceFamily: enriched.deviceFamily,
          sourceName: sourceName,
          sourcePath: sourcePath,
          warnings: warnings,
        ),
      ],
    );
  }
}
