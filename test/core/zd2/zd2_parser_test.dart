import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/zd2/zd2_parser.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

/// Builds a synthetic binary Zoom `.ZD2` (`ZDLF`) buffer for deterministic unit tests.
Uint8List buildSyntheticZd2({
  String magic = 'ZDLF',
  int headerLength = 120,
  int checksum = 0x12345678,
  int targetMask = 0x00080000, // MS-60B+
  String version = '1.20',
  int groupByte = 0x04,
  int effectId = 0x04000999,
  String name = 'MY NAM',
  String nameGarbageAfterNul = 'XYZ',
  String groupName = 'PREAMP',
  String groupGarbageAfterNul = '99',
  List<({String tag, Uint8List payload})> sections = const [],
  List<int> trailer = const [],
}) {
  final headerSize = headerLength >= 120 ? 8 + headerLength : 0x80;
  final builder = BytesBuilder(copy: false);
  final header = Uint8List(headerSize);
  final bd = ByteData.sublistView(header);

  final magicBytes = ascii.encode(magic);
  header.setRange(0, magicBytes.length.clamp(0, 4), magicBytes);
  bd.setUint32(0x04, headerLength, Endian.little);
  bd.setUint32(0x08, checksum, Endian.little);
  bd.setUint32(0x0C, targetMask, Endian.little);

  // Version at 0x59..0x5D (4 bytes)
  final verBytes = ascii.encode(version);
  for (int i = 0; i < verBytes.length && i < 4; i++) {
    header[0x59 + i] = verBytes[i];
  }

  // Group byte at 0x5F
  header[0x5F] = groupByte & 0xFF;

  // Effect ID at 0x60..0x64
  bd.setUint32(0x60, effectId, Endian.little);

  // Name C-string at 0x64..0x6F (11 bytes) with deliberate trailing garbage after NUL
  final nameBytes = ascii.encode(name);
  for (int i = 0; i < nameBytes.length && i < 10; i++) {
    header[0x64 + i] = nameBytes[i];
  }
  final nameNulPos = 0x64 + nameBytes.length.clamp(0, 10);
  if (nameNulPos < 0x6F) {
    header[nameNulPos] = 0x00;
    final garbage = ascii.encode(nameGarbageAfterNul);
    for (int i = 0; i < garbage.length && nameNulPos + 1 + i < 0x6F; i++) {
      header[nameNulPos + 1 + i] = garbage[i];
    }
  }

  // Group name C-string at 0x6F..0x7A (11 bytes) with deliberate trailing garbage after NUL
  final grpBytes = ascii.encode(groupName);
  for (int i = 0; i < grpBytes.length && i < 10; i++) {
    header[0x6F + i] = grpBytes[i];
  }
  final grpNulPos = 0x6F + grpBytes.length.clamp(0, 10);
  if (grpNulPos < 0x7A) {
    header[grpNulPos] = 0x00;
    final garbage = ascii.encode(groupGarbageAfterNul);
    for (int i = 0; i < garbage.length && grpNulPos + 1 + i < 0x7A; i++) {
      header[grpNulPos + 1 + i] = garbage[i];
    }
  }

  builder.add(header);

  for (final section in sections) {
    final secHeader = Uint8List(8);
    secHeader.setRange(0, 4, ascii.encode(section.tag.padRight(4).substring(0, 4)));
    ByteData.sublistView(secHeader).setUint32(4, section.payload.length, Endian.little);
    builder.add(secHeader);
    builder.add(section.payload);
  }

  if (trailer.isNotEmpty) {
    builder.add(Uint8List.fromList(trailer));
  }

  return builder.toBytes();
}

Uint8List buildInfoPayload(double rawDspFloat) {
  final bytes = Uint8List(24);
  ByteData.sublistView(bytes).setFloat32(16, rawDspFloat, Endian.little);
  return bytes;
}

