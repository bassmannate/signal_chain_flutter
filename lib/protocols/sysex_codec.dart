import 'dart:typed_data';

/// Pure Dart codec and utilities for MIDI System Exclusive (SysEx) communication.
///
/// Provides 7-bit <-> 8-bit data packing/unpacking, nibble encoding,
/// bitfield manipulation, CRC32, and framing helpers.
class SysexCodec {
  const SysexCodec._();

  static final Uint32List _crc32Table = _initCrc32Table();

  static Uint32List _initCrc32Table() {
    final table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        if ((c & 1) != 0) {
          c = 0xEDB88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[n] = c;
    }
    return table;
  }

  /// Packs an 8-bit binary payload into a 7-bit MIDI SysEx safe byte array.
  ///
  /// Every group of 7 raw 8-bit bytes is packed into 8 MIDI bytes.
  /// The first byte in each group contains the MSBs (bit 7) of the following bytes:
  /// - Byte 0 MSB -> Header bit 6
  /// - Byte 1 MSB -> Header bit 5
  /// - ...
  /// - Byte 6 MSB -> Header bit 0
  /// Followed by 7 bytes containing the lower 7 bits of each original byte.
  ///
  /// Trailing partial groups (1–6 bytes) are encoded with a header byte containing
  /// only the MSBs for the remaining bytes.
  static Uint8List pack8BitTo7Bit(
    Uint8List unpacked, {
    int start = 0,
    int? end,
  }) {
    if (unpacked.isEmpty) return Uint8List(0);
    final effectiveEnd = end ?? (unpacked.length - 1);
    if (start > effectiveEnd || start >= unpacked.length) return Uint8List(0);

    final inputLength = effectiveEnd - start + 1;
    final outputLength = inputLength + ((inputLength + 6) ~/ 7);
    final result = Uint8List(outputLength);

    int readIndex = start;
    int writeIndex = 0;

    while (readIndex <= effectiveEnd) {
      final headerIndex = writeIndex++;
      int header = 0;

      for (int offset = 0; offset < 7 && readIndex <= effectiveEnd; offset++) {
        final b = unpacked[readIndex++];
        if ((b & 0x80) != 0) {
          header |= (1 << (6 - offset));
        }
        result[writeIndex++] = b & 0x7F;
      }
      result[headerIndex] = header;
    }

    return result;
  }

  /// Unpacks a 7-bit MIDI SysEx byte array back into an 8-bit binary payload.
  ///
  /// Reverses the MSB-header grouping used by [pack8BitTo7Bit].
  /// Every 8 bytes in [packed] consists of 1 header byte followed by 7 data bytes.
  static Uint8List unpack7BitTo8Bit(
    Uint8List packed, {
    int start = 0,
    int? end,
  }) {
    if (packed.isEmpty) return Uint8List(0);
    final effectiveEnd = end ?? (packed.length - 1);
    if (start > effectiveEnd || start >= packed.length) return Uint8List(0);

    final packedLength = effectiveEnd - start + 1;
    final remainder = packedLength % 8;
    final num8BitBytes = (packedLength ~/ 8) * 7 + (remainder < 2 ? 0 : remainder - 1);
    final result = Uint8List(num8BitBytes);

    int writeIndex = 0;
    int readIndex = start;
    int highBits = 0;

    while (readIndex <= effectiveEnd) {
      final byteVal = packed[readIndex];
      final groupOffset = (readIndex - start) % 8;
      final bitIndex = 7 - groupOffset;

      if (bitIndex == 7) {
        highBits = byteVal;
      } else {
        final msb = ((highBits >> bitIndex) & 1) << 7;
        result[writeIndex++] = (byteVal & 0x7F) | msb;
      }
      readIndex++;
    }

    return result;
  }

  /// Packs 8-bit data into 4-bit nibbles (2 MIDI bytes per 8-bit byte).
  ///
  /// If [msbFirst] is false (default for Line 6), the lower nibble comes first.
  static Uint8List packNibbles(Uint8List unpacked, {bool msbFirst = false}) {
    final result = Uint8List(unpacked.length * 2);
    int writeIndex = 0;
    for (int i = 0; i < unpacked.length; i++) {
      final b = unpacked[i];
      final low = b & 0x0F;
      final high = (b >> 4) & 0x0F;
      if (msbFirst) {
        result[writeIndex++] = high;
        result[writeIndex++] = low;
      } else {
        result[writeIndex++] = low;
        result[writeIndex++] = high;
      }
    }
    return result;
  }

