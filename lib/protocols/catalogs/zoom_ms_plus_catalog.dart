export '../../catalog/zoom_ms_plus_catalog_data.dart';

import '../../catalog/zoom_ms_plus_catalog_data.dart';
import '../../models/device_family.dart';
import 'effect_catalog.dart';

/// Built-in effect definitions and parameter descriptors for Zoom MS Plus series pedals.
class ZoomMsPlusCatalog {
  /// Complete built-in MS-60B+ and MS Plus effects extracted from hardware mappings.
  static const List<EffectDefinition> builtInEffects = zoomMsPlusCatalogData;

  /// Returns all available built-in effects.
  static List<EffectDefinition> get allEffects => builtInEffects;

  /// Returns all unique categories available in the Zoom MS Plus catalog.
  static List<String> get categories {
    final cats = <String>{};
    for (final e in builtInEffects) {
      cats.add(e.category);
    }
    return cats.toList()..sort();
  }

  /// Looks up an effect definition by exact integer DSP ID.
  static EffectDefinition? getByIntId(int intId) {
    for (final effect in builtInEffects) {
      if (effect.intEffectId == intId) {
        return effect;
      }
    }
    return null;
  }

  /// Looks up an effect definition by hex string or raw ID.
  static EffectDefinition? getById(String effectId) {
    final clean = effectId.trim().toLowerCase();
    for (final effect in builtInEffects) {
      final effId = effect.effectId.toLowerCase();
      if (effId == clean ||
          effId.replaceFirst('0x', '') == clean ||
          effId == '0x$clean') {
        return effect;
      }
    }
    return null;
  }

  /// Returns all effects matching the specified category.
  static List<EffectDefinition> getByCategory(String category) {
    final target = category.trim().toLowerCase();
    return builtInEffects
        .where((e) => e.category.toLowerCase() == target)
        .toList();
  }

  /// Searches effects by name or category, with optional category filter.
  static List<EffectDefinition> search(String query, {String? category}) {
    final cleanQuery = query.trim().toLowerCase();
    final cleanCategory = category?.trim().toLowerCase();

    return builtInEffects.where((effect) {
      if (cleanCategory != null &&
          cleanCategory.isNotEmpty &&
          effect.category.toLowerCase() != cleanCategory) {
        return false;
      }
      if (cleanQuery.isEmpty) return true;
      return effect.name.toLowerCase().contains(cleanQuery) ||
          effect.category.toLowerCase().contains(cleanQuery);
    }).toList();
  }

  /// Creates a fallback [EffectDefinition] for an unknown Zoom effect ID.
  static EffectDefinition createFallback(int dspId, [DeviceFamily family = DeviceFamily.zoomMs60bPlus]) {
    final hexId = '0x${dspId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    return EffectDefinition(
      effectId: hexId,
      name: dspId == 0 ? 'Bypass' : 'Unknown Effect ($hexId)',
      category: dspId == 0 ? 'Bypass' : 'Unknown',
      deviceFamily: family,
      parameters: const [],
    );
  }
}
