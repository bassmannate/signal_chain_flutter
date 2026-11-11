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

  /// Serializes this descriptor into a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'min': min,
        'max': max,
        'defaultValue': defaultValue,
        'step': step,
        if (unit != null) 'unit': unit,
        if (labels != null) 'labels': labels,
      };

  /// Deserializes a [ParameterDescriptor] from a JSON map.
  factory ParameterDescriptor.fromJson(Map<String, dynamic> json) {
    return ParameterDescriptor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 100.0,
      defaultValue: (json['defaultValue'] as num?)?.toDouble() ?? 0.0,
      step: (json['step'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit'] as String?,
      labels: (json['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }

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
          unit == other.unit &&
          listEquals(labels, other.labels);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        min,
        max,
        defaultValue,
        step,
        unit,
        labels == null ? null : Object.hashAll(labels!),
      );

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

  /// Serializes this parameter value into a JSON map.
  Map<String, dynamic> toJson() => {
        'descriptor': descriptor.toJson(),
        'currentValue': currentValue,
      };

  /// Deserializes a [ParameterValue] from a JSON map.
  factory ParameterValue.fromJson(Map<String, dynamic> json) {
    return ParameterValue(
      descriptor: ParameterDescriptor.fromJson(
        json['descriptor'] as Map<String, dynamic>? ?? {},
      ),
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0.0,
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
