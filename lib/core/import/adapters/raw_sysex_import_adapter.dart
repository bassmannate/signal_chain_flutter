import 'dart:typed_data';

import '../../../models/device_family.dart';
import '../../../models/patch.dart';
import '../../../protocols/line6_bass_pod_pro_protocol.dart';
import '../../../protocols/sysex_codec.dart';
import '../../../protocols/zoom_ms_plus_protocol.dart';
import '../../midi/midi_message.dart';
import '../import_adapter.dart';
import '../import_batch_result.dart';
import '../import_format.dart';
import '../imported_patch_entry.dart';

/// Imports single-message and multi-message `.syx` SysEx dumps for
/// Zoom MS Plus (`0x45` 989-byte / `64 12 01`) and Line 6 Bass POD Pro (`0x02` 170/169-byte).
class RawSysExImportAdapter extends ImportAdapter {
  const RawSysExImportAdapter();

  @override
  ImportFormat get format => ImportFormat.rawSysEx;

  @override
  bool canHandle({required Uint8List bytes, String? fileName}) {
    if (bytes.isEmpty) return false;
    for (final b in bytes) {
      if (b == 0xF0) return true;
      if (b != 0x00 && b != 0x20 && b != 0x0A && b != 0x0D && b != 0x09) {
        break;
      }
    }
    return false;
  }

