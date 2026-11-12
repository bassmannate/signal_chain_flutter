import 'package:flutter/foundation.dart';
import 'parameter_descriptor.dart';

/// Immutable representation of an individual effect block inside an effects chain.
@immutable
class EffectSlot {
  final int slotIndex;
  final String effectId;
  final String effectName;
  final bool isEnabled;
  final List<ParameterValue> parameters;
  final List<double>? rawTrailingValues;

  const EffectSlot({
    required this.slotIndex,
    required this.effectId,
    required this.effectName,
    this.isEnabled = true,
    this.parameters = const [],
    this.rawTrailingValues,
  });

  EffectSlot copyWith({
    int? slotIndex,
    String? effectId,
    String? effectName,
    bool? isEnabled,
    List<ParameterValue>? parameters,
    List<double>? rawTrailingValues,
  }) {
    return EffectSlot(
      slotIndex: slotIndex ?? this.slotIndex,
      effectId: effectId ?? this.effectId,
      effectName: effectName ?? this.effectName,
      isEnabled: isEnabled ?? this.isEnabled,
      parameters: parameters ?? this.parameters,
      rawTrailingValues: rawTrailingValues ?? this.rawTrailingValues,
    );
  }

  /// Serializes this effect slot into a JSON map.
  Map<String, dynamic> toJson() => {
        'slotIndex': slotIndex,
        'effectId': effectId,
        'effectName': effectName,
        'isEnabled': isEnabled,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        if (rawTrailingValues != null) 'rawTrailingValues': rawTrailingValues,
      };

  /// Deserializes an [EffectSlot] from a JSON map.
  factory EffectSlot.fromJson(Map<String, dynamic> json) {
    return EffectSlot(
      slotIndex: json['slotIndex'] as int? ?? 0,
      effectId: json['effectId'] as String? ?? '',
      effectName: json['effectName'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
      parameters: (json['parameters'] as List<dynamic>?)
              ?.map((e) => ParameterValue.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      rawTrailingValues: (json['rawTrailingValues'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectSlot &&
          runtimeType == other.runtimeType &&
          slotIndex == other.slotIndex &&
          effectId == other.effectId &&
          effectName == other.effectName &&
          isEnabled == other.isEnabled &&
          listEquals(parameters, other.parameters) &&
          listEquals(rawTrailingValues, other.rawTrailingValues);

  @override
  int get hashCode => Object.hash(
        slotIndex,
        effectId,
        effectName,
        isEnabled,
        Object.hashAll(parameters),
        rawTrailingValues == null ? null : Object.hashAll(rawTrailingValues!),
      );

  @override
  String toString() =>
      'EffectSlot(slot: $slotIndex, name: $effectName [id: $effectId], '
      'enabled: $isEnabled, params: ${parameters.length})';
}