  /// Unpacks 4-bit nibbles back into 8-bit bytes.
  static Uint8List unpackNibbles(Uint8List packed, {bool msbFirst = false}) {
    final length = packed.length ~/ 2;
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      final first = packed[i * 2] & 0x0F;
      final second = packed[i * 2 + 1] & 0x0F;
      if (msbFirst) {
        result[i] = (first << 4) | second;
      } else {
        result[i] = (second << 4) | first;
      }
    }
    return result;
  }

  /// Computes the standard IEEE 802.3 CRC32 checksum for [data].
  static int calculateCrc32(Uint8List data, {int start = 0, int? end}) {
    if (data.isEmpty) return 0;
    final effectiveEnd = end ?? (data.length - 1);
    int crc = 0xFFFFFFFF;
    for (int i = start; i <= effectiveEnd; i++) {
      crc = (crc >>> 8) ^ _crc32Table[(crc ^ data[i]) & 0xFF];
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  /// Computes the 5-byte 7-bit CRC used by Zoom MS Plus pedals.
  ///
  /// Formula: Inverts CRC32, then splits the 32 bits into five 7-bit words (LSB first).
  static Uint8List calculateZoom7BitCrc(
    Uint8List data, {
    int start = 0,
    int? end,
  }) {
    final rawCrc = calculateCrc32(data, start: start, end: end);
    final crc = rawCrc ^ 0xFFFFFFFF;
    return Uint8List.fromList([
      crc & 0x7F,
      (crc >> 7) & 0x7F,
      (crc >> 14) & 0x7F,
      (crc >> 21) & 0x7F,
      (crc >> 28) & 0x0F,
    ]);
  }

  /// Extracts an integer value from a bitfield in [data] spanning from [startBit] to [endBit] inclusive.
  ///
  /// Bit indices are big-endian (MSB-first):
  /// Bit 0 of byte 0 is MSB (0x80), bit 7 of byte 0 is LSB (0x01).
  static int getBits(Uint8List data, int startBit, int endBit) {
    if (startBit > endBit) {
      throw ArgumentError('startBit ($startBit) cannot be greater than endBit ($endBit)');
    }
    final startByte = startBit ~/ 8;
    final endByte = endBit ~/ 8;
    final startBitOffset = startBit % 8;
    final endBitOffset = endBit % 8;

    final startMask = 0xFF >> startBitOffset;
    final endMask = (0xFF00 >> (endBitOffset + 1)) & 0xFF;

    int value = 0;
    for (int i = endByte; i >= startByte; i--) {
      int b = data[i];
      if (i == startByte) b &= startMask;
      if (i == endByte) b &= endMask;
      value += b << ((endByte - i) * 8);
    }
    return value >> (7 - endBitOffset);
  }

  /// Sets an integer [value] into a bitfield in [data] spanning from [startBit] to [endBit] inclusive.
  ///
  /// Bit indices are big-endian (MSB-first):
  /// Bit 0 of byte 0 is MSB (0x80), bit 7 of byte 0 is LSB (0x01).
  static void setBits(Uint8List data, int startBit, int endBit, int value) {
    if (startBit > endBit) {
      throw ArgumentError('startBit ($startBit) cannot be greater than endBit ($endBit)');
    }
    final startByte = startBit ~/ 8;
    final endByte = endBit ~/ 8;
    final startBitOffset = startBit % 8;
    final endBitOffset = endBit % 8;

    final valueStartMask = (0xFF >> startBitOffset) & 0xFF;
    int startMask = (0xFF00 >> startBitOffset) & 0xFF;
    final valueEndMask = (0xFF00 >> (endBitOffset + 1)) & 0xFF;
    int endMask = (0xFF >> (endBitOffset + 1)) & 0xFF;

    if (startByte == endByte) {
      startMask |= endMask;
      endMask = startMask;
    }

    final shiftedValue = value << (7 - endBitOffset);
    for (int i = endByte; i >= startByte; i--) {
      int b = data[i];
      final valueByte = (shiftedValue >> ((endByte - i) * 8)) & 0xFF;

      if (i == startByte) {
        b = (b & startMask) | (valueByte & valueStartMask);
      } else if (i == endByte) {
        b = (b & endMask) | (valueByte & valueEndMask);
      } else {
        b = valueByte;
      }
      data[i] = b;
    }
  }

  /// Checks if [data] is a properly delimited System Exclusive message.
  static bool isSysEx(Uint8List data) {
    return data.length >= 2 && data.first == 0xF0 && data.last == 0xF7;
  }

  /// Checks if [data] matches a Universal Non-Real-Time Identity Reply.
  ///
  /// `F0 7E <channel> 06 02 <manufacturer> ... F7`
  static bool isIdentityReply(Uint8List data) {
    return data.length >= 7 &&
        data[0] == 0xF0 &&
        data[1] == 0x7E &&
        data[3] == 0x06 &&
        data[4] == 0x02 &&
        data.last == 0xF7;
  }
}

