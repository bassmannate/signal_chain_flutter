import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/zd2/flst_seq_parser.dart';

/// Builds a synthetic Zoom `FLST_SEQ.ZT2` binary buffer following the exact
/// 26-byte record layout verified against `mungewell/zoom-zt2`.
Uint8List buildSyntheticFlstSeq({
  String deviceName = 'MS-60B+',
  required List<
      ({
        int groupByte,
        List<({String filename, String version, int effectId, bool installed})>
            entries,
        bool includeCloseMarker,
      })> groups,
  int padToLength = 0,
  List<int> trailingGarbage = const [],
}) {
  final builder = BytesBuilder(copy: false);

  Uint8List markerRecord(String marker, int groupByte) {
    final rec = Uint8List(FlstSeqParser.recordSize);
    rec.setRange(0, 3, ascii.encode(marker));
    rec[3] = 0x00;
    rec[4] = groupByte & 0xFF;
    return rec;
  }

  // 78-byte file header (3 x 26-byte records)
  builder.add(markerRecord('>>>', 0x00));
  final headerBody = Uint8List(FlstSeqParser.recordSize);
  final nameBytes = ascii.encode(deviceName);
  headerBody.setRange(0, nameBytes.length.clamp(0, 12), nameBytes);
  headerBody[18] = 0x01;
  builder.add(headerBody);
  builder.add(markerRecord('<<<', 0x00));

  for (final group in groups) {
    builder.add(markerRecord('>>>', group.groupByte));
    for (final e in group.entries) {
      final rec = Uint8List(FlstSeqParser.recordSize);
      final fnBytes = ascii.encode(e.filename);
      rec.setRange(0, fnBytes.length.clamp(0, 12), fnBytes);
      rec[12] = 0x00;
      final verBytes = ascii.encode(e.version);
      rec.setRange(13, 13 + verBytes.length.clamp(0, 4), verBytes);
      rec[17] = 0x00;
      rec[18] = e.installed ? 0x01 : 0x00;
      ByteData.sublistView(rec).setUint32(19, e.effectId, Endian.little);
      builder.add(rec);
    }
    if (group.includeCloseMarker) {
      builder.add(markerRecord('<<<', group.groupByte));
    }
  }

  final currentLen = builder.length;
  if (padToLength > currentLen) {
    builder.add(Uint8List(padToLength - currentLen));
  }
  if (trailingGarbage.isNotEmpty) {
    builder.add(Uint8List.fromList(trailingGarbage));
  }
  return builder.toBytes();
}

