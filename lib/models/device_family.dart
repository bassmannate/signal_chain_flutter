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

  /// Returns true if this device is a Line 6 Bass Pod Pro.
  bool get isLine6BassPodPro => this == line6BassPodPro;

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

