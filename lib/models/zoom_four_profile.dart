import 'device_family.dart';

/// Hardware profiles for the Zoom Four series (`0x6E` family, 5 effect slots,
/// 50 user patches displayed as `10`–`59`).
enum ZoomFourProfile {
  b1xFour(
    displayName: 'Zoom B1X FOUR',
    shortName: 'B1X FOUR',
    subModelId: 0x0F,
    ptcfTargetMask: 0x00000080,
    hasExpressionPedal: true,
    isBass: true,
    patchExtension: '.zb1f',
    symbiosisSuffix: '.b1xf.zptc',
  ),
  b1Four(
    displayName: 'Zoom B1 FOUR',
    shortName: 'B1 FOUR',
    subModelId: 0x0E,
    ptcfTargetMask: 0x00000040,
    hasExpressionPedal: false,
    isBass: true,
    patchExtension: '.zb1f',
    symbiosisSuffix: '.b1f.zptc',
  ),
  g1xFour(
    displayName: 'Zoom G1X FOUR',
    shortName: 'G1X FOUR',
    subModelId: 0x0D,
    ptcfTargetMask: 0x00000020,
    hasExpressionPedal: true,
    isBass: false,
    patchExtension: '.zg1f',
    symbiosisSuffix: '.g1xf.zptc',
  ),
  g1Four(
    displayName: 'Zoom G1 FOUR',
    shortName: 'G1 FOUR',
    subModelId: 0x0C,
    ptcfTargetMask: 0x00000010,
    hasExpressionPedal: false,
    isBass: false,
    patchExtension: '.zg1f',
    symbiosisSuffix: '.g1f.zptc',
  );

  /// Maximum number of active effect blocks per patch on Zoom Four hardware.
  static const int defaultMaxSlots = 5;

  /// Total number of user patch memory slots (0..49).
  static const int defaultTotalPatches = 50;

  /// Hardware display offset added to zero-based slot index (0 -> "10", 49 -> "59").
  static const int defaultPatchDisplayOffset = 10;

  /// Number of patch banks on Zoom Four hardware (`10–19` through `50–59`).
  static const int totalBanks = 5;

  /// Number of patches per bank on Zoom Four hardware.
  static const int patchesPerBank = 10;

  /// Maximum patch name length stored inside Zoom Four PTCF binaries.
  static const int defaultMaxNameLength = 10;

  /// Bitmask covering all Zoom Four target bits in the PTCF header (`0x10`..`0x80`).
  static const int ptcfTargetAllMask = 0x000000F0;

  const ZoomFourProfile({
    required this.displayName,
    required this.shortName,
    required this.subModelId,
    required this.ptcfTargetMask,
    required this.hasExpressionPedal,
    required this.isBass,
    required this.patchExtension,
    required this.symbiosisSuffix,
  });

  /// Human-readable hardware name (e.g., `"Zoom B1X FOUR"`).
  final String displayName;

  /// Compact model label (e.g., `"B1X FOUR"`).
  final String shortName;

  /// Identity Reply byte 8 / sub-model identifier inside the `0x6E` family.
  final int subModelId;

  /// PTCF target word bitmask identifying this specific Four-series model.
  final int ptcfTargetMask;

  /// Whether this hardware unit includes a built-in expression pedal (`X` models).
  final bool hasExpressionPedal;

  /// Whether this unit is the bass variant (`B1X FOUR` / `B1 FOUR`).
  final bool isBass;

  /// Preferred ToneLib patch container extension (`.zb1f` or `.zg1f`).
  final String patchExtension;

  /// Symbiosis multi-device extension suffix (e.g., `.b1xf.zptc`).
  final String symbiosisSuffix;

  /// Maximum effect slots supported by this hardware profile (5).
  int get maxEffectSlots => defaultMaxSlots;

  /// Total user patch memory slots on this hardware profile (50).
  int get totalPatches => defaultTotalPatches;

  /// Hardware display numbering offset (10, producing labels `10`–`59`).
  int get patchDisplayOffset => defaultPatchDisplayOffset;

  /// Hardware generation shared by all Four-series pedals.
  DeviceGeneration get generation => DeviceGeneration.zoomFour;

  /// Corresponding [DeviceFamily] enum entry for this hardware profile.
  DeviceFamily get deviceFamily {
    switch (this) {
      case ZoomFourProfile.b1xFour:
        return DeviceFamily.zoomB1xFour;
      case ZoomFourProfile.b1Four:
        return DeviceFamily.zoomB1Four;
      case ZoomFourProfile.g1xFour:
        return DeviceFamily.zoomG1xFour;
      case ZoomFourProfile.g1Four:
        return DeviceFamily.zoomG1Four;
    }
  }

  /// Formats a zero-based patch index (`0..49`) to the hardware display label
  /// (`"10"`..`"59"`).
  static String formatPatchLabel(int patchIndex) {
    final clamped = patchIndex.clamp(0, defaultTotalPatches - 1);
    return '${clamped + defaultPatchDisplayOffset}';
  }