void main() {
  group('Zd2Parser', () {
    test('parses valid MS+ .ZD2 with INFO, TXE1, PRME JSON, NUL-terminated strings, and 16-byte trailer', () {
      final prmeJson = json.encode({
        'Parameters': [
          {'name': 'OnOff', 'mmax': 1, 'default': 1},
          {'name': 'Page', 'mmax': 0, 'default': 0},
          {'name': 'Pedal', 'mmax': 0, 'default': 0},
          {
            'name': 'Gain',
            'mmax': 100,
            'default': 65,
            'explanation': 'Input drive amount',
          },
          {
            'name': 'Tone',
            'mmax': 24,
            'default': 12,
            'display': [for (int i = -12; i <= 12; i++) '$i'],
          },
          {
            'name': 'Mode',
            'mmax': 2,
            'default': 1,
            'display': ['VINTAGE', 'MODERN', 'SCOOP'],
          },
        ],
      });

      final bytes = buildSyntheticZd2(
        targetMask: 0x00080000, // MS-60B+
        version: '1.30',
        groupByte: 0x04,
        effectId: 0x04000999,
        name: 'MY NAM',
        groupName: 'PREAMP',
        sections: [
          (tag: 'INFO', payload: buildInfoPayload(54.0)), // 54.0 / 2.7 = 20%
          (
            tag: 'TXE1',
            payload: Uint8List.fromList([...utf8.encode('Neural Amp Capture'), 0x00, 0x00]),
          ),
          (
            tag: 'PRME',
            payload: Uint8List.fromList([...utf8.encode(prmeJson), 0x00, 0x00]),
          ),
        ],
        // Standard 16-byte binary trailer
        trailer: List<int>.generate(16, (i) => i),
      );

      final parsed = Zd2Parser.parse(bytes, sourceFilename: 'MY_NAM.ZD2');

      expect(parsed.effectId, equals('0x04000999'));
      expect(parsed.intEffectId, equals(0x04000999));
      expect(parsed.name, equals('MY NAM'));
      expect(parsed.groupName, equals('PREAMP'));
      expect(parsed.groupByte, equals(0x04));
      expect(parsed.version, equals('1.30'));
      expect(parsed.dspLoad, equals(20));
      expect(parsed.description, equals('Neural Amp Capture'));
      expect(parsed.sourceFilename, equals('MY_NAM.ZD2'));
      expect(parsed.generation, equals(DeviceGeneration.zoomMsPlus));

      // System entries (OnOff, Page, mmax==0 Pedal) are skipped so knob indices align with EDTB slots 0..2
      expect(parsed.parameters.length, equals(3));
      expect(parsed.parameters[0].name, equals('Gain'));
      expect(parsed.parameters[0].min, equals(0));
      expect(parsed.parameters[0].max, equals(100));
      expect(parsed.parameters[0].defaultValue, equals(65));

      expect(parsed.parameters[1].name, equals('Tone'));
      expect(parsed.parameters[1].displayOffset, equals(-12));
      expect(parsed.parameters[1].formatValue(12), equals('0'));
      expect(parsed.parameters[1].formatValue(0), equals('-12'));

      expect(parsed.parameters[2].name, equals('Mode'));
      expect(parsed.parameters[2].isDiscrete, isTrue);
      expect(parsed.parameters[2].labels, equals(['VINTAGE', 'MODERN', 'SCOOP']));
      expect(parsed.parameters[2].defaultValue, equals(1));

      final def = parsed.toEffectDefinition(deviceFamily: DeviceFamily.zoomMs60bPlus);
      expect(def.origin, equals(EffectOrigin.custom));
      expect(def.category, equals('Custom'));
      expect(def.sourceModelLabel, equals('Custom'));
      expect(def.sourceFilename, equals('MY_NAM.ZD2'));
      expect(def.version, equals('1.30'));
      expect(def.description, equals('Neural Amp Capture'));
      expect(def.dspLoad, equals(20));
    });

    test('parses valid Zoom Four .ZD2 with lowercase PRME variants and zero trailer', () {
      final prmeJson = json.encode({
        'parameters': [
          {'name': 'Drive', 'max': 100, 'default': 40},
          {'name': 'Blend', 'max': 100, 'default': 50, 'values': ['DRY', '50/50', 'WET']},
        ],
      });

      final bytes = buildSyntheticZd2(
        targetMask: 0x00000080, // B1X FOUR
        version: '2.00',
        groupByte: 0x03,
        effectId: 0x03800999,
        name: 'FOUR FUZZ',
        groupName: 'DRIVE',
        sections: [
          (tag: 'INFO', payload: buildInfoPayload(27.0)), // 10%
          (tag: 'PRME', payload: Uint8List.fromList(utf8.encode(prmeJson))),
        ],
      );

      final parsed = Zd2Parser.parse(bytes, sourceFilename: 'FOURFUZZ.ZD2');
      expect(parsed.generation, equals(DeviceGeneration.zoomFour));
      expect(parsed.dspLoad, equals(10));
      expect(parsed.parameters.length, equals(2));
      expect(parsed.parameters[0].name, equals('Drive'));
      expect(parsed.parameters[1].labels, equals(['DRY', '50/50', 'WET']));
    });

    test('handles duplicate PRME sections without failing or losing parameters', () {
      final validPrme = json.encode({
        'Parameters': [
          {'name': 'Rate', 'mmax': 50, 'default': 25},
          {'name': 'Depth', 'mmax': 100, 'default': 60},
        ],
      });

      final bytes = buildSyntheticZd2(
        effectId: 0x06000999,
        name: 'DUAL PRME',
        sections: [
          (tag: 'PRME', payload: Uint8List.fromList(utf8.encode(validPrme))),
          (tag: 'PRME', payload: Uint8List.fromList(utf8.encode('{invalid json!!!'))),
        ],
      );

      final parsed = Zd2Parser.parse(bytes);
      expect(parsed.name, equals('DUAL PRME'));
      expect(parsed.parameters.length, equals(2));
      expect(parsed.parameters.map((p) => p.name), equals(['Rate', 'Depth']));
    });

    test('imports cleanly with empty parameter list when PRME is missing or malformed', () {
      final noPrmeBytes = buildSyntheticZd2(
        targetMask: 0,
        effectId: 0x09000999,
        name: 'NO PRME FX',
        sections: [
          (tag: 'TXE1', payload: Uint8List.fromList(utf8.encode('Simple custom block'))),
        ],
      );
      final parsedNoPrme = Zd2Parser.parse(noPrmeBytes);
      expect(parsedNoPrme.name, equals('NO PRME FX'));
      expect(parsedNoPrme.generation, isNull); // targetMask 0 -> generation-agnostic
      expect(parsedNoPrme.parameters, isEmpty);
      expect(parsedNoPrme.description, equals('Simple custom block'));

      final badPrmeBytes = buildSyntheticZd2(
        effectId: 0x0900099A,
        name: 'BAD PRME',
        sections: [
          (tag: 'PRME', payload: Uint8List.fromList(utf8.encode('not-json-at-all'))),
        ],
      );
      final parsedBadPrme = Zd2Parser.parse(badPrmeBytes);
      expect(parsedBadPrme.name, equals('BAD PRME'));
      expect(parsedBadPrme.parameters, isEmpty);
    });

    test('stops cleanly when a trailing section declares a length exceeding remaining bytes', () {
      final truncatedTrailer = Uint8List(12);
      truncatedTrailer.setRange(0, 4, ascii.encode('DATA'));
      ByteData.sublistView(truncatedTrailer).setUint32(4, 999999, Endian.little);

      final bytes = buildSyntheticZd2(
        effectId: 0x02000999,
        name: 'SAFE STOP',
        sections: [
          (tag: 'INFO', payload: buildInfoPayload(40.5)), // 15%
        ],
        trailer: truncatedTrailer,
      );

      final parsed = Zd2Parser.parse(bytes);
      expect(parsed.name, equals('SAFE STOP'));
      expect(parsed.dspLoad, equals(15));
    });

    test('throws Zd2ParseException on invalid magic, truncated header, or corrupt headerLength', () {
      // Too small (< 0x80)
      expect(
        () => Zd2Parser.parse(Uint8List(64)),
        throwsA(isA<Zd2ParseException>()),
      );

      // Invalid magic (e.g. PTCF patch instead of ZDLF)
      final wrongMagic = buildSyntheticZd2(magic: 'PTCF');
      expect(
        () => Zd2Parser.parse(wrongMagic),
        throwsA(isA<Zd2ParseException>()),
      );

      // Corrupt headerLength exceeding buffer
      final badHeaderLen = buildSyntheticZd2(headerLength: 120);
      ByteData.sublistView(badHeaderLen).setUint32(0x04, 50000, Endian.little);
      expect(
        () => Zd2Parser.parse(badHeaderLen),
        throwsA(isA<Zd2ParseException>()),
      );
    });
  });
}

