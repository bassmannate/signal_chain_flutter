export '../../catalog/zoom_ms_plus_catalog_data.dart';

import '../../catalog/zoom_ms_plus_catalog_data.dart';
import '../../models/device_family.dart';
import 'effect_catalog.dart';

/// Built-in effect definitions and parameter descriptors for Zoom MS Plus series pedals
/// (MS-60B+, MS-50G+, MS-70CDR+, and MS-200D+).
class ZoomMsPlusCatalog {
  /// Backward-compatible built-in MS-60B+ effects extracted from hardware mappings.
  static const List<EffectDefinition> builtInEffects = zoomMs60bPlusCatalogData;

  /// Returns all available built-in MS-60B+ effects (backward-compatible default).
  static List<EffectDefinition> get allEffects => builtInEffects;

  /// Returns all built-in effects for the specified Zoom MS Plus [family].
  static List<EffectDefinition> effectsForFamily(DeviceFamily family) {
    switch (family) {
      case DeviceFamily.zoomMs50gPlus:
        return zoomMs50gPlusCatalogData;
      case DeviceFamily.zoomMs70cdrPlus:
        return zoomMs70cdrPlusCatalogData;
      case DeviceFamily.zoomMs200dPlus:
        return zoomMs200dPlusCatalogData;
      case DeviceFamily.zoomMs60bPlus:
      case DeviceFamily.line6BassPodPro:
      case DeviceFamily.unknown:
        return zoomMs60bPlusCatalogData;
    }
  }

  /// Returns all unique categories available in the Zoom MS-60B+ catalog.
  static List<String> get categories => categoriesForFamily(DeviceFamily.zoomMs60bPlus);

  /// Returns all unique categories available for the specified Zoom MS Plus [family].
  static List<String> categoriesForFamily(DeviceFamily family) {
    final cats = <String>{};
    for (final e in effectsForFamily(family)) {
      cats.add(e.category);
    }
    return cats.toList()..sort();
  }

  /// Looks up an effect definition by exact integer DSP ID for [family].
  static EffectDefinition? getByIntId(
    int intId, {
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
  }) {
    for (final effect in effectsForFamily(family)) {
      if (effect.intEffectId == intId) {
        return effect;
      }
    }
    return null;
  }

  /// Looks up an effect definition by hex string or raw ID for [family].
  static EffectDefinition? getById(
    String effectId, {
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
  }) {
    final clean = effectId.trim().toLowerCase();
    for (final effect in effectsForFamily(family)) {
      final effId = effect.effectId.toLowerCase();
      if (effId == clean ||
          effId.replaceFirst('0x', '') == clean ||
          effId == '0x$clean') {
        return effect;
      }
    }
    return null;
  }

  /// Returns all effects matching the specified [category] for [family].
  static List<EffectDefinition> getByCategory(
    String category, {
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
  }) {
    final target = category.trim().toLowerCase();
    return effectsForFamily(family)
        .where((e) => e.category.toLowerCase() == target)
        .toList();
  }

  /// Searches effects by name or category for [family], with optional category filter.
  static List<EffectDefinition> search(
    String query, {
    String? category,
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    final cleanCategory = category?.trim().toLowerCase();

    return effectsForFamily(family).where((effect) {
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
  static EffectDefinition createFallback(
    int dspId, [
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
  ]) {
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
