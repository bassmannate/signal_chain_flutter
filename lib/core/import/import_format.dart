/// Supported external and native patch/library import formats.
enum ImportFormat {
  signalChainJson(
    storageKey: 'signalChainJson',
    displayName: 'Signal Chain Native JSON (.json)',
    subtitle: 'Single-patch or multi-patch library bundle JSON',
    fileExtensions: ['.json'],
    isBinary: false,
  ),
  zoomPtcf(
    storageKey: 'zoomPtcf',
    displayName: 'Zoom PTCF (.zptc)',
    subtitle: 'Standard binary PTCF patch container for Zoom MS Plus',
    fileExtensions: ['.zptc'],
    isBinary: true,
  ),
  symbiosisPtcf(
    storageKey: 'symbiosisPtcf',
    displayName: 'Symbiosis ZPTC (.<model>.zptc)',
    subtitle: 'Model-suffixed Symbiosis .zptc file or batch backup folder',
    fileExtensions: ['.60bp.zptc', '.50gp.zptc', '.70cdrp.zptc', '.200dp.zptc'],
    isBinary: true,
  ),
  zoomMultiStompStudio(
    storageKey: 'zoomMultiStompStudio',
    displayName: 'Zoom MultiStomp Studio (.zptc)',
    subtitle: 'Zoom MultiStomp Studio .zptc patch export',
    fileExtensions: ['.zptc'],
    isBinary: true,
  ),
  rawSysEx(
    storageKey: 'rawSysEx',
    displayName: 'Raw SysEx (.syx)',
    subtitle: 'MIDI SysEx dump (Zoom 0x45 / 64 12 01, Line 6 0x02)',
    fileExtensions: ['.syx'],
    isBinary: true,
  ),
  unknown(
    storageKey: 'unknown',
    displayName: 'Unknown Format',
    subtitle: 'Unrecognized file or text payload',
    fileExtensions: [],
    isBinary: true,
  );

  final String storageKey;
  final String displayName;
  final String subtitle;
  final List<String> fileExtensions;
  final bool isBinary;

  const ImportFormat({
    required this.storageKey,
    required this.displayName,
    required this.subtitle,
    required this.fileExtensions,
    required this.isBinary,
  });
}

