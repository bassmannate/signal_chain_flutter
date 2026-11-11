import 'package:flutter/foundation.dart';

/// Immutable wrapper around raw MIDI bytes with timestamp and protocol helpers.
@immutable
class MidiMessage {
  final Uint8List data;
  final DateTime timestamp;

  MidiMessage(this.data, {DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  /// Returns true if this message is a System Exclusive message (starts with 0xF0 and ends with 0xF7).
  bool get isSysEx => data.length >= 2 && data.first == 0xF0 && data.last == 0xF7;

  /// Returns true if this message is a Control Change status message (0xBn).
  bool get isControlChange => data.length >= 3 && (data[0] & 0xF0) == 0xB0;

  /// Returns true if this message is a Program Change status message (0xCn).
  bool get isProgramChange => data.length >= 2 && (data[0] & 0xF0) == 0xC0;

  /// Creates a SysEx MIDI message from [payload], ensuring it is framed with 0xF0 and 0xF7.
  factory MidiMessage.sysEx(List<int> payload, {DateTime? timestamp}) {
    if (payload.length >= 2 && payload.first == 0xF0 && payload.last == 0xF7) {
      return MidiMessage(Uint8List.fromList(payload), timestamp: timestamp);
    }
    final List<int> framed = [];
    if (payload.isEmpty || payload.first != 0xF0) {
      framed.add(0xF0);
    }
    framed.addAll(payload);
    if (framed.last != 0xF7) {
      framed.add(0xF7);
    }
    return MidiMessage(Uint8List.fromList(framed), timestamp: timestamp);
  }

  /// Creates a standard 3-byte Control Change (CC) MIDI message.
  ///
  /// [channel] is 0-indexed (0–15).
  /// [controller] is the CC number (0–127).
  /// [value] is the CC value (0–127).
  factory MidiMessage.controlChange({
    required int channel,
    required int controller,
    required int value,
    DateTime? timestamp,
  }) {
    final status = 0xB0 | (channel & 0x0F);
    final cc = controller & 0x7F;
    final val = value & 0x7F;
    return MidiMessage(
      Uint8List.fromList([status, cc, val]),
      timestamp: timestamp,
    );
  }

  /// Creates a standard 2-byte Program Change (PC) MIDI message.
  ///
  /// [channel] is 0-indexed (0–15).
  /// [program] is the program number (0–127).
  factory MidiMessage.programChange({
    required int channel,
    required int program,
    DateTime? timestamp,
  }) {
    final status = 0xC0 | (channel & 0x0F);
    final prog = program & 0x7F;
    return MidiMessage(
      Uint8List.fromList([status, prog]),
      timestamp: timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MidiMessage) return false;
    if (data.length != other.data.length) return false;
    for (int i = 0; i < data.length; i++) {
      if (data[i] != other.data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int result = 17;
    for (int i = 0; i < data.length; i++) {
      result = 37 * result + data[i];
    }
    return result;
  }

  @override
  String toString() {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    return 'MidiMessage([$hex], timestamp: ${timestamp.toIso8601String()})';
  }
}
