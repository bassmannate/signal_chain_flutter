import 'package:flutter/foundation.dart';

/// Immutable descriptor representing a MIDI input or output port.
@immutable
class MidiPortDescriptor {
  final String id;
  final String name;
  final String? manufacturer;
  final bool isInput;
  final bool isOutput;

  const MidiPortDescriptor({
    required this.id,
    required this.name,
    this.manufacturer,
    required this.isInput,
    required this.isOutput,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiPortDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          manufacturer == other.manufacturer &&
          isInput == other.isInput &&
          isOutput == other.isOutput;

  @override
  int get hashCode => Object.hash(id, name, manufacturer, isInput, isOutput);

  @override
  String toString() =>
      'MidiPortDescriptor(id: $id, name: $name, manufacturer: $manufacturer, '
      'isInput: $isInput, isOutput: $isOutput)';
}
