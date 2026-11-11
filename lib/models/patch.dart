import 'package:flutter/foundation.dart';
import 'device_family.dart';
import 'effect_slot.dart';

/// Immutable representation of a device preset/patch containing an effect chain and metadata.
@immutable
class Patch {
  final String id;
  final String name;
  final DeviceFamily deviceFamily;
  final int? programNumber;
  final List<EffectSlot> slots;
  final Map<String, dynamic> metadata;

  const Patch({
    required this.id,
    required this.name,
    required this.deviceFamily,
    this.programNumber,
    this.slots = const [],
    this.metadata = const {},
  });

  Patch copyWith({
    String? id,
    String? name,
    DeviceFamily? deviceFamily,
    int? programNumber,
    List<EffectSlot>? slots,
    Map<String, dynamic>? metadata,
  }) {
    return Patch(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceFamily: deviceFamily ?? this.deviceFamily,
      programNumber: programNumber ?? this.programNumber,
      slots: slots ?? this.slots,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Patch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          deviceFamily == other.deviceFamily &&
          programNumber == other.programNumber &&
          listEquals(slots, other.slots) &&
          mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        deviceFamily,
        programNumber,
        Object.hashAll(slots),
        Object.hash(
          Object.hashAll(metadata.keys),
          Object.hashAll(metadata.values),
        ),
      );

  @override
  String toString() =>
      'Patch(id: $id, name: "$name", family: ${deviceFamily.displayName}, '
      'prog: $programNumber, slots: ${slots.length})';
}
