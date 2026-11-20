import 'dart:convert';
import 'dart:typed_data';

import '../models/device_family.dart';
import '../models/patch.dart';
import 'zoom_ms_plus_protocol.dart';

/// Codec for Zoom `0x6E` `PTCF` patch binary containers across MS Plus
/// (up to 6 effect slots) and Zoom Four (`B1X FOUR`, `B1 FOUR`, `G1X FOUR`,
/// `G1 FOUR` — up to 5 effect slots).
class PtcfCodec {
  final DeviceFamily defaultFamily;

  const PtcfCodec({
    this.defaultFamily = DeviceFamily.zoomB1xFour,
  });

  /// Maximum number of effect blocks permitted by [defaultFamily].
  int get maxSlots => defaultFamily.isZoomFour
      ? ZoomFourProfile.defaultMaxSlots
      : ZoomMsPlusProtocol.defaultMaxSlots;

  /// Encodes [patch] into an unpadded raw `PTCF` binary container.
  Uint8List encode(Patch patch) {
    final effectiveFamily = patch.deviceFamily == DeviceFamily.unknown
        ? defaultFamily
        : patch.deviceFamily;
    final protocol = ZoomMsPlusProtocol(defaultFamily: effectiveFamily);
    return protocol.encodePtcf(patch);
  }

  /// Encodes [patch] into a fixed-size hardware `PTCF` slot buffer (848 bytes
  /// zero-padded).
  Uint8List encodePadded(
    Patch patch, {
    int slotLength = ZoomMsPlusProtocol.msPlusPtcfSlotLength,
  }) {
    final raw = encode(patch);
    final padded = Uint8List(slotLength);
    final copyLen = raw.length < slotLength ? raw.length : slotLength;
    padded.setRange(0, copyLen, raw);
    return padded;
  }

  /// Decodes raw `PTCF` binary bytes into a [Patch], tagging it with its
  /// resolved [DeviceFamily] and [DeviceGeneration].
  Patch decode(Uint8List ptcfBytes, {int? programNumber}) {
    final protocol = ZoomMsPlusProtocol(defaultFamily: defaultFamily);
    final decoded = protocol.decodePtcf(ptcfBytes, programNumber: programNumber);
    final cappedSlots = decoded.deviceFamily.isZoomFour &&
            decoded.slots.length > ZoomFourProfile.defaultMaxSlots
        ? decoded.slots.sublist(0, ZoomFourProfile.defaultMaxSlots)
        : decoded.slots;
    return decoded.copyWith(
      slots: cappedSlots,
      metadata: {
        ...decoded.metadata,
        'generation': decoded.deviceFamily.generation.name,
      },
    );
  }

  /// Returns `true` when [bytes] starts with the 4-byte ASCII `'PTCF'` magic header.
  static bool isPtcfBuffer(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'PTCF';
  }

  /// Inspects the `PTCF` header target word at offset `16..19` to identify the
  /// owning [DeviceGeneration] without performing a full decode.
  static DeviceGeneration detectGeneration(Uint8List ptcfBytes) {
    if (!isPtcfBuffer(ptcfBytes) || ptcfBytes.length < 20) {
      return DeviceGeneration.unknown;
    }
    final target = ByteData.sublistView(ptcfBytes).getUint32(16, Endian.little);
    if ((target & ZoomMsPlusProtocol.ptcfTargetZoomFourMask) != 0) {
      return DeviceGeneration.zoomFour;
    }
    if ((target &
            (ZoomMsPlusProtocol.ptcfTargetMs50gPlus |
                ZoomMsPlusProtocol.ptcfTargetMs60bPlus)) !=
        0) {
      return DeviceGeneration.zoomMsPlus;
    }
    return DeviceGeneration.unknown;
  }
}

