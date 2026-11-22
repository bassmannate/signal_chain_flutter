import 'dart:convert';
import 'dart:typed_data';

import '../../models/device_family.dart';
import '../../models/parameter_descriptor.dart';
import '../../protocols/catalogs/effect_catalog.dart';

/// Exception thrown when a binary buffer is not a valid Zoom `.ZD2` (`ZDLF`) file.
class Zd2ParseException implements Exception {
  final String message;

  const Zd2ParseException(this.message);

  @override
  String toString() => 'Zd2ParseException: $message';
}

/// Immutable representation of a parsed Zoom `.ZD2` (`ZDLF`) binary effect file.
class ParsedZd2Effect {
  /// Normalized uppercase 32-bit hex DSP ID (`'0xXXXXXXXX'`).
  final String effectId;

  /// Raw 32-bit unsigned integer DSP ID.
  final int intEffectId;

  /// Effect display name extracted from the ZDLF header C-string (`0x64..0x6F`).
  final String name;

  /// Raw hardware group name extracted from `0x6F..0x7A`.
  final String groupName;

  /// Raw hardware group byte from `0x5F`.
  final int groupByte;

  /// Optional 4-character ASCII version string from `0x59..0x5D`.
  final String? version;

  /// Optional English description decoded from the `TXE1` chunk.
  final String? description;

  /// Optional original filename (e.g., `'MY_NAM.ZD2'`).
  final String? sourceFilename;

  /// Header checksum (`u32le` at `0x08`).
  final int checksum;

  /// Hardware target bitmask (`u32le` at `0x0C`).
  final int targetMask;

  /// Inferred hardware generation hint (`zoomMsPlus`, `zoomFour`, or `null` if agnostic).
  final DeviceGeneration? generation;

  /// Estimated integer DSP load percentage (`0..100`, or `0` if absent/invalid).
  final int dspLoad;

  /// Raw float32 DSP value from `INFO` offset `16` when present.
  final double? rawDspLoad;

  /// Extracted knob parameter descriptors from `PRME` JSON, aligned to EDTB slots.
  final List<ParameterDescriptor> parameters;

  const ParsedZd2Effect({
    required this.effectId,
    required this.intEffectId,
    required this.name,
    required this.groupName,
    required this.groupByte,
    required this.checksum,
    required this.targetMask,
    this.version,
    this.description,
    this.sourceFilename,
    this.generation,
    this.dspLoad = 0,
    this.rawDspLoad,
    this.parameters = const [],
  });

  /// Converts this parsed `.ZD2` into an [EffectDefinition] tagged as [EffectOrigin.custom].
  EffectDefinition toEffectDefinition({
    required DeviceFamily deviceFamily,
  }) {
    final resolvedName =
        name.trim().isNotEmpty ? name.trim() : 'Custom ($effectId)';
    return EffectDefinition(
      effectId: effectId,
      name: resolvedName,
      category: 'Custom',
      deviceFamily: deviceFamily,
      parameters: parameters,
      dspLoad: dspLoad > 0 ? dspLoad : null,
      origin: EffectOrigin.custom,
      sourceModelLabel: 'Custom',
      sourceFilename: sourceFilename,
      description: description,
      version: version,
    );
  }
}

/// Pure-Dart binary parser for Zoom `.ZD2` (`ZDLF`) DSP effect files.
class Zd2Parser {
  Zd2Parser._();

  /// Minimum valid `.ZD2` header length in bytes (`0x80` = 128).
  static const int minHeaderBytes = 0x80;

  /// Default ZDLF header length field (`120` = `0x78`), placing section blocks at `8 + 120 = 0x80`.
  static const int defaultHeaderLength = 120;

  /// Zoom Four target mask bits (`G1 FOUR`, `G1X FOUR`, `B1 FOUR`, `B1X FOUR`, `A1/A1X FOUR`).
  static const int _zoomFourTargetMask = 0x000003F0;

  /// Zoom MS+ target mask bits (`MS-50G+`, `MS-60B+`, `MS-70CDR+`, `MS-200D+`, etc.).
  static const int _zoomMsPlusTargetMask = 0x00FE0000;

