import 'dart:typed_data';

/// Exception thrown when a binary buffer cannot be parsed as a valid Zoom
/// `FLST_SEQ.ZT2` onboard effect index file.
class FlstParseException implements Exception {
  final String message;

  const FlstParseException(this.message);

  @override
  String toString() => 'FlstParseException: $message';
}

/// Immutable representation of a single effect record inside `FLST_SEQ.ZT2`.
class FlstEffectEntry {
  /// NUL-trimmed ASCII effect filename (e.g., `'COMP.ZD2'`, `'MY_NAM.ZD2'`).
  final String filename;

  /// NUL-trimmed 4-byte ASCII version string (e.g., `'1.00'`).
  final String version;

  /// Normalized uppercase 32-bit hex DSP ID (`'0xXXXXXXXX'`).
  final String effectId;

  /// Raw unsigned 32-bit DSP effect ID.
  final int intEffectId;

  /// Hardware category group byte from the enclosing `>>>\0` block.
  final int groupByte;

  /// Human-readable hardware group name (e.g., `'DYNAMICS'`, `'AMP'`).
  final String groupName;

  /// True when the pedal marks this effect as installed (`installed == 1`).
  final bool installed;

  const FlstEffectEntry({
    required this.filename,
    required this.version,
    required this.effectId,
    required this.intEffectId,
    required this.groupByte,
    required this.groupName,
    required this.installed,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlstEffectEntry &&
          runtimeType == other.runtimeType &&
          filename == other.filename &&
          version == other.version &&
          effectId == other.effectId &&
          intEffectId == other.intEffectId &&
          groupByte == other.groupByte &&
          groupName == other.groupName &&
          installed == other.installed;

  @override
  int get hashCode => Object.hash(
        filename,
        version,
        effectId,
        intEffectId,
        groupByte,
        groupName,
        installed,
      );

  @override
  String toString() =>
      'FlstEffectEntry($filename, id: $effectId, v$version, '
      'group: $groupName($groupByte), installed: $installed)';
}

/// Immutable result of parsing a Zoom `FLST_SEQ.ZT2` binary buffer.
class FlstParseResult {
  /// Optional hardware model name from the file header block (e.g., `'MS-60B+'`).
  final String? deviceName;

  /// All parsed effect entries (both installed and uninstalled).
  final List<FlstEffectEntry> allEntries;

  /// Subset of [allEntries] where [FlstEffectEntry.installed] is `true`.
  final List<FlstEffectEntry> installedEntries;

  /// Authoritative set of normalized uppercase `'0xXXXXXXXX'` effect IDs
  /// currently marked installed on the pedal.
  final Set<String> installedEffectIds;

  FlstParseResult({
    this.deviceName,
    required List<FlstEffectEntry> allEntries,
  })  : allEntries = List<FlstEffectEntry>.unmodifiable(allEntries),
        installedEntries = List<FlstEffectEntry>.unmodifiable(
          allEntries.where((e) => e.installed),
        ),
        installedEffectIds = Set<String>.unmodifiable(
          allEntries.where((e) => e.installed).map((e) => e.effectId),
        );
}

/// Pure-Dart binary parser for Zoom `FLST_SEQ.ZT2` onboard effect index files
/// (Zoom MS+ and Zoom Four `0x6E` hardware families).
///
/// Binary layout (verified against `mungewell/zoom-zt2`):
/// The file is composed of 26-byte fixed-width records:
/// - **File header block** (78 bytes = 3 records):
///   - `>>>\0` + `0x00` + 21 zero bytes (26 bytes)
///   - `name` (12-byte ASCII) + 6 bytes + `0x01` + 7 bytes (26 bytes)
///   - `<<<\0` + 22 zero bytes (26 bytes)
/// - **Effect group blocks** (repeated):
///   - Group opener: `>>>\0` + `groupByte` (1 byte) + 21 padding bytes (26 bytes)
///   - Zero or more 26-byte Effect entries:
///     - `0..12`: `filename` (12-byte NUL-padded ASCII, e.g. `COMP.ZD2`)
///     - `12`: `0x00` separator
///     - `13..17`: `version` (4-byte ASCII, e.g. `1.00`)
///     - `17`: `0x00` separator
///     - `18`: `installed` flag (`0` or `1`)
///     - `19..23`: `effectId` (32-bit unsigned little-endian)
///     - `23..26`: 3 trailing zero bytes
///   - Group closer: `<<<\0` + `groupByte` (1 byte) + 21 padding bytes (26 bytes)
/// - Trailing NUL padding (e.g., padded to 8,502 bytes on Zoom Four).
class FlstSeqParser {
  const FlstSeqParser._();

  /// Fixed width of each `FLST_SEQ.ZT2` record in bytes.
  static const int recordSize = 26;

  /// Standard file header length (3 records = 78 bytes).
  static const int standardHeaderSize = recordSize * 3;

  static const int _markerOpenByte = 0x3E; // '>'
  static const int _markerCloseByte = 0x3C; // '<'

  /// Formats a 32-bit unsigned integer effect ID as uppercase `'0xXXXXXXXX'`.
  static String formatEffectId(int intEffectId) {
    final masked = intEffectId & 0xFFFFFFFF;
    return '0x${masked.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  /// Resolves a Zoom hardware group byte to its canonical uppercase group name.
  ///
  /// When [deviceName] identifies an MS-60B+ pedal, applies the MS-60B+
  /// 11-group layout (`0x04=PREAMP`, `0x05=AMPS`, `0x07=PITCH`, `0x08=SYNTHS`,
  /// `0x09=SFX`, `0x0A=DELAY`, `0x0B=REVERB`); otherwise uses the standard
  /// Zoom Four / MS-50G+ group mapping.
  static String groupNameForByte(int groupByte, {String? deviceName}) {
    final upperDevice = deviceName?.toUpperCase() ?? '';
    final isMs60bPlus = upperDevice.contains('MS-60B') ||
        upperDevice.contains('MS60B') ||
        upperDevice.contains('60B+');

    if (isMs60bPlus) {
      switch (groupByte) {
        case 0x01:
          return 'DYNAMICS';
        case 0x02:
          return 'FILTER';
        case 0x03:
          return 'DRIVE';
        case 0x04:
          return 'PREAMP';
        case 0x05:
          return 'AMPS';
        case 0x06:
          return 'MODULATION';
        case 0x07:
          return 'PITCH';
        case 0x08:
          return 'SYNTHS';
        case 0x09:
          return 'SFX';
        case 0x0A:
          return 'DELAY';
        case 0x0B:
          return 'REVERB';
        default:
          return 'GROUP_$groupByte';
      }
    }

    switch (groupByte) {
      case 0x01:
        return 'DYNAMICS';
      case 0x02:
        return 'FILTER';
      case 0x03:
        return 'DRIVE';
      case 0x04:
        return 'AMP';
      case 0x05:
        return 'CABINET';
      case 0x06:
        return 'MODULATION';
      case 0x07:
        return 'SFX';
      case 0x08:
        return 'DELAY';
      case 0x09:
        return 'REVERB';
      case 0x0A:
        return 'EQ';
      case 0x0B:
        return 'PEDAL';
      case 0x0C:
        return 'PREAMP';
      case 0x14: // 20
        return 'AG_MODEL';
      case 0x1D: // 29
        return 'ACOUSTIC';
      case 0x1E: // 30
        return 'RHYTHM';
      case 0x1F: // 31
        return 'LOOPER';
      default:
        return 'GROUP_$groupByte';
    }
  }

  /// Parses raw `FLST_SEQ.ZT2` bytes into a [FlstParseResult].
  ///
  /// Throws [FlstParseException] when [bytes] is empty, shorter than one
  /// 26-byte record, or contains no `>>>\0` block markers.
  ///
  /// Safely tolerates trailing NUL padding, truncated final records, missing
  /// closing `<<<\0` markers, and minor header/group ID variations between
  /// Zoom Four and Zoom MS+ hardware.
  static FlstParseResult parse(Uint8List bytes) {
    if (bytes.length < recordSize) {
      throw FlstParseException(
        'Buffer too short to be a valid FLST_SEQ.ZT2 file '
        '(${bytes.length} bytes; minimum $recordSize bytes required).',
      );
    }

    final firstMarker = _findFirstOpenMarker(bytes);
    if (firstMarker == -1) {
      throw const FlstParseException(
        'Invalid FLST_SEQ.ZT2 buffer: missing ">>>\\0" header or group marker.',
      );
    }

    final bd = ByteData.sublistView(bytes);
    final entries = <FlstEffectEntry>[];
    String? deviceName;
    bool inHeader = false;
    int? currentGroupByte;
    String? currentGroupName;

    int offset = firstMarker;
    while (offset + recordSize <= bytes.length) {
      if (_isOpenMarker(bytes, offset)) {
        final markerGroup = bytes[offset + 4];
        if (markerGroup == 0x00) {
          inHeader = true;
          currentGroupByte = null;
          currentGroupName = null;
        } else {
          inHeader = false;
          currentGroupByte = markerGroup;
          final inlineLabel = _readNulTerminatedAscii(bytes, offset + 5, 21);
          currentGroupName = inlineLabel.isNotEmpty
              ? inlineLabel
              : groupNameForByte(markerGroup, deviceName: deviceName);
        }
        offset += recordSize;
        continue;
      }

      if (_isCloseMarker(bytes, offset)) {
        inHeader = false;
        currentGroupByte = null;
        currentGroupName = null;
        offset += recordSize;
        continue;
      }

      if (inHeader) {
        if (deviceName == null || deviceName.isEmpty) {
          final candidate = _readNulTerminatedAscii(bytes, offset, 12);
          if (candidate.isNotEmpty) {
            deviceName = candidate;
          }
        }
        offset += recordSize;
        continue;
      }

      if (currentGroupByte != null) {
        final filename = _readNulTerminatedAscii(bytes, offset, 12);
        final version = _readNulTerminatedAscii(bytes, offset + 13, 4);
        final installedFlag = bytes[offset + 18];
        final intEffectId = bd.getUint32(offset + 19, Endian.little);

        if (filename.isNotEmpty && intEffectId != 0) {
          entries.add(FlstEffectEntry(
            filename: filename,
            version: version,
            effectId: formatEffectId(intEffectId),
            intEffectId: intEffectId,
            groupByte: currentGroupByte,
            groupName: currentGroupName ??
                groupNameForByte(currentGroupByte, deviceName: deviceName),
            installed: installedFlag == 1,
          ));
        }
        offset += recordSize;
        continue;
      }

      // Outside header/group: skip trailing zero padding or unknown filler records.
      offset += recordSize;
    }

    return FlstParseResult(
      deviceName: deviceName,
      allEntries: entries,
    );
  }

  static int _findFirstOpenMarker(Uint8List bytes) {
    final limit = bytes.length - 4;
    for (int i = 0; i <= limit; i++) {
      if (_isOpenMarker(bytes, i)) {
        return i;
      }
    }
    return -1;
  }

  static bool _isOpenMarker(Uint8List bytes, int offset) {
    return offset + 4 <= bytes.length &&
        bytes[offset] == _markerOpenByte &&
        bytes[offset + 1] == _markerOpenByte &&
        bytes[offset + 2] == _markerOpenByte &&
        bytes[offset + 3] == 0x00;
  }

  static bool _isCloseMarker(Uint8List bytes, int offset) {
    return offset + 4 <= bytes.length &&
        bytes[offset] == _markerCloseByte &&
        bytes[offset + 1] == _markerCloseByte &&
        bytes[offset + 2] == _markerCloseByte &&
        bytes[offset + 3] == 0x00;
  }

  static String _readNulTerminatedAscii(
    Uint8List bytes,
    int offset,
    int maxLength,
  ) {
    final chars = <int>[];
    final end = (offset + maxLength).clamp(0, bytes.length);
    for (int i = offset; i < end; i++) {
      final b = bytes[i];
      if (b == 0x00) break;
      if (b >= 0x20 && b <= 0x7E) {
        chars.add(b);
      }
    }
    return String.fromCharCodes(chars).trim();
  }
}

