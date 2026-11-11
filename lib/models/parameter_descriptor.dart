import 'package:flutter/foundation.dart';

/// Immutable specification of a configurable DSP parameter.
@immutable
class ParameterDescriptor {
  final String id;
  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final double step;
  final String? unit;
  final List<String>? labels;

  const ParameterDescriptor({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.step = 1.0,
    this.unit,
    this.labels,
  });

  /// True if this parameter selects between discrete named states or models.
  bool get isDiscrete => labels != null && labels!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParameterDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          min == other.min &&
          max == other.max &&
          defaultValue == other.defaultValue &&
          step == other.step &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(id, name, min, max, defaultValue, step, unit);

  @override
  String toString() =>
      'ParameterDescriptor(id: $id, name: $name, range: $min..$max, default: $defaultValue)';
}

/// Immutable state holding the active value for a given [ParameterDescriptor].
@immutable
class ParameterValue {
  final ParameterDescriptor descriptor;
  final double currentValue;

  const ParameterValue({
    required this.descriptor,
    required this.currentValue,
  });

  /// Value scaled from 0.0 to 1.0 based on [descriptor.min] and [descriptor.max].
  double get normalizedValue {
    if (descriptor.max <= descriptor.min) return 0.0;
    final range = descriptor.max - descriptor.min;
    return ((currentValue - descriptor.min) / range).clamp(0.0, 1.0);
  }

  /// Human-readable representation of the current value, resolving discrete labels if available.
  String get displayValue {
    if (descriptor.labels != null && descriptor.labels!.isNotEmpty) {
      final index = currentValue.round();
      if (index >= 0 && index < descriptor.labels!.length) {
        return descriptor.labels![index];
      }
    }
    final formatted = currentValue.toStringAsFixed(descriptor.step < 1.0 ? 1 : 0);
    return descriptor.unit != null ? '$formatted ${descriptor.unit}' : formatted;
  }

  ParameterValue copyWith({double? currentValue}) {
    return ParameterValue(
      descriptor: descriptor,
      currentValue: currentValue ?? this.currentValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParameterValue &&
          runtimeType == other.runtimeType &&
          descriptor == other.descriptor &&
          currentValue == other.currentValue;

  @override
  int get hashCode => Object.hash(descriptor, currentValue);

  @override
  String toString() =>
      'ParameterValue(${descriptor.name}: $displayValue [raw: $currentValue])';
}