void main() {
  group('FlstSeqParser', () {
    test(
      'parses multi-group FLST_SEQ.ZT2 with installed == 1 and installed == 0 entries, uppercase hex IDs, and 8502-byte padding',
      () {
        final bytes = buildSyntheticFlstSeq(
          deviceName: 'MS-60B+',
          groups: const [
            (
              groupByte: 0x01,
              includeCloseMarker: true,
              entries: [
                (
                  filename: 'COMP.ZD2',
                  version: '1.10',
                  effectId: 0x01000010,
                  installed: true,
                ),
                (
                  filename: 'OPTCOMP.ZD2',
                  version: '1.00',
                  effectId: 0x0100002a,
                  installed: false,
                ),
              ],
            ),
            (
              groupByte: 0x03,
              includeCloseMarker: true,
              entries: [
                (
                  filename: 'TB_MK15.ZD2',
                  version: '1.20',
                  effectId: 0x030000e0,
                  installed: true,
                ),
              ],
            ),
            (
              groupByte: 0x04,
              includeCloseMarker: true,
              entries: [
                (
                  filename: 'MY_NAM.ZD2',
                  version: '1.30',
                  effectId: 0x0400099f,
                  installed: true,
                ),
              ],
            ),
          ],
          padToLength: 8502,
        );

        expect(bytes.length, equals(8502));
        final parsed = FlstSeqParser.parse(bytes);

        expect(parsed.deviceName, equals('MS-60B+'));
        expect(parsed.allEntries.length, equals(4));
        expect(parsed.installedEntries.length, equals(3));

        // Verify uppercase 0xXXXXXXXX formatting and exclusion of installed == 0
        expect(
          parsed.installedEffectIds,
          equals({'0x01000010', '0x030000E0', '0x0400099F'}),
        );
        expect(parsed.installedEffectIds.contains('0x0100002A'), isFalse);

        // Verify entry fields
        final comp = parsed.allEntries[0];
        expect(comp.filename, equals('COMP.ZD2'));
        expect(comp.version, equals('1.10'));
        expect(comp.effectId, equals('0x01000010'));
        expect(comp.groupByte, equals(0x01));
        expect(comp.groupName, equals('DYNAMICS'));
        expect(comp.installed, isTrue);

        final optComp = parsed.allEntries[1];
        expect(optComp.filename, equals('OPTCOMP.ZD2'));
        expect(optComp.effectId, equals('0x0100002A'));
        expect(optComp.installed, isFalse);

        final custom = parsed.allEntries[3];
        expect(custom.filename, equals('MY_NAM.ZD2'));
        expect(custom.groupByte, equals(0x04));
        expect(custom.groupName, equals('PREAMP'));
        expect(custom.effectId, equals('0x0400099F'));
        expect(custom.installed, isTrue);
      },
    );

    test(
      'assigns device-aware group names across multiple groups (MS-60B+ 0x09=SFX vs Zoom Four 0x09=REVERB)',
      () {
        final ms60bBytes = buildSyntheticFlstSeq(
          deviceName: 'MS-60B+',
          groups: const [
            (
              groupByte: 0x04,
              includeCloseMarker: true,
              entries: [
                (filename: 'BASS_DRV.ZD2', version: '1.00', effectId: 0x04000010, installed: true),
              ],
            ),
            (
              groupByte: 0x05,
              includeCloseMarker: true,
              entries: [
                (filename: 'AMPG_SVT.ZD2', version: '1.00', effectId: 0x05000020, installed: true),
              ],
            ),
            (
              groupByte: 0x09,
              includeCloseMarker: true,
              entries: [
                (filename: 'BPM_MDL.ZD2', version: '1.00', effectId: 0x09000FF0, installed: true),
              ],
            ),
            (
              groupByte: 0x0A,
              includeCloseMarker: true,
              entries: [
                (filename: 'ANLG_DLY.ZD2', version: '1.00', effectId: 0x0A000010, installed: true),
              ],
            ),
            (
              groupByte: 0x0B,
              includeCloseMarker: true,
              entries: [
                (filename: 'HALL_RVB.ZD2', version: '1.00', effectId: 0x0B000010, installed: true),
              ],
            ),
          ],
        );

        final ms60bParsed = FlstSeqParser.parse(ms60bBytes);
        expect(
          ms60bParsed.installedEntries.map((e) => e.groupName).toList(),
          equals(['PREAMP', 'AMPS', 'SFX', 'DELAY', 'REVERB']),
        );

        final b1xBytes = buildSyntheticFlstSeq(
          deviceName: 'B1X FOUR',
          groups: const [
            (
              groupByte: 0x04,
              includeCloseMarker: true,
              entries: [
                (filename: 'SVT_AMP.ZD2', version: '1.00', effectId: 0x04800010, installed: true),
              ],
            ),
            (
              groupByte: 0x09,
              includeCloseMarker: true,
              entries: [
                (filename: 'HALL.ZD2', version: '1.00', effectId: 0x09800010, installed: true),
              ],
            ),
          ],
        );
        final b1xParsed = FlstSeqParser.parse(b1xBytes);
        expect(
          b1xParsed.installedEntries.map((e) => e.groupName).toList(),
          equals(['AMP', 'REVERB']),
        );
      },
    );

    test(
      'handles missing closing marker, truncated trailing bytes, and cross-group IDs without crashing',
      () {
        final bytes = buildSyntheticFlstSeq(
          deviceName: 'B1X FOUR',
          groups: const [
            (
              groupByte: 0x0B, // PEDAL
              includeCloseMarker: false, // Missing <<<\0 before EOF
              entries: [
                (
                  filename: 'WAH_B1X.ZD2',
                  version: '1.00',
                  effectId: 0x02800055, // Top byte intentionally != groupByte
                  installed: true,
                ),
              ],
            ),
          ],
          // 11 truncated trailing bytes (< 26-byte record)
          trailingGarbage: const [0x41, 0x42, 0x43, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07],
        );

        final parsed = FlstSeqParser.parse(bytes);
        expect(parsed.deviceName, equals('B1X FOUR'));
        expect(parsed.installedEntries.length, equals(1));
        expect(parsed.installedEntries.first.filename, equals('WAH_B1X.ZD2'));
        expect(parsed.installedEntries.first.groupName, equals('PEDAL'));
        expect(parsed.installedEffectIds, equals({'0x02800055'}));
      },
    );

    test('throws FlstParseException on empty, too-short, or non-FLST garbage buffers', () {
      expect(
        () => FlstSeqParser.parse(Uint8List(0)),
        throwsA(isA<FlstParseException>()),
      );
      expect(
        () => FlstSeqParser.parse(Uint8List(12)),
        throwsA(isA<FlstParseException>()),
      );
      expect(
        () => FlstSeqParser.parse(Uint8List.fromList(List<int>.filled(128, 0x42))),
        throwsA(isA<FlstParseException>()),
      );
    });
  });
}

