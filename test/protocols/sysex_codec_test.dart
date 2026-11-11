import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/protocols/sysex_codec.dart';

void main() {
  group('SysexCodec 7-bit / 8-bit Packing & Unpacking', () {
    test('handles empty payload round-trip', () {
      final input = Uint8List(0);
      final packed = SysexCodec.pack8BitTo7Bit(input);
      expect(packed, isEmpty);

      final unpacked = SysexCodec.unpack7BitTo8Bit(packed);
      expect(unpacked, isEmpty);
    });

    test('round-trips exact 7-byte boundary', () {
      // 7 8-bit bytes pack into exactly 8 7-bit bytes
      final input = Uint8List.fromList([0x01, 0x82, 0x03, 0xF4, 0x05, 0x86, 0x7F]);
      final packed = SysexCodec.pack8BitTo7Bit(input);
      expect(packed.length, equals(8));

      // Check MSB header byte
      // input[0]=0x01 (MSB=0), input[1]=0x82 (MSB=1), input[2]=0x03 (MSB=0),
      // input[3]=0xF4 (MSB=1), input[4]=0x05 (MSB=0), input[5]=0x86 (MSB=1), input[6]=0x7F (MSB=0)
      // Header bit 6=0, 5=1, 4=0, 3=1, 2=0, 1=1, 0=0 -> binary 00101010 = 0x2A
      expect(packed[0], equals(0x2A));
      expect(packed[1], equals(0x01));
      expect(packed[2], equals(0x02)); // 0x82 & 0x7F
      expect(packed[3], equals(0x03));
      expect(packed[4], equals(0x74)); // 0xF4 & 0x7F
      expect(packed[5], equals(0x05));
      expect(packed[6], equals(0x06)); // 0x86 & 0x7F
      expect(packed[7], equals(0x7F));

      // Every packed byte must be a valid 7-bit MIDI byte (< 128)
      for (final b in packed) {
        expect(b, lessThan(128));
      }

      final unpacked = SysexCodec.unpack7BitTo8Bit(packed);
      expect(unpacked, equals(input));
    });

    test('round-trips multiple 7-byte groups (14 bytes and 21 bytes)', () {
      final input14 = Uint8List.fromList(List.generate(14, (i) => (i * 17) & 0xFF));
      final packed14 = SysexCodec.pack8BitTo7Bit(input14);
      expect(packed14.length, equals(16));
      expect(SysexCodec.unpack7BitTo8Bit(packed14), equals(input14));

      final input21 = Uint8List.fromList(List.generate(21, (i) => (i * 29) & 0xFF));
      final packed21 = SysexCodec.pack8BitTo7Bit(input21);
      expect(packed21.length, equals(24));
      expect(SysexCodec.unpack7BitTo8Bit(packed21), equals(input21));
    });

    test('round-trips partial trailing groups (1 to 6 bytes)', () {
      for (int len = 1; len <= 6; len++) {
        final input = Uint8List.fromList(List.generate(len, (i) => 0x80 | (i * 10)));
        final packed = SysexCodec.pack8BitTo7Bit(input);
        expect(packed.length, equals(len + 1));

        for (final b in packed) {
          expect(b, lessThan(128));
        }

        final unpacked = SysexCodec.unpack7BitTo8Bit(packed);
        expect(unpacked, equals(input));
      }
    });

    test('round-trips across 14-byte + partial remainder (e.g. 17 bytes, 25 bytes)', () {
      final input17 = Uint8List.fromList(List.generate(17, (i) => 0xFF - i));
      final packed17 = SysexCodec.pack8BitTo7Bit(input17);
      expect(SysexCodec.unpack7BitTo8Bit(packed17), equals(input17));

      final input25 = Uint8List.fromList(List.generate(25, (i) => (i * 37) & 0xFF));
      final packed25 = SysexCodec.pack8BitTo7Bit(input25);
      expect(SysexCodec.unpack7BitTo8Bit(packed25), equals(input25));
    });

    test('round-trips high-bit bytes (0x80 to 0xFF) exclusively', () {
      final highBits = Uint8List.fromList(List.generate(128, (i) => 0x80 + i));
      final packed = SysexCodec.pack8BitTo7Bit(highBits);

      for (final b in packed) {
        expect(b, lessThan(128));
      }

      final unpacked = SysexCodec.unpack7BitTo8Bit(packed);
      expect(unpacked, equals(highBits));
    });

    test('subrange packing and unpacking with start and end offsets', () {
      final full = Uint8List.fromList([0x00, 0x11, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
      final sub = SysexCodec.pack8BitTo7Bit(full, start: 2, end: 8);
      expect(SysexCodec.unpack7BitTo8Bit(sub), equals(full.sublist(2, 9)));
    });
  });

  group('SysexCodec Nibble Packing & Unpacking', () {
    test('round-trips nibbles with LS nibble first (Line 6 format)', () {
      final input = Uint8List.fromList([0x00, 0x12, 0xAB, 0x7F, 0xFF]);
      final packed = SysexCodec.packNibbles(input, msbFirst: false);
      expect(packed.length, equals(10));
      expect(packed[0], equals(0x00));
      expect(packed[1], equals(0x00));
      expect(packed[2], equals(0x02)); // low nibble of 0x12
      expect(packed[3], equals(0x01)); // high nibble of 0x12
      expect(packed[4], equals(0x0B)); // low nibble of 0xAB
      expect(packed[5], equals(0x0A)); // high nibble of 0xAB

      final unpacked = SysexCodec.unpackNibbles(packed, msbFirst: false);
      expect(unpacked, equals(input));
    });

    test('round-trips nibbles with MS nibble first', () {
      final input = Uint8List.fromList([0x34, 0xCD]);
      final packed = SysexCodec.packNibbles(input, msbFirst: true);
      expect(packed[0], equals(0x03));
      expect(packed[1], equals(0x04));
      expect(packed[2], equals(0x0C));
      expect(packed[3], equals(0x0D));

      final unpacked = SysexCodec.unpackNibbles(packed, msbFirst: true);
      expect(unpacked, equals(input));
    });
  });

  group('SysexCodec Bitfield Operations', () {
    test('getBits and setBits within single byte', () {
      final buffer = Uint8List(4);
      SysexCodec.setBits(buffer, 3, 6, 0x0B); // 4 bits: 1011
      expect(SysexCodec.getBits(buffer, 3, 6), equals(0x0B));
    });

    test('getBits and setBits spanning across byte boundaries', () {
      final buffer = Uint8List(4);
      // Span 12 bits from bit 6 to bit 17 (spans byte 0, 1, 2)
      SysexCodec.setBits(buffer, 6, 17, 0x0ABC);
      expect(SysexCodec.getBits(buffer, 6, 17), equals(0x0ABC));
    });

    test('getBits single bit (toggle flag)', () {
      final buffer = Uint8List.fromList([0x80, 0x00]);
      expect(SysexCodec.getBits(buffer, 0, 0), equals(1));
      expect(SysexCodec.getBits(buffer, 1, 1), equals(0));

      SysexCodec.setBits(buffer, 0, 0, 0);
      expect(SysexCodec.getBits(buffer, 0, 0), equals(0));
      expect(buffer[0], equals(0x00));
    });
  });

  group('SysexCodec CRC & Framing Helpers', () {
    test('calculateCrc32 produces valid IEEE 802.3 CRC32', () {
      final data = Uint8List.fromList('123456789'.codeUnits);
      final crc = SysexCodec.calculateCrc32(data);
      // Standard CRC-32 for '123456789' is 0xCBF43926
      expect(crc, equals(0xCBF43926));
    });

    test('calculateZoom7BitCrc produces 5 7-bit words', () {
      final data = Uint8List.fromList([0x50, 0x54, 0x43, 0x46, 0x01, 0x02, 0x03]);
      final crc7 = SysexCodec.calculateZoom7BitCrc(data);
      expect(crc7.length, equals(5));
      for (final b in crc7) {
        expect(b, lessThan(128));
      }
    });

    test('isSysEx correctly identifies framed messages', () {
      expect(SysexCodec.isSysEx(Uint8List.fromList([0xF0, 0x52, 0xF7])), isTrue);
      expect(SysexCodec.isSysEx(Uint8List.fromList([0xF0])), isFalse);
      expect(SysexCodec.isSysEx(Uint8List.fromList([0xB0, 0x07, 0x7F])), isFalse);
    });

    test('isIdentityReply validates identity reply frames', () {
      final validReply = Uint8List.fromList([0xF0, 0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x27, 0x00, 0xF7]);
      expect(SysexCodec.isIdentityReply(validReply), isTrue);

      final nonReply = Uint8List.fromList([0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7]); // Request, not reply
      expect(SysexCodec.isIdentityReply(nonReply), isFalse);
    });
  });
}

