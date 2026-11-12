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
  final List<String> tags;
  final String? author;
  final String? notes;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;

  const Patch({
    required this.id,
    required this.name,
    required this.deviceFamily,
    this.programNumber,
    this.slots = const [],
    this.tags = const [],
    this.author,
    this.notes,
    this.updatedAt,
    this.metadata = const {},
  });

  /// Active patch tempo in BPM (typically 40–250 BPM, default 120).
  int get tempo => ((metadata['tempo'] as num?)?.round()) ?? 120;

  Patch copyWith({
    String? id,
    String? name,
    DeviceFamily? deviceFamily,
    int? programNumber,
    List<EffectSlot>? slots,
    List<String>? tags,
    String? author,
    String? notes,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Patch(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceFamily: deviceFamily ?? this.deviceFamily,
      programNumber: programNumber ?? this.programNumber,
      slots: slots ?? this.slots,
      tags: tags ?? this.tags,
      author: author ?? this.author,
      notes: notes ?? this.notes,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Serializes this patch into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deviceFamily': deviceFamily.toJson(),
        if (programNumber != null) 'programNumber': programNumber,
        'slots': slots.map((s) => s.toJson()).toList(),
        if (tags.isNotEmpty) 'tags': tags,
        if (author != null) 'author': author,
        if (notes != null) 'notes': notes,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  /// Deserializes a [Patch] from a JSON map.
  factory Patch.fromJson(Map<String, dynamic> json) {
    return Patch(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      deviceFamily: DeviceFamily.fromJson(json['deviceFamily']),
      programNumber: json['programNumber'] as int?,
      slots: (json['slots'] as List<dynamic>?)
              ?.map((e) => EffectSlot.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      author: json['author'] as String?,
      notes: json['notes'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
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
          listEquals(tags, other.tags) &&
          author == other.author &&
          notes == other.notes &&
          updatedAt == other.updatedAt &&
          mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        deviceFamily,
        programNumber,
        Object.hashAll(slots),
        Object.hashAll(tags),
        author,
        notes,
        updatedAt,
        Object.hash(
          Object.hashAll(metadata.keys),
          Object.hashAll(metadata.values),
        ),
      );

  @override
  String toString() =>
      'Patch(id: $id, name: "$name", family: ${deviceFamily.displayName}, '
      'prog: $programNumber, slots: ${slots.length}, tags: $tags)';
}