  /// System/non-knob PRME parameter names that must be excluded so knob indices
  /// align directly with EDTB parameter slots (`paramNumber = paramIndex + 2`).
  static const Set<String> _alwaysSkipParamNames = {
    'onoff',
    'on/off',
    'on_off',
    'bypass',
    'page',
    'effect',
    'effectid',
  };

  /// Parses raw `.ZD2` bytes into a [ParsedZd2Effect].
  ///
  /// Throws [Zd2ParseException] if the buffer is truncated, missing the `'ZDLF'`
  /// magic signature, or has a corrupt header length.
  static ParsedZd2Effect parse(
    Uint8List bytes, {
    String? sourceFilename,
  }) {
    if (bytes.length < minHeaderBytes) {
      throw Zd2ParseException(
        'File is too small to be a valid Zoom .ZD2 effect '
        '(${bytes.length} bytes; minimum $minHeaderBytes bytes required).',
      );
    }

    // Validate 'ZDLF' ASCII magic at 0x00..0x04
    if (bytes[0] != 0x5A ||
        bytes[1] != 0x44 ||
        bytes[2] != 0x4C ||
        bytes[3] != 0x46) {
      throw const Zd2ParseException(
        'Invalid .ZD2 file: missing "ZDLF" magic signature.',
      );
    }

    final bd = ByteData.sublistView(bytes);
    final headerLength = bd.getUint32(0x04, Endian.little);
    final checksum = bd.getUint32(0x08, Endian.little);
    final targetMask = bd.getUint32(0x0C, Endian.little);

    final int sectionsStart;
    if (headerLength == 0 || headerLength == defaultHeaderLength) {
      sectionsStart = minHeaderBytes;
    } else if (headerLength > defaultHeaderLength &&
        8 + headerLength <= bytes.length) {
      sectionsStart = 8 + headerLength;
    } else {
      throw Zd2ParseException(
        'Corrupt .ZD2 header length ($headerLength bytes) for ${bytes.length}-byte file.',
      );
    }

    final versionRaw = _readNulTerminatedAscii(bytes, 0x59, 4);
    final version = versionRaw.isEmpty ? null : versionRaw;
    final groupByte = bytes[0x5F];
    final intEffectId = bd.getUint32(0x60, Endian.little);
    final effectId =
        '0x${intEffectId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
    final name = _readNulTerminatedAscii(bytes, 0x64, 11);
    final groupName = _readNulTerminatedAscii(bytes, 0x6F, 11);

    int dspLoad = 0;
    double? rawDspLoad;
    String? description;
    List<ParameterDescriptor> parameters = const [];

    // Walk tagged sections starting at sectionsStart until < 8 bytes remain.
    int cursor = sectionsStart;
    while (cursor + 8 <= bytes.length) {
      final tagBytes = bytes.sublist(cursor, cursor + 4);
      if (!_isValidSectionTag(tagBytes)) {
        // Reached binary trailer (e.g., 16-byte footer/CRC) or non-tag padding.
        break;
      }

      final payloadLen = bd.getUint32(cursor + 4, Endian.little);
      final payloadStart = cursor + 8;
      if (payloadLen > bytes.length - payloadStart) {
        // Stop cleanly on truncated block or trailer bytes.
        break;
      }

      final tag = ascii.decode(tagBytes);
      final payload = Uint8List.sublistView(
        bytes,
        payloadStart,
        payloadStart + payloadLen,
      );
      cursor = payloadStart + payloadLen;

      switch (tag) {
        case 'INFO':
          if (payload.length >= 20) {
            final infoData = ByteData.sublistView(payload);
            final rawFloat = infoData.getFloat32(16, Endian.little);
            if (rawFloat.isFinite && rawFloat > 0) {
              rawDspLoad = rawFloat;
              dspLoad = (rawFloat / 2.7).round().clamp(1, 100);
            }
          }
          break;

        case 'TXE1':
          final decoded = utf8
              .decode(payload, allowMalformed: true)
              .replaceAll('\x00', '')
              .trim();
          if (decoded.isNotEmpty) {
            description = decoded;
          }
          break;

        case 'PRME':
          final parsedParams = _parsePrmeSection(payload);
          if (parsedParams.isNotEmpty &&
              parsedParams.length > parameters.length) {
            parameters = parsedParams;
          }
          break;
      }
    }

    final generation = _inferGeneration(targetMask, intEffectId);

    return ParsedZd2Effect(
      effectId: effectId,
      intEffectId: intEffectId,
      name: name.isNotEmpty ? name : 'Custom ($effectId)',
      groupName: groupName,
      groupByte: groupByte,
      checksum: checksum,
      targetMask: targetMask,
      version: version,
      description: description,
      sourceFilename: sourceFilename,
      generation: generation,
      dspLoad: dspLoad,
      rawDspLoad: rawDspLoad,
      parameters: parameters,
    );
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
      if (b == 0x00) break; // Ignore any garbage bytes after the first NUL
      if (b >= 0x20 && b <= 0x7E) {
        chars.add(b);
      }
    }
    return String.fromCharCodes(chars).trim();
  }

  static bool _isValidSectionTag(List<int> tagBytes) {
    if (tagBytes.length != 4) return false;
    for (final b in tagBytes) {
      final isUpper = b >= 0x41 && b <= 0x5A; // A-Z
      final isLower = b >= 0x61 && b <= 0x7A; // a-z
      final isDigit = b >= 0x30 && b <= 0x39; // 0-9
      final isSymbol = b == 0x5F || b == 0x20 || b == 0x2D; // _, space, -
      if (!isUpper && !isLower && !isDigit && !isSymbol) {
        return false;
      }
    }
    return true;
  }

  static DeviceGeneration? _inferGeneration(int targetMask, int effectId) {
    final isMsPlus = (targetMask & _zoomMsPlusTargetMask) != 0;
    final isZoomFour = (targetMask & _zoomFourTargetMask) != 0;

    if (isMsPlus && !isZoomFour) {
      return DeviceGeneration.zoomMsPlus;
    }
    if (isZoomFour && !isMsPlus) {
      return DeviceGeneration.zoomFour;
    }

    // Secondary heuristic when targetMask is 0: ZDL7 Zoom Four bass/guitar effects
    // often set bit 0x00800000 or 0x00090000, while generic custom files stay agnostic.
    if (targetMask == 0) {
      return null;
    }
    return null;
  }

  static List<ParameterDescriptor> _parsePrmeSection(Uint8List payload) {
    if (payload.isEmpty) return const [];
    try {
      // Decode UTF-8 and strip NUL bytes / trailing control characters.
      var rawText = utf8.decode(payload, allowMalformed: true);
      final firstNul = rawText.indexOf('\x00');
      if (firstNul != -1) {
        rawText = rawText.substring(0, firstNul);
      }
      rawText = rawText
          .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
          .trim();
      if (rawText.isEmpty) return const [];

      // Trim any trailing non-JSON garbage after the final closing brace/bracket.
      final lastBrace = rawText.lastIndexOf('}');
      final lastBracket = rawText.lastIndexOf(']');
      final lastClose = lastBrace > lastBracket ? lastBrace : lastBracket;
      if (lastClose != -1 && lastClose + 1 < rawText.length) {
        rawText = rawText.substring(0, lastClose + 1);
      }

      final decoded = json.decode(rawText);
      final List<dynamic>? rawParams = _extractParameterList(decoded);
      if (rawParams == null || rawParams.isEmpty) return const [];

      final descriptors = <ParameterDescriptor>[];
      for (final item in rawParams) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);

        final rawName = (_firstPresent(map, const [
                  'name',
                  'Name',
                  'screenName',
                  'ScreenName',
                  'label',
                  'Label',
                ])?.toString() ??
                '')
            .trim();
        final normalizedName = rawName.toLowerCase().replaceAll(' ', '');

        if (rawName.isEmpty || _alwaysSkipParamNames.contains(normalizedName)) {
          continue;
        }

        final rawValues = _extractDisplayValues(map);
        final num? rawMin = _readNum(map, const ['mmin', 'min', 'Min', 'MMin']);
        final num? rawMax = _readNum(map, const ['mmax', 'max', 'Max', 'MMax']);
        final num? rawDefault =
            _readNum(map, const ['default', 'Default', 'def', 'defaultValue']);
        final num? rawStep = _readNum(map, const ['step', 'Step']);
        final int? explicitOffset =
            _readNum(map, const ['displayOffset', 'DisplayOffset'])?.round();
        final String? unit =
            _firstPresent(map, const ['unit', 'Unit'])?.toString().trim();

        final double minVal = rawMin?.toDouble() ?? 0.0;
        double maxVal;
        if (rawMax != null) {
          maxVal = rawMax.toDouble();
        } else if (rawValues != null && rawValues.length > 1) {
          maxVal = (rawValues.length - 1).toDouble();
        } else {
          maxVal = 0.0;
        }

        // Skip dummy/system slots with mmax == 0 and no multi-value display labels
        // (e.g., Zoom PRME placeholder "Pedal" or unused slot entries).
        if (maxVal <= minVal && (rawValues == null || rawValues.length <= 1)) {
          continue;
        }

        int detectedOffset = explicitOffset ?? 0;
        List<String>? discreteLabels;

        if (rawValues != null && rawValues.isNotEmpty) {
          final cleanedVals = rawValues.map(_cleanDisplayValue).toList();
          if (explicitOffset == null) {
            final parsedInts = <int>[];
            bool allInts = true;
            for (final s in cleanedVals) {
              final v = int.tryParse(s);
              if (v == null) {
                allInts = false;
                break;
              }
              parsedInts.add(v);
            }
            if (allInts && parsedInts.isNotEmpty) {
              final firstDiff = parsedInts[0];
              bool linear = true;
              for (int i = 0; i < parsedInts.length; i++) {
                if (parsedInts[i] - i != firstDiff) {
                  linear = false;
                  break;
                }
              }
              if (linear) {
                detectedOffset = firstDiff;
              } else {
                discreteLabels = cleanedVals;
              }
            } else {
              discreteLabels = cleanedVals;
            }
          } else {
            discreteLabels = cleanedVals;
          }

          if (maxVal < cleanedVals.length - 1 && rawMax == null) {
            maxVal = (cleanedVals.length - 1).toDouble();
          }
        }

        final defaultVal =
            (rawDefault?.toDouble() ?? minVal).clamp(minVal, maxVal);
        final stepVal =
            (rawStep != null && rawStep > 0) ? rawStep.toDouble() : 1.0;

        final pIdx = descriptors.length;
        final sanitized = rawName
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
        final paramId = '${sanitized.isEmpty ? 'param' : sanitized}_$pIdx';

        descriptors.add(ParameterDescriptor(
          id: paramId,
          name: rawName,
          min: minVal,
          max: maxVal,
          defaultValue: defaultVal,
          step: stepVal,
          unit: (unit != null && unit.isNotEmpty) ? unit : null,
          displayOffset: detectedOffset,
          labels: discreteLabels,
          valueLabels: discreteLabels,
        ));
      }

      return descriptors;
    } catch (_) {
      // Malformed or non-JSON PRME never aborts .ZD2 import.
      return const [];
    }
  }

  static List<dynamic>? _extractParameterList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is! Map) return null;

    final map = Map<String, dynamic>.from(decoded);
    for (final key in const [
      'Parameters',
      'parameters',
      'Param',
      'param',
      'Params',
      'params',
    ]) {
      final candidate = map[key];
      if (candidate is List) return candidate;
    }

    // Handle optional outer wrapper object (e.g., {"Effect": {"Parameters": [...]}})
    for (final wrapperKey in const ['Effect', 'effect', 'data', 'Data']) {
      final inner = map[wrapperKey];
      if (inner is Map) {
        final nested = _extractParameterList(inner);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static dynamic _firstPresent(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k) && map[k] != null) return map[k];
    }
    return null;
  }

  static num? _readNum(Map<String, dynamic> map, List<String> keys) {
    final val = _firstPresent(map, keys);
    if (val is num) return val;
    if (val is String) return num.tryParse(val.trim());
    return null;
  }

  static List<String>? _extractDisplayValues(Map<String, dynamic> map) {
    final raw = _firstPresent(map, const [
      'display',
      'Display',
      'labels',
      'Labels',
      'values',
      'Values',
      'valueLabels',
    ]);
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).toList();
    }
    return null;
  }

  static String _cleanDisplayValue(String raw) {
    return raw.replaceAll('\x00', '').trim();
  }
}
