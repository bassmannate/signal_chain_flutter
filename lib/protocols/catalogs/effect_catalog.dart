import 'package:flutter/foundation.dart';

import '../../models/device_family.dart';
import '../../models/parameter_descriptor.dart';
import 'line6_bass_pod_pro_catalog.dart';
import 'zoom_ms_plus_catalog.dart';

/// Immutable specification of a DSP effect type in an effect catalog.
@immutable
class EffectDefinition {
  final String effectId;
  final String name;
  final String category;
  final DeviceFamily deviceFamily;
  final List<ParameterDescriptor> parameters;

  const EffectDefinition({
    required this.effectId,
    required this.name,
    required this.category,
    required this.deviceFamily,
    this.parameters = const [],
  });

  /// Returns the [ParameterDescriptor] at the given index, or null if out of range.
  ParameterDescriptor? getParameter(int index) {
    if (index >= 0 && index < parameters.length) {
      return parameters[index];
    }
    return null;
  }

  EffectDefinition copyWith({
    String? effectId,
    String? name,
    String? category,
    DeviceFamily? deviceFamily,
    List<ParameterDescriptor>? parameters,
  }) {
    return EffectDefinition(
      effectId: effectId ?? this.effectId,
      name: name ?? this.name,
      category: category ?? this.category,
      deviceFamily: deviceFamily ?? this.deviceFamily,
      parameters: parameters ?? this.parameters,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectDefinition &&
          runtimeType == other.runtimeType &&
          effectId == other.effectId &&
          name == other.name &&
          category == other.category &&
          deviceFamily == other.deviceFamily &&
          listEquals(parameters, other.parameters);

  @override
  int get hashCode => Object.hash(
        effectId,
        name,
        category,
        deviceFamily,
        Object.hashAll(parameters),
      );

  @override
  String toString() =>
      'EffectDefinition(id: $effectId, name: "$name", cat: "$category", family: ${deviceFamily.displayName})';
}

/// Global registry and lookup service for device effect definitions and parameter schemas.
class EffectCatalogRegistry {
  static final Map<DeviceFamily, Map<String, EffectDefinition>> _catalogs = {};
  static bool _initialized = false;

  /// Ensures built-in effect catalogs are populated.
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    // Register Zoom MS Plus effects across supported Zoom families
    for (final def in ZoomMsPlusCatalog.builtInEffects) {
      register(def);
      // Also register for other Zoom MS Plus models if it belongs to Zoom MS-60B+
      if (def.deviceFamily == DeviceFamily.zoomMs60bPlus) {
        register(def.copyWith(deviceFamily: DeviceFamily.zoomMs50gPlus));
        register(def.copyWith(deviceFamily: DeviceFamily.zoomMs70cdrPlus));
        register(def.copyWith(deviceFamily: DeviceFamily.zoomMs200dPlus));
      }
    }

    // Register Line 6 Bass Pod Pro effects
    registerAll(Line6BassPodProCatalog.builtInEffects);
  }

  /// Registers an individual [EffectDefinition].
  static void register(EffectDefinition definition) {
    final familyMap = _catalogs.putIfAbsent(definition.deviceFamily, () => {});
    familyMap[definition.effectId.toLowerCase()] = definition;
  }

  /// Registers a collection of [EffectDefinition]s.
  static void registerAll(Iterable<EffectDefinition> definitions) {
    for (final def in definitions) {
      register(def);
    }
  }

  /// Resolves an [EffectDefinition] by [family] and [effectId].
  ///
  /// Returns a clean fallback definition when the effect is not recognized.
  static EffectDefinition getDefinition(DeviceFamily family, String effectId) {
    ensureInitialized();
    final familyMap = _catalogs[family];
    final normalized = effectId.trim().toLowerCase();

    // 1. Direct match
    if (familyMap != null && familyMap.containsKey(normalized)) {
      return familyMap[normalized]!;
    }

    // 2. Hex prefix normalization (e.g., "0x01000010" vs "01000010")
    if (familyMap != null) {
      if (normalized.startsWith('0x')) {
        final stripped = normalized.substring(2);
        if (familyMap.containsKey(stripped)) {
          return familyMap[stripped]!;
        }
      } else {
        final prefixed = '0x$normalized';
        if (familyMap.containsKey(prefixed)) {
          return familyMap[prefixed]!;
        }
      }
    }

    // 3. Fallback definition
    return createFallbackDefinition(family, effectId);
  }

  /// Creates a fallback [EffectDefinition] for unmapped DSP IDs.
  static EffectDefinition createFallbackDefinition(DeviceFamily family, String effectId) {
    final cleanId = effectId.trim();
    final isBypass = cleanId == '0' ||
        cleanId == '0x0' ||
        cleanId.toLowerCase() == '0x00000000' ||
        cleanId.toLowerCase() == 'bypass';

    final name = isBypass ? 'Bypass' : 'Unknown Effect ($cleanId)';
    final category = isBypass ? 'Bypass' : 'Unknown';

    return EffectDefinition(
      effectId: cleanId,
      name: name,
      category: category,
      deviceFamily: family,
      parameters: const [],
    );
  }

  /// Returns all registered [EffectDefinition]s for a given [family].
  static List<EffectDefinition> getEffectsForFamily(DeviceFamily family) {
    ensureInitialized();
    return _catalogs[family]?.values.toList() ?? const [];
  }

  /// Returns all unique category names registered for a [family].
  static List<String> getCategories(DeviceFamily family) {
    ensureInitialized();
    final effects = getEffectsForFamily(family);
    final categories = <String>{};
    for (final e in effects) {
      categories.add(e.category);
    }
    return categories.toList()..sort();
  }

  /// Clears registry state (primarily used in unit test isolation).
  @visibleForTesting
  static void reset() {
    _catalogs.clear();
    _initialized = false;
  }
}

