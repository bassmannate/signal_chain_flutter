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
  final int displayOffset;
  final List<String>? valueLabels;

  const ParameterDescriptor({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.step = 1.0,
    this.unit,
    this.labels,
    this.displayOffset = 0,
    this.valueLabels,
  });

  /// Effective list of discrete labels (checking [valueLabels] then [labels]).
  List<String>? get effectiveLabels => valueLabels ?? labels;

  /// True if this parameter selects between discrete named states or models.
  bool get isDiscrete => effectiveLabels != null && effectiveLabels!.isNotEmpty;

  /// Formats a raw zero-based parameter value (`0..max`) into the exact human-readable
  /// string matching physical pedal screens, applying discrete label lookups, display offsets,
  /// or step decimals.
  String formatValue(num rawValue) {
    final labelsList = effectiveLabels;
    if (labelsList != null && labelsList.isNotEmpty) {
      final index = rawValue.round();
      if (index >= 0 && index < labelsList.length) {
        return labelsList[index];
      }
    }

    final num displayNum = rawValue + displayOffset;
    final formatted = step < 1.0
        ? displayNum.toStringAsFixed(1)
        : (displayNum == displayNum.roundToDouble()
            ? displayNum.round().toString()
            : displayNum.toString());

    return unit != null ? '$formatted $unit' : formatted;
  }

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
        if (displayOffset != 0) 'displayOffset': displayOffset,
        if (valueLabels != null) 'valueLabels': valueLabels,
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
      displayOffset: (json['displayOffset'] as num?)?.toInt() ?? 0,
      valueLabels: (json['valueLabels'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
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
          displayOffset == other.displayOffset &&
          listEquals(labels, other.labels) &&
          listEquals(valueLabels, other.valueLabels);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        min,
        max,
        defaultValue,
        step,
        unit,
        displayOffset,
        labels == null ? null : Object.hashAll(labels!),
        valueLabels == null ? null : Object.hashAll(valueLabels!),
      );

  @override
  String toString() =>
      'ParameterDescriptor(id: $id, name: $name, range: $min..$max, offset: $displayOffset, default: $defaultValue)';
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

  /// Human-readable representation of the current value, resolving discrete labels or offsets.
  String get displayValue => descriptor.formatValue(currentValue);

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
