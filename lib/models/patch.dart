import 'package:flutter/foundation.dart';
import 'device_family.dart';
import 'effect_slot.dart';

/// Constants and normalization helpers for the Zoom MS+ configurable Right-Output
/// (`R-Out`) signal tap point encoded in `PRM2` byte 13 bits `1..3`.
///
/// Tap code values:
/// - `0`: End of chain (`OUT`, default — L and R both output after the final slot)
/// - `1`: Input (`IN`, dry signal before slot 0)
/// - `2..6`: After 0-based slot index `code - 2` (so `2` = after Effect 1 / slot 0,
///   `5` = after Effect 4 / slot 3, `6` = after Effect 5 / slot 4)
abstract final class RightOutputTap {
  static const int endOfChain = 0;
  static const int input = 1;
  static const int minSlotTapCode = 2;
  static const int maxCode = 6;

  /// Returns the tap code representing a split right after 0-based [slotIndex].
  static int afterSlot(int slotIndex) => slotIndex + minSlotTapCode;

  /// Returns the 0-based slot index whose output is tapped by [tapCode],
  /// or `null` when [tapCode] represents [endOfChain] (`0`) or [input] (`1`).
  static int? slotIndexFor(int tapCode) =>
      tapCode >= minSlotTapCode && tapCode <= maxCode
          ? tapCode - minSlotTapCode
          : null;

  /// Normalizes [tapCode] against a signal chain of length [slotCount].
  ///
  /// Tapping after the final slot (`tapCode == slotCount + 1`) is equivalent
  /// to [endOfChain] (`0`) and normalizes to `0`. Invalid or out-of-range
  /// values also fall back safely to `0`.
  static int normalize(int tapCode, {required int slotCount}) {
    if (slotCount <= 0) return endOfChain;
    if (tapCode == endOfChain || tapCode == input) return tapCode;
    if (tapCode >= minSlotTapCode &&
        tapCode <= slotCount &&
        tapCode <= maxCode) {
      return tapCode;
    }
    return endOfChain;
  }

  /// Adjusts [tapCode] after removing 0-based [removedIndex] from an MS+ chain,
  /// resulting in [newSlotCount] remaining slots.
  static int adjustForRemovedSlot(
    int tapCode, {
    required int removedIndex,
    required int newSlotCount,
  }) {
    if (tapCode < minSlotTapCode) {
      return normalize(tapCode, slotCount: newSlotCount);
    }
    final tapSlot = tapCode - minSlotTapCode;
    if (tapSlot == removedIndex) {
      return endOfChain;
    }
    final shifted = tapSlot > removedIndex ? tapCode - 1 : tapCode;
    return normalize(shifted, slotCount: newSlotCount);
  }

  /// Human-readable full label for menus and tooltips.
  static String describe(int tapCode, {List<EffectSlot> slots = const []}) {
    if (tapCode == endOfChain) return 'End of Chain (L+R Out)';
    if (tapCode == input) return 'Input (Dry)';
    final slotIdx = slotIndexFor(tapCode);
    if (slotIdx != null) {
      final rawName =
          slotIdx < slots.length ? slots[slotIdx].effectName.trim() : '';
      final name = rawName.isNotEmpty ? rawName : 'Effect ${slotIdx + 1}';
      return 'After ${slotIdx + 1}: $name';
    }
    return 'End of Chain (L+R Out)';
  }

  /// Compact summary label for pills and diff rows.
  static String shortLabel(int tapCode, {List<EffectSlot> slots = const []}) {
    if (tapCode == endOfChain) return 'End (L+R)';
    if (tapCode == input) return 'Input (Dry)';
    final slotIdx = slotIndexFor(tapCode);
    if (slotIdx != null) {
      final rawName =
          slotIdx < slots.length ? slots[slotIdx].effectName.trim() : '';
      return rawName.isNotEmpty
          ? 'After #${slotIdx + 1} ($rawName)'
          : 'After #${slotIdx + 1}';
    }
    return 'End (L+R)';
  }
}