  /// Parses a hardware display label (`"10"`..`"59"`) back into a zero-based
  /// patch index (`0..49`), returning `null` if out of range or non-numeric.
  static int? parseHardwarePatchLabel(String label) {
    final parsed = int.tryParse(label.trim());
    if (parsed == null) return null;
    final zeroBased = parsed - defaultPatchDisplayOffset;
    if (zeroBased < 0 || zeroBased >= defaultTotalPatches) return null;
    return zeroBased;
  }

  /// Formats a zero-based bank index (`0..4`) to its hardware patch range
  /// (`"10–19"`, `"20–29"`, ..., `"50–59"`).
  static String formatBankRange(int bankIndex) {
    final clampedBank = bankIndex.clamp(0, totalBanks - 1);
    final start = (clampedBank * patchesPerBank) + defaultPatchDisplayOffset;
    final end = start + patchesPerBank - 1;
    return '$start–$end';
  }

  /// Resolves a [ZoomFourProfile] from a [DeviceFamily], or `null` if not
  /// part of [DeviceGeneration.zoomFour].
  static ZoomFourProfile? fromDeviceFamily(DeviceFamily family) {
    switch (family) {
      case DeviceFamily.zoomB1xFour:
        return ZoomFourProfile.b1xFour;
      case DeviceFamily.zoomB1Four:
        return ZoomFourProfile.b1Four;
      case DeviceFamily.zoomG1xFour:
        return ZoomFourProfile.g1xFour;
      case DeviceFamily.zoomG1Four:
        return ZoomFourProfile.g1Four;
      case DeviceFamily.zoomMs50gPlus:
      case DeviceFamily.zoomMs60bPlus:
      case DeviceFamily.zoomMs70cdrPlus:
      case DeviceFamily.zoomMs200dPlus:
      case DeviceFamily.line6BassPodPro:
      case DeviceFamily.unknown:
        return null;
    }
  }

  /// Resolves a [ZoomFourProfile] from Identity Reply sub-model byte 8.
  static ZoomFourProfile? fromSubModelByte(int subModelByte) {
    switch (subModelByte) {
      case 0x0F:
      case 0x1F:
        return ZoomFourProfile.b1xFour;
      case 0x0E:
      case 0x1E:
        return ZoomFourProfile.b1Four;
      case 0x0D:
      case 0x1D:
        return ZoomFourProfile.g1xFour;
      case 0x0C:
      case 0x1C:
        return ZoomFourProfile.g1Four;
      default:
        return null;
    }
  }

  /// Resolves a [ZoomFourProfile] from a PTCF header target word.
  static ZoomFourProfile? fromPtcfTarget(int target) {
    if ((target & ptcfTargetAllMask) == 0) return null;
    for (final profile in ZoomFourProfile.values) {
      if ((target & profile.ptcfTargetMask) != 0) {
        return profile;
      }
    }
    return ZoomFourProfile.b1xFour;
  }

  /// Detects a Zoom Four hardware profile from a USB MIDI port name string
  /// (e.g., `"ZOOM B1X FOUR MIDI 1"`, `"ZOOM B1 FOUR"`, `"ZOOM G1X FOUR"`).
  ///
  /// Returns `null` when the port name does not identify a Four-series unit,
  /// preventing collisions with MS Plus pedals (`MS-60B+`, `MS-50G+`, etc.).
  static ZoomFourProfile? fromPortName(String portName) {
    final normalized = portName.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    if (normalized.contains('b1xfour') ||
        (normalized.contains('zoom') && normalized.contains('b1x'))) {
      return ZoomFourProfile.b1xFour;
    }
    if (normalized.contains('b1four')) {
      return ZoomFourProfile.b1Four;
    }
    if (normalized.contains('g1xfour') ||
        (normalized.contains('zoom') && normalized.contains('g1x'))) {
      return ZoomFourProfile.g1xFour;
    }
    if (normalized.contains('g1four')) {
      return ZoomFourProfile.g1Four;
    }
    // Check standalone tokens like "B1X FOUR" or "B1 FOUR" when separated by punctuation.
    final rawLower = portName.toLowerCase();
    if (RegExp(r'\bb1x\s*four\b|\bb1x\b').hasMatch(rawLower)) {
      return ZoomFourProfile.b1xFour;
    }
    if (RegExp(r'\bb1\s*four\b').hasMatch(rawLower)) {
      return ZoomFourProfile.b1Four;
    }
    if (RegExp(r'\bg1x\s*four\b|\bg1x\b').hasMatch(rawLower)) {
      return ZoomFourProfile.g1xFour;
    }
    if (RegExp(r'\bg1\s*four\b').hasMatch(rawLower)) {
      return ZoomFourProfile.g1Four;
    }
    return null;
  }
}

