import 'zoom_four_profile.dart';
export 'zoom_four_profile.dart';

/// Hardware generation families used to enforce preset-to-pedal compatibility.
enum DeviceGeneration {
  zoomMsPlus('Zoom MS+ Series'),
  zoomFour('Zoom Four Series'),
  zoomOn('Zoom On Series'),
  line6Pod('Line 6 POD Series'),
  unknown('Unknown Generation');

  final String displayName;
  const DeviceGeneration(this.displayName);
}

/// Enumeration of supported hardware processor families and models.
enum DeviceFamily {
  zoomMs50gPlus(
    displayName: 'Zoom MS-50G+',
    manufacturer: 'Zoom',
    maxEffectSlots: 6,
  ),
  zoomMs60bPlus(
    displayName: 'Zoom MS-60B+',
    manufacturer: 'Zoom',
    maxEffectSlots: 6,
  ),
  zoomMs70cdrPlus(
    displayName: 'Zoom MS-70CDR+',
    manufacturer: 'Zoom',
    maxEffectSlots: 6,
  ),
  zoomMs200dPlus(
    displayName: 'Zoom MS-200D+',
    manufacturer: 'Zoom',
    maxEffectSlots: 6,
  ),
  zoomB1xFour(
    displayName: 'Zoom B1X FOUR',
    manufacturer: 'Zoom',
    maxEffectSlots: 5,
  ),
  zoomB1Four(
    displayName: 'Zoom B1 FOUR',
    manufacturer: 'Zoom',
    maxEffectSlots: 5,
  ),
  zoomG1xFour(
    displayName: 'Zoom G1X FOUR',
    manufacturer: 'Zoom',
    maxEffectSlots: 5,
  ),
  zoomG1Four(
    displayName: 'Zoom G1 FOUR',
    manufacturer: 'Zoom',
    maxEffectSlots: 5,
  ),
  line6BassPodPro(
    displayName: 'Line 6 Bass Pod Pro',
    manufacturer: 'Line 6',
    maxEffectSlots: 4,
  ),
  unknown(
    displayName: 'Unknown Device',
    manufacturer: 'Generic',
    maxEffectSlots: 0,
  );

  final String displayName;
  final String manufacturer;
  final int maxEffectSlots;

  const DeviceFamily({
    required this.displayName,
    required this.manufacturer,
    required this.maxEffectSlots,
  });

  /// Returns true if this device is part of the Zoom MS Plus family.
  bool get isZoomMsPlus =>
      this == zoomMs50gPlus ||
      this == zoomMs60bPlus ||
      this == zoomMs70cdrPlus ||
      this == zoomMs200dPlus;

  /// Returns true if this device is part of the Zoom Four series (`B1X/B1/G1X/G1 FOUR`).
  bool get isZoomFour =>
      this == zoomB1xFour ||
      this == zoomB1Four ||
      this == zoomG1xFour ||
      this == zoomG1Four;

  /// Returns true if this device speaks the shared Zoom `0x6E` SysEx / PTCF family protocol.
  bool get isZoom6E => isZoomMsPlus || isZoomFour;

  /// Returns true if this hardware supports a configurable Right-Output (`R-Out`)
  /// signal tap point in the chain (Zoom MS+ series: MS-50G+, MS-60B+, MS-70CDR+, MS-200D+).
  bool get supportsConfigurableRightOutput => isZoomMsPlus;

  /// Hardware capability profile when this family belongs to [DeviceGeneration.zoomFour].
  ZoomFourProfile? get zoomFourProfile => ZoomFourProfile.fromDeviceFamily(this);

  /// Returns true if this hardware model has a built-in expression pedal.
  bool get hasExpressionPedal => zoomFourProfile?.hasExpressionPedal ?? false;

  /// Zero-based-to-hardware display numbering offset (`10` for Zoom Four, `0` otherwise).
  int get hardwarePatchDisplayOffset =>
      isZoomFour ? ZoomFourProfile.defaultPatchDisplayOffset : 0;

  /// Formats a zero-based patch slot index using hardware numbering conventions
  /// (`"10"`..`"59"` for Zoom Four; `"00"`..`"99"` for MS Plus).
  String formatHardwarePatchLabel(int slotIndex) => isZoomFour
      ? ZoomFourProfile.formatPatchLabel(slotIndex)
      : slotIndex.toString().padLeft(2, '0');

  /// Returns true if this device is a Line 6 Bass Pod Pro.
  bool get isLine6BassPodPro => this == line6BassPodPro;

  /// Whether the hardware displays its signal chain Right-to-Left (`MS-60B+` / MS Plus).
  /// Zoom Four (`B1X FOUR` / `B1 FOUR` / `G1X FOUR` / `G1 FOUR`) and Line 6 display Left-to-Right.
  bool get isSignalChainRightToLeft => isZoomMsPlus;

  /// Whether the hardware displays its signal chain Left-to-Right.
  bool get isSignalChainLeftToRight => !isZoomMsPlus;

  /// Hardware generation this device family belongs to.
  DeviceGeneration get generation {
    switch (this) {
      case DeviceFamily.zoomMs50gPlus:
      case DeviceFamily.zoomMs60bPlus:
      case DeviceFamily.zoomMs70cdrPlus:
      case DeviceFamily.zoomMs200dPlus:
        return DeviceGeneration.zoomMsPlus;
      case DeviceFamily.zoomB1xFour:
      case DeviceFamily.zoomB1Four:
      case DeviceFamily.zoomG1xFour:
      case DeviceFamily.zoomG1Four:
        return DeviceGeneration.zoomFour;
      case DeviceFamily.line6BassPodPro:
        return DeviceGeneration.line6Pod;
      case DeviceFamily.unknown:
        return DeviceGeneration.unknown;
    }
  }

  /// Returns true if both families belong to the same known hardware generation
  /// (for example, MS-50G+ and MS-60B+ share [DeviceGeneration.zoomMsPlus]).
  bool isSameGeneration(DeviceFamily other) =>
      generation != DeviceGeneration.unknown && generation == other.generation;

  /// Maximum patch name character limit supported by this hardware family.
  ///
  /// Zoom `0x6E` pedals display up to 10 characters on the hardware screen;
  /// Line 6 Bass Pod Pro stores up to 16 ASCII characters.
  int get maxNameLength {
    if (isZoom6E) return 10;
    if (isLine6BassPodPro) return 16;
    return 16;
  }

  /// Total number of persistent memory bank slots on this hardware.
  ///
  /// Zoom MS Plus features 100 slots (00 to 99); Zoom Four features 50 slots (`10` to `59`).
  int get totalMemorySlots {
    if (isZoomFour) return ZoomFourProfile.defaultTotalPatches;
    if (isZoomMsPlus) return 100;
    if (isLine6BassPodPro) return 36;
    return 100;
  }

  /// Serializes the enum instance to a stable string identifier.
  String toJson() => name;

  /// Deserializes a string identifier into a [DeviceFamily], falling back to [DeviceFamily.unknown].
  static DeviceFamily fromJson(dynamic json) {
    if (json is! String) return DeviceFamily.unknown;
    return DeviceFamily.values.firstWhere(
      (e) => e.name == json,
      orElse: () => DeviceFamily.unknown,
    );
  }
}

