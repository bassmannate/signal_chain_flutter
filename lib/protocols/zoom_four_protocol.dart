import 'dart:typed_data';

import '../models/device_family.dart';
import '../models/patch.dart';
import 'zoom_ms_plus_protocol.dart';

/// Hardware protocol handler for the **Zoom Four Series** (`0x6E` family:
/// `B1X FOUR`, `B1 FOUR`, `G1X FOUR`, `G1 FOUR`).
///
/// Shares the `0x6E` SysEx transport and `PTCF` binary container with MS Plus
/// while enforcing:
/// - **5 Effect Slots maximum** per patch
/// - **50 User Patches** (`0..49`, displayed on hardware as `10..59`)
/// - Model-specific PTCF target tagging and [DeviceGeneration.zoomFour] metadata
class ZoomFourProtocol extends ZoomMsPlusProtocol {
  /// Maximum number of effect slots per patch on Zoom Four hardware.
  static const int maxSlots = ZoomFourProfile.defaultMaxSlots;

  /// Total user memory patches on Zoom Four hardware (`0..49`, labeled `10..59`).
  static const int totalPatches = ZoomFourProfile.defaultTotalPatches;

  /// Offset added to zero-based slot indices to obtain hardware patch numbers.
  static const int displayOffset = ZoomFourProfile.defaultPatchDisplayOffset;

  const ZoomFourProtocol({
    super.defaultFamily = DeviceFamily.zoomB1xFour,
  });

  /// Constructs a [ZoomFourProtocol] bound to [family] if it is part of
  /// [DeviceGeneration.zoomFour], otherwise defaulting to [DeviceFamily.zoomB1xFour].
  factory ZoomFourProtocol.forFamily(DeviceFamily family) {
    return ZoomFourProtocol(
      defaultFamily: family.isZoomFour ? family : DeviceFamily.zoomB1xFour,
    );
  }

  /// Constructs a [ZoomFourProtocol] for the given [ZoomFourProfile].
  factory ZoomFourProtocol.forProfile(ZoomFourProfile profile) {
    return ZoomFourProtocol(defaultFamily: profile.deviceFamily);
  }

  /// Active hardware profile for this protocol instance.
  ZoomFourProfile get profile =>
      ZoomFourProfile.fromDeviceFamily(defaultFamily) ?? ZoomFourProfile.b1xFour;

  /// Whether the active hardware profile includes a built-in expression pedal.
  bool get hasExpressionPedal => profile.hasExpressionPedal;

  @override
  int get maxEffectSlots => maxSlots;

  /// Convenience [PtcfCodec] bound to this Zoom Four protocol's [defaultFamily].
  PtcfCodec get ptcfCodec => PtcfCodec(defaultFamily: defaultFamily);

  /// Formats a zero-based patch index (`0..49`) using hardware numbering
  /// (`"10"`..`"59"`).
  String formatPatchNumber(int patchIndex) =>
      ZoomFourProfile.formatPatchLabel(patchIndex);

  /// Formats a bank index (`0..4`) as its hardware range (`"10–19"`..`"50–59"`).
  String formatBankRange(int bankIndex) =>
      ZoomFourProfile.formatBankRange(bankIndex);

  /// Parses a hardware patch number (`"10"`..`"59"`) back into a zero-based
  /// index (`0..49`).
  int? parsePatchNumber(String label) =>
      ZoomFourProfile.parseHardwarePatchLabel(label);

  @override
  Uint8List encodePtcf(Patch patch) {
    final normalizedPatch = patch.slots.length > maxSlots
        ? patch.copyWith(slots: patch.slots.sublist(0, maxSlots))
        : patch;
    return super.encodePtcf(normalizedPatch);
  }

  @override
  Patch decodePtcf(Uint8List ptcf, {int? programNumber}) {
    final decoded = super.decodePtcf(ptcf, programNumber: programNumber);
    final clampedSlots = decoded.slots.length > maxSlots
        ? decoded.slots.sublist(0, maxSlots)
        : decoded.slots;
    return decoded.copyWith(
      slots: clampedSlots,
      metadata: {
        ...decoded.metadata,
        'generation': DeviceGeneration.zoomFour.name,
      },
    );
  }
}
