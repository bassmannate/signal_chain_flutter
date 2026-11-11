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

  const EffectSlot({
    required this.slotIndex,
    required this.effectId,
    required this.effectName,
    this.isEnabled = true,
    this.parameters = const [],
  });

  EffectSlot copyWith({
    int? slotIndex,
    String? effectId,
    String? effectName,
    bool? isEnabled,
    List<ParameterValue>? parameters,
  }) {
    return EffectSlot(
      slotIndex: slotIndex ?? this.slotIndex,
      effectId: effectId ?? this.effectId,
      effectName: effectName ?? this.effectName,
      isEnabled: isEnabled ?? this.isEnabled,
      parameters: parameters ?? this.parameters,
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
          listEquals(parameters, other.parameters);

  @override
  int get hashCode => Object.hash(
        slotIndex,
        effectId,
        effectName,
        isEnabled,
        Object.hashAll(parameters),
      );

  @override
  String toString() =>
      'EffectSlot(slot: $slotIndex, name: $effectName [id: $effectId], '
      'enabled: $isEnabled, params: ${parameters.length})';
}