/// Immutable representation of a device preset/patch containing an effect chain and metadata.
@immutable
class Patch {
  final String id;
  final String name;
  final DeviceFamily deviceFamily;
  final int? programNumber;
  final List<EffectSlot> slots;
  final int rightOutputTapCode;
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
    this.rightOutputTapCode = RightOutputTap.endOfChain,
    this.tags = const [],
    this.author,
    this.notes,
    this.updatedAt,
    this.metadata = const {},
  });

  /// Active patch tempo in BPM (typically 40–250 BPM, default 120).
  int get tempo => ((metadata['tempo'] as num?)?.round()) ?? 120;

  /// Hardware generation derived from [deviceFamily].
  DeviceGeneration get deviceGeneration => deviceFamily.generation;

  /// Alias for [deviceGeneration].
  DeviceGeneration get generation => deviceFamily.generation;

  /// True when [deviceFamily] supports a configurable Right-Output (`R-Out`) signal tap.
  bool get supportsConfigurableRightOutput =>
      deviceFamily.supportsConfigurableRightOutput;

  /// Normalized Right-Output tap code for this patch (`0` for non-MS+ devices).
  int get effectiveRightOutputTapCode => supportsConfigurableRightOutput
      ? RightOutputTap.normalize(rightOutputTapCode, slotCount: slots.length)
      : RightOutputTap.endOfChain;

  /// Checks whether [candidate] matches the effect chain signature of [target],
  /// ignoring volatile fields like [id], [programNumber], and timestamps.
  ///
  /// If [matchParameters] is true, parameter values and trailing raw values
  /// are compared for equality (within 0.05 tolerance).
  static bool isSignatureMatch(
    Patch target,
    Patch candidate, {
    bool matchParameters = true,
  }) {
    // 1. Name comparison (trimmed, case-insensitive if non-empty)
    final targetName = target.name.trim();
    final candidateName = candidate.name.trim();
    if (targetName.isNotEmpty && candidateName.isNotEmpty) {
      if (targetName.toLowerCase() != candidateName.toLowerCase()) {
        return false;
      }
    } else if (targetName != candidateName) {
      return false;
    }

    // 2. Right-Output routing tap comparison
    if (target.effectiveRightOutputTapCode !=
        candidate.effectiveRightOutputTapCode) {
      return false;
    }

    // 3. Slot count
    if (target.slots.length != candidate.slots.length) {
      return false;
    }

    // 4. Effect slots comparison
    for (int i = 0; i < target.slots.length; i++) {
      final slotA = target.slots[i];
      final slotB = candidate.slots[i];

      if (slotA.effectId != slotB.effectId) {
        return false;
      }
      if (slotA.isEnabled != slotB.isEnabled) {
        return false;
      }

      if (matchParameters) {
        if (slotA.parameters.length != slotB.parameters.length) {
          return false;
        }
        for (int p = 0; p < slotA.parameters.length; p++) {
          final valA = slotA.parameters[p].currentValue;
          final valB = slotB.parameters[p].currentValue;
          if ((valA - valB).abs() > 0.05) {
            return false;
          }
        }

        // Compare raw trailing values if present
        final trailA = slotA.rawTrailingValues;
        final trailB = slotB.rawTrailingValues;
        if (trailA != null && trailB != null) {
          if (trailA.length != trailB.length) return false;
          for (int t = 0; t < trailA.length; t++) {
            if ((trailA[t] - trailB[t]).abs() > 0.05) return false;
          }
        }
      }
    }

    return true;
  }

  Patch copyWith({
    String? id,
    String? name,
    DeviceFamily? deviceFamily,
    int? programNumber,
    List<EffectSlot>? slots,
    int? rightOutputTapCode,
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
      rightOutputTapCode: rightOutputTapCode ?? this.rightOutputTapCode,
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
        if (rightOutputTapCode != RightOutputTap.endOfChain)
          'rightOutputTapCode': rightOutputTapCode,
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
      rightOutputTapCode:
          (json['rightOutputTapCode'] as num?)?.toInt() ??
              RightOutputTap.endOfChain,
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
          rightOutputTapCode == other.rightOutputTapCode &&
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
        rightOutputTapCode,
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
      'prog: $programNumber, slots: ${slots.length}, rOut: $rightOutputTapCode, tags: $tags)';
}