  /// Attempts to parse ASCII hex SysEx text (e.g., `"F0 52 00 6E ... F7"`),
  /// returning null if [text] does not represent hex SysEx bytes.
  static Uint8List? tryParseHexSysExText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^f0\b', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    final cleaned = trimmed.replaceAll(RegExp(r'[^0-9a-fA-F]+'), ' ').trim();
    if (cleaned.isEmpty) return null;
    final tokens = cleaned.split(RegExp(r'\s+'));
    final bytes = <int>[];
    for (final token in tokens) {
      if (token.length > 2) return null;
      final parsed = int.tryParse(token, radix: 16);
      if (parsed == null || parsed < 0 || parsed > 255) return null;
      bytes.add(parsed);
    }
    if (bytes.isEmpty || bytes.first != 0xF0) return null;
    return Uint8List.fromList(bytes);
  }

  /// Splits a `.syx` byte stream into individual `F0 ... F7` frames plus any
  /// framing diagnostics (such as unclosed/truncated `F0` frames).
  static ({List<Uint8List> frames, List<String> errors}) splitSysExFrames(
    Uint8List bytes,
  ) {
    final frames = <Uint8List>[];
    final errors = <String>[];
    int? frameStart;

    for (int i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0xF0) {
        if (frameStart != null) {
          errors.add(
            'Truncated SysEx frame at byte $frameStart (new 0xF0 encountered before 0xF7).',
          );
        }
        frameStart = i;
      } else if (b == 0xF7) {
        if (frameStart != null) {
          frames.add(Uint8List.sublistView(bytes, frameStart, i + 1));
          frameStart = null;
        }
      }
    }

    if (frameStart != null) {
      errors.add(
        'Truncated SysEx frame starting at byte $frameStart (missing terminating 0xF7).',
      );
    }

    return (frames: frames, errors: errors);
  }

  @override
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  }) {
    if (bytes.isEmpty) {
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: [
          ImportDiagnostic(
            severity: ImportDiagnosticSeverity.error,
            sourceName: sourceName,
            sourcePath: sourcePath,
            message: 'SysEx file is empty.',
          ),
        ],
      );
    }

    final split = splitSysExFrames(bytes);
    final entries = <ImportedPatchEntry>[];
    final diagnostics = <ImportDiagnostic>[
      for (final err in split.errors)
        ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: sourceName,
          sourcePath: sourcePath,
          message: err,
        ),
    ];

    if (split.frames.isEmpty) {
      if (diagnostics.isEmpty) {
        diagnostics.add(ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: sourceName,
          sourcePath: sourcePath,
          message: 'No valid F0...F7 SysEx frames found.',
        ));
      }
      return ImportBatchResult(
        totalSourcesScanned: 1,
        diagnostics: diagnostics,
      );
    }

    final zoomDefault = (targetDeviceHint != null && targetDeviceHint.isZoomMsPlus)
        ? targetDeviceHint
        : DeviceFamily.zoomMs60bPlus;
    final zoomProto = ZoomMsPlusProtocol(defaultFamily: zoomDefault);
    const line6Proto = Line6BassPodProProtocol();

    for (int i = 0; i < split.frames.length; i++) {
      final frame = split.frames[i];
      final msg = MidiMessage(frame, timestamp: DateTime.now());
      final frameLabel = split.frames.length > 1 ? '$sourceName [msg #${i + 1}]' : sourceName;

      try {
        if (zoomProto.isPatchDump(msg)) {
          final warnings = <String>[];
          _validateZoomCrc(frame, warnings);
          final Patch patch = zoomProto.decodePatch(msg);
          if (patch.slots.isEmpty) {
            diagnostics.add(ImportDiagnostic(
              severity: ImportDiagnosticSeverity.error,
              sourceName: frameLabel,
              sourcePath: sourcePath,
              message: 'Zoom SysEx patch dump decoded 0 effect slots.',
            ));
            continue;
          }
          entries.add(ImportedPatchEntry(
            patch: patch,
            detectedFormat: format,
            inferredDeviceFamily: patch.deviceFamily,
            sourceName: sourceName,
            sourcePath: sourcePath,
            messageIndex: split.frames.length > 1 ? i : null,
            warnings: warnings,
          ));
        } else if (line6Proto.isPatchDump(msg)) {
          final Patch patch = line6Proto.decodePatch(msg);
          entries.add(ImportedPatchEntry(
            patch: patch,
            detectedFormat: format,
            inferredDeviceFamily: DeviceFamily.line6BassPodPro,
            sourceName: sourceName,
            sourcePath: sourcePath,
            messageIndex: split.frames.length > 1 ? i : null,
          ));
        } else {
          diagnostics.add(ImportDiagnostic(
            severity: ImportDiagnosticSeverity.skipped,
            sourceName: frameLabel,
            sourcePath: sourcePath,
            message: 'Skipped non-patch or unsupported SysEx frame (${frame.length} bytes).',
          ));
        }
      } catch (e) {
        diagnostics.add(ImportDiagnostic(
          severity: ImportDiagnosticSeverity.error,
          sourceName: frameLabel,
          sourcePath: sourcePath,
          message: 'Failed to decode SysEx frame: $e',
        ));
      }
    }

    return ImportBatchResult(
      entries: entries,
      diagnostics: diagnostics,
      totalSourcesScanned: 1,
    );
  }

  static void _validateZoomCrc(Uint8List frame, List<String> warnings) {
    // Standard Zoom MS Plus 0x45 (989 bytes) or 64 12 01 (985 bytes):
    // 5-byte 7-bit CRC precedes trailing 0xF7.
    final bool isSlotV2 = frame.length == 989 &&
        frame[4] == ZoomMsPlusProtocol.cmdMemoryPatchDump &&
        frame[5] == 0x00 &&
        frame[6] == 0x00;
    final bool isCurrentV2 = frame.length == 985 &&
        frame[4] == 0x64 &&
        frame[5] == ZoomMsPlusProtocol.cmdCurrentPatchDump &&
        frame[6] == 0x01;

    if (!isSlotV2 && !isCurrentV2) return;

    final int offset = isSlotV2 ? 13 : 9;
    final int crcStart = frame.length - 6;
    if (crcStart <= offset) return;

    final unpacked = SysexCodec.unpack7BitTo8Bit(
      frame,
      start: offset,
      end: crcStart - 1,
    );
    if (unpacked.length != ZoomMsPlusProtocol.msPlusPtcfSlotLength) return;

    final expectedCrc = SysexCodec.calculateZoom7BitCrc(unpacked);
    for (int i = 0; i < 5; i++) {
      if (frame[crcStart + i] != expectedCrc[i]) {
        warnings.add(
          'Zoom SysEx CRC mismatch; patch data may have been modified externally.',
        );
        return;
      }
    }
  }
}

