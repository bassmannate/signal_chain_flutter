/// Supported external and native patch/library export formats.
enum ExportFormat {
  nativeJson(
    storageKey: 'nativeJson',
    displayName: 'Signal Chain Native JSON (.json)',
    subtitle: 'Lossless single-patch or multi-patch library bundle (All devices)',
    fileExtension: '.json',
    isBinary: false,
    supportsTextCopy: true,
    isZoomOnly: false,
  ),
  zoomPtcf(
    storageKey: 'zoomPtcf',
    displayName: 'Zoom PTCF Patch (.zptc)',
    subtitle: 'Standard 848-byte binary PTCF file for Zoom Guitar Lab / Handy Guitar Lab',
    fileExtension: '.zptc',
    isBinary: true,
    supportsTextCopy: false,
    isZoomOnly: true,
  ),
  symbiosisZptc(
    storageKey: 'symbiosisZptc',
    displayName: 'Symbiosis ZPTC (.<model>.zptc / Folder)',
    subtitle: 'Model-suffixed .zptc for single patches, or folder of .zptc files for libraries',
    fileExtension: '.zptc',
    isBinary: true,
    supportsTextCopy: false,
    isZoomOnly: true,
  ),
  zoomMultistompStudio(
    storageKey: 'zoomMultistompStudio',
    displayName: 'Zoom MultiStomp Studio (tongatron.org)',
    subtitle: 'Compatible .zptc patch export for Zoom MultiStomp Studio web app',
    fileExtension: '.zptc',
    isBinary: true,
    supportsTextCopy: false,
    isZoomOnly: true,
  ),
  rawSysEx(
    storageKey: 'rawSysEx',
    displayName: 'Raw SysEx (.syx)',
    subtitle: 'Standard F0...F7 binary SysEx dump (Zoom 0x45 / Line 6 0x02)',
    fileExtension: '.syx',
    isBinary: true,
    supportsTextCopy: true,
    isZoomOnly: false,
  );

  final String storageKey;
  final String displayName;
  final String subtitle;
  final String fileExtension;
  final bool isBinary;
  final bool supportsTextCopy;
  final bool isZoomOnly;

  const ExportFormat({
    required this.storageKey,
    required this.displayName,
    required this.subtitle,
    required this.fileExtension,
    required this.isBinary,
    required this.supportsTextCopy,
    required this.isZoomOnly,
  });

  /// Resolves an [ExportFormat] from its persisted [storageKey], or null if unrecognized.
  static ExportFormat? fromStorageString(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final format in ExportFormat.values) {
      if (format.storageKey == key || format.name == key) {
        return format;
      }
    }
    return null;
  }
}

