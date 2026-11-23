import 'package:flutter/foundation.dart';

import '../../models/device_family.dart';
import '../../models/parameter_descriptor.dart';
import '../../data/zoom_four_catalog.dart';
import '../../data/zoom_zdl7_master_catalog.dart';
import 'line6_bass_pod_pro_catalog.dart';
import 'zoom_ms_plus_catalog.dart';

/// Provenance tier indicating where an [EffectDefinition] was resolved from.
enum EffectOrigin {
  /// Built-in stock effect for the active pedal model.
  stock,

  /// Built-in effect resolved from a sibling model in the same hardware generation
  /// (or the extended ZDL7 master catalog on Zoom Four).
  crossModel,

  /// User-imported custom `.ZD2` effect definition.
  custom,

  /// Unrecognized DSP effect ID using a generic fallback definition.
  unknown,
}

/// Alias for [EffectDefinition] used throughout palette and drag-and-drop operations.
typedef EffectCatalogEntry = EffectDefinition;

/// Registered custom `.ZD2` effect record stored inside [EffectCatalogRegistry].
@immutable
class RegisteredCustomEffect {
  final EffectDefinition definition;
  final DeviceGeneration? generation;

  const RegisteredCustomEffect({
    required this.definition,
    this.generation,
  });

  /// Returns true if this custom effect is compatible with [family].
  bool isCompatibleWith(DeviceFamily family) {
    if (!family.isZoom6E) return false;
    return generation == null ||
        generation == DeviceGeneration.unknown ||
        generation == family.generation;
  }
}

/// Immutable specification of a DSP effect type in an effect catalog.
@immutable
class EffectDefinition {
  final String effectId;
  final String name;
  final String category;
  final DeviceFamily deviceFamily;
  final List<ParameterDescriptor> parameters;
  final int? dspLoad;
  final EffectOrigin origin;
  final String? sourceModelLabel;
  final String? sourceFilename;
  final String? description;
  final String? version;

  const EffectDefinition({
    required this.effectId,
    required this.name,
    required this.category,
    required this.deviceFamily,
    this.parameters = const [],
    this.dspLoad,
    this.origin = EffectOrigin.stock,
    this.sourceModelLabel,
    this.sourceFilename,
    this.description,
    this.version,
  });

  /// The integer DSP effect ID (parsed from hex if string starts with 0x).
  int get intEffectId {
    final clean = effectId.trim();
    if (clean.startsWith('0x') || clean.startsWith('0X')) {
      return int.tryParse(clean.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(clean) ?? 0;
  }

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
    int? dspLoad,
    EffectOrigin? origin,
    String? sourceModelLabel,
    String? sourceFilename,
    String? description,
    String? version,
  }) {
    return EffectDefinition(
      effectId: effectId ?? this.effectId,
      name: name ?? this.name,
      category: category ?? this.category,
      deviceFamily: deviceFamily ?? this.deviceFamily,
      parameters: parameters ?? this.parameters,
      dspLoad: dspLoad ?? this.dspLoad,
      origin: origin ?? this.origin,
      sourceModelLabel: sourceModelLabel ?? this.sourceModelLabel,
      sourceFilename: sourceFilename ?? this.sourceFilename,
      description: description ?? this.description,
      version: version ?? this.version,
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
          dspLoad == other.dspLoad &&
          origin == other.origin &&
          sourceModelLabel == other.sourceModelLabel &&
          sourceFilename == other.sourceFilename &&
          description == other.description &&
          version == other.version &&
          listEquals(parameters, other.parameters);

  @override
  int get hashCode => Object.hash(
        effectId,
        name,
        category,
        deviceFamily,
        dspLoad,
        origin,
        sourceModelLabel,
        sourceFilename,
        description,
        version,
        Object.hashAll(parameters),
      );

  @override
  String toString() =>
      'EffectDefinition(id: $effectId, name: "$name", cat: "$category", '
      'origin: ${origin.name}, family: ${deviceFamily.displayName})';
}

/// Global registry and lookup service for device effect definitions and parameter schemas.
class EffectCatalogRegistry {
  static final Map<DeviceFamily, Map<String, EffectDefinition>> _catalogs = {};
  static final List<RegisteredCustomEffect> _customEffects = [];
  static final Map<DeviceFamily, Set<String>> _installedCrossModelIds = {};
  static bool _initialized = false;

  /// Monotonically increasing revision counter notified whenever custom effects
  /// are registered, updated, removed, or cleared.
  static final ValueNotifier<int> catalogRevision = ValueNotifier<int>(0);

  /// Deterministic Zoom MS+ sibling resolution order for Tier 2 lookups.
  static const List<DeviceFamily> _msPlusSiblingOrder = [
    DeviceFamily.zoomMs60bPlus,
    DeviceFamily.zoomMs50gPlus,
    DeviceFamily.zoomMs70cdrPlus,
    DeviceFamily.zoomMs200dPlus,
  ];

  /// Deterministic Zoom Four sibling resolution order for Tier 2 lookups.
  static const List<DeviceFamily> _zoomFourSiblingOrder = [
    DeviceFamily.zoomB1xFour,
    DeviceFamily.zoomB1Four,
    DeviceFamily.zoomG1xFour,
    DeviceFamily.zoomG1Four,
  ];

  static void _notifyCatalogChanged() {
    catalogRevision.value = catalogRevision.value + 1;
  }

  /// Returns a concise hardware model label for cross-model origin badges.
  static String conciseModelLabel(DeviceFamily family) {
    switch (family) {
      case DeviceFamily.zoomMs60bPlus:
        return 'MS-60B+';
      case DeviceFamily.zoomMs50gPlus:
        return 'MS-50G+';
      case DeviceFamily.zoomMs70cdrPlus:
        return 'MS-70CDR+';
      case DeviceFamily.zoomMs200dPlus:
        return 'MS-200D+';
      case DeviceFamily.zoomB1xFour:
        return 'B1X FOUR';
      case DeviceFamily.zoomB1Four:
        return 'B1 FOUR';
      case DeviceFamily.zoomG1xFour:
        return 'G1X FOUR';
      case DeviceFamily.zoomG1Four:
        return 'G1 FOUR';
      case DeviceFamily.line6BassPodPro:
        return 'Bass POD Pro';
      case DeviceFamily.unknown:
        return 'Unknown';
    }
  }

  /// Normalizes a hex effect ID string to canonical lowercase `'0x01000010'` form,
  /// or returns `null` if [raw] is not a hex identifier.
  static String? _canonicalHexLower(String raw) {
    final clean = raw.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final hexPart = clean.startsWith('0x') ? clean.substring(2) : clean;
    if (hexPart.isEmpty || !RegExp(r'^[0-9a-f]+$').hasMatch(hexPart)) {
      return null;
    }
    final parsed = int.tryParse(hexPart, radix: 16);
    if (parsed == null) return null;
    return '0x${parsed.toRadixString(16).padLeft(8, '0')}';
  }

  static EffectDefinition? _lookupInFamilyMap(
    Map<String, EffectDefinition>? familyMap,
    String effectId,
  ) {
    if (familyMap == null || familyMap.isEmpty) return null;
    final normalized = effectId.trim().toLowerCase();

    if (familyMap.containsKey(normalized)) {
      return familyMap[normalized]!;
    }

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

    final canonical = _canonicalHexLower(normalized);
    if (canonical != null) {
      if (familyMap.containsKey(canonical)) {
        return familyMap[canonical]!;
      }
      final canonicalStripped = canonical.substring(2);
      if (familyMap.containsKey(canonicalStripped)) {
        return familyMap[canonicalStripped]!;
      }
    }

    return null;
  }

  /// Ensures built-in effect catalogs are populated.
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    // Register dedicated catalogs for each Zoom MS Plus pedal model
    registerAll(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs60bPlus));
    registerAll(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs50gPlus));
    registerAll(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs70cdrPlus));
    registerAll(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs200dPlus));

    // Register dedicated catalogs for Zoom Four series pedals
    registerAll(ZoomFourCatalog.effectsForFamily(DeviceFamily.zoomB1xFour));
    registerAll(ZoomFourCatalog.effectsForFamily(DeviceFamily.zoomB1Four));
    registerAll(ZoomFourCatalog.effectsForFamily(DeviceFamily.zoomG1xFour));
    registerAll(ZoomFourCatalog.effectsForFamily(DeviceFamily.zoomG1Four));

    // Register Line 6 Bass Pod Pro effects
    registerAll(Line6BassPodProCatalog.builtInEffects);
  }

  /// Registers an individual built-in [EffectDefinition].
  static void register(EffectDefinition definition) {
    final familyMap = _catalogs.putIfAbsent(definition.deviceFamily, () => {});
    familyMap[definition.effectId.toLowerCase()] = definition;
  }

  /// Registers a collection of built-in [EffectDefinition]s.
  static void registerAll(Iterable<EffectDefinition> definitions) {
    for (final def in definitions) {
      register(def);
    }
  }

  /// Registers or updates a local custom `.ZD2` [EffectDefinition] in Tier 3.
  static void registerCustomEffect(
    EffectDefinition definition, {
    DeviceGeneration? generation,
    bool notify = true,
  }) {
    ensureInitialized();
    final canonical = _canonicalHexLower(definition.effectId);
    final normalizedId = canonical != null
        ? '0x${canonical.substring(2).toUpperCase()}'
        : definition.effectId.trim();
    final normalizedGen =
        generation == DeviceGeneration.unknown ? null : generation;

    final customDef = definition.copyWith(
      effectId: normalizedId,
      category: 'Custom',
      origin: EffectOrigin.custom,
      sourceModelLabel: 'Custom',
    );

    final record = RegisteredCustomEffect(
      definition: customDef,
      generation: normalizedGen,
    );

    final existingIdx = _customEffects.indexWhere((e) =>
        _canonicalHexLower(e.definition.effectId) ==
            _canonicalHexLower(normalizedId) &&
        e.definition.effectId.toLowerCase() == normalizedId.toLowerCase() &&
        e.generation == normalizedGen);

    if (existingIdx != -1) {
      _customEffects[existingIdx] = record;
    } else {
      _customEffects.add(record);
    }

    if (notify) {
      _notifyCatalogChanged();
    }
  }

  /// Replaces all registered custom `.ZD2` definitions at once and notifies listeners.
  static void setCustomEffects(Iterable<RegisteredCustomEffect> records) {
    ensureInitialized();
    _customEffects.clear();
    for (final record in records) {
      registerCustomEffect(
        record.definition,
        generation: record.generation,
        notify: false,
      );
    }
    _notifyCatalogChanged();
  }

  /// Removes registered custom `.ZD2` definition(s) matching [effectId]
  /// (and optional [generation] scope). Returns true if any entry was removed.
  static bool unregisterCustomEffect(
    String effectId, {
    DeviceGeneration? generation,
  }) {
    ensureInitialized();
    final targetCanonical = _canonicalHexLower(effectId);
    final targetLower = effectId.trim().toLowerCase();
    final before = _customEffects.length;

    _customEffects.removeWhere((entry) {
      final entryCanonical = _canonicalHexLower(entry.definition.effectId);
      final idMatches = (targetCanonical != null &&
              entryCanonical == targetCanonical) ||
          entry.definition.effectId.trim().toLowerCase() == targetLower;
      if (!idMatches) return false;
      if (generation != null && entry.generation != generation) return false;
      return true;
    });

    final removed = _customEffects.length != before;
    if (removed) {
      _notifyCatalogChanged();
    }
    return removed;
  }

  /// Clears all registered custom `.ZD2` definitions and notifies listeners.
  static void clearCustomEffects() {
    if (_customEffects.isEmpty) return;
    _customEffects.clear();
    _notifyCatalogChanged();
  }

  /// Returns an unmodifiable snapshot of all registered custom `.ZD2` effects.
  static List<RegisteredCustomEffect> getRegisteredCustomEffects() {
    ensureInitialized();
    return List.unmodifiable(_customEffects);
  }

  /// Returns compatible registered custom `.ZD2` [EffectDefinition]s for [family].
  static List<EffectDefinition> getCustomEffectsForFamily(DeviceFamily family) {
    ensureInitialized();
    if (!family.isZoom6E || _customEffects.isEmpty) return const [];

    // Prefer generation-specific matches before generation-agnostic entries when deduplicating.
    final byId = <String, EffectDefinition>{};
    for (final record in _customEffects) {
      if (record.generation == family.generation) {
        final key = _canonicalHexLower(record.definition.effectId) ??
            record.definition.effectId.toLowerCase();
        byId[key] = record.definition.copyWith(deviceFamily: family);
      }
    }
    for (final record in _customEffects) {
      if (record.generation == null ||
          record.generation == DeviceGeneration.unknown) {
        final key = _canonicalHexLower(record.definition.effectId) ??
            record.definition.effectId.toLowerCase();
        byId.putIfAbsent(
          key,
          () => record.definition.copyWith(deviceFamily: family),
        );
      }
    }
    return byId.values.toList(growable: false);
  }

  /// Count of compatible registered custom `.ZD2` effects for [family].
  static int customEffectCountForFamily(DeviceFamily family) =>
      getCustomEffectsForFamily(family).length;

  static EffectDefinition? _lookupCustomEffect(
    DeviceFamily family,
    String effectId,
  ) {
    if (!family.isZoom6E || _customEffects.isEmpty) return null;
    final targetCanonical = _canonicalHexLower(effectId);
    final targetLower = effectId.trim().toLowerCase();

    bool matchesId(RegisteredCustomEffect entry) {
      final entryCanonical = _canonicalHexLower(entry.definition.effectId);
      if (targetCanonical != null && entryCanonical != null) {
        return entryCanonical == targetCanonical;
      }
      return entry.definition.effectId.trim().toLowerCase() == targetLower;
    }

    // Pass 1: exact generation match
    for (final entry in _customEffects) {
      if (entry.generation == family.generation && matchesId(entry)) {
        return entry.definition.copyWith(deviceFamily: family);
      }
    }
    // Pass 2: generation-agnostic custom entry
    for (final entry in _customEffects) {
      if ((entry.generation == null ||
              entry.generation == DeviceGeneration.unknown) &&
          matchesId(entry)) {
        return entry.definition.copyWith(deviceFamily: family);
      }
    }
    // Pass 3: any Zoom custom entry with matching ID
    for (final entry in _customEffects) {
      if (matchesId(entry)) {
        return entry.definition.copyWith(deviceFamily: family);
      }
    }
    return null;
  }

  /// Returns true if [effectId] exists in [family]'s built-in stock catalog (Tier 1).
  static bool isStockEffect(DeviceFamily family, String effectId) {
    ensureInitialized();
    return _lookupInFamilyMap(_catalogs[family], effectId) != null;
  }

  /// Looks up [effectId] in same-generation sibling catalogs (Tier 2),
  /// returning a definition tagged with [EffectOrigin.crossModel] and the
  /// originating sibling's concise model label, or `null` if not found.
  static EffectDefinition? lookupCrossModelSibling(
    DeviceFamily family,
    String effectId,
  ) {
    ensureInitialized();
    if (family.isZoomMsPlus) {
      for (final sibling in _msPlusSiblingOrder) {
        if (sibling == family) continue;
        final found = _lookupInFamilyMap(_catalogs[sibling], effectId);
        if (found != null) {
          return found.copyWith(
            deviceFamily: family,
            origin: EffectOrigin.crossModel,
            sourceModelLabel: conciseModelLabel(sibling),
          );
        }
      }
    } else if (family.isZoomFour) {
      for (final sibling in _zoomFourSiblingOrder) {
        if (sibling == family) continue;
        final found = _lookupInFamilyMap(_catalogs[sibling], effectId);
        if (found != null) {
          return found.copyWith(
            deviceFamily: family,
            origin: EffectOrigin.crossModel,
            sourceModelLabel: conciseModelLabel(sibling),
          );
        }
      }
    }
    return null;
  }

  /// Sets the runtime overlay of cross-model effect IDs confirmed installed on
  /// a connected [family] pedal so they become selectable in the palette and
  /// effect picker with their [EffectOrigin.crossModel] badge.
  static void setInstalledCrossModelEffects(
    DeviceFamily family,
    Iterable<String> effectIds, {
    bool notify = true,
  }) {
    ensureInitialized();
    final nextSet = <String>{};
    for (final rawId in effectIds) {
      if (isStockEffect(family, rawId)) continue;
      final cross = lookupCrossModelSibling(family, rawId);
      if (cross != null) {
        final key = _canonicalHexLower(cross.effectId) ??
            cross.effectId.trim().toLowerCase();
        nextSet.add(key);
      }
    }

    final existing = _installedCrossModelIds[family];
    final changed = existing == null
        ? nextSet.isNotEmpty
        : !setEquals(existing, nextSet);

    if (nextSet.isEmpty) {
      _installedCrossModelIds.remove(family);
    } else {
      _installedCrossModelIds[family] = nextSet;
    }

    if (notify && changed) {
      _notifyCatalogChanged();
    }
  }

  /// Clears runtime installed cross-model effects for [family] (or all families
  /// when [family] is omitted), notifying listeners if any overlay was removed.
  static void clearInstalledCrossModelEffects([DeviceFamily? family]) {
    bool removed = false;
    if (family == null) {
      removed = _installedCrossModelIds.isNotEmpty;
      _installedCrossModelIds.clear();
    } else {
      removed = _installedCrossModelIds.remove(family) != null;
    }
    if (removed) {
      _notifyCatalogChanged();
    }
  }

  /// Returns runtime-discovered installed cross-model [EffectDefinition]s
  /// currently active for [family].
  static List<EffectDefinition> getInstalledCrossModelEffectsForFamily(
    DeviceFamily family,
  ) {
    ensureInitialized();
    final ids = _installedCrossModelIds[family];
    if (ids == null || ids.isEmpty) return const [];
    final results = <EffectDefinition>[];
    for (final id in ids) {
      final def = lookupCrossModelSibling(family, id);
      if (def != null) {
        results.add(def);
      }
    }
    return results;
  }

  /// Resolves an [EffectDefinition] by [family] and [effectId] using 4-tier lookup:
  /// 1. Active device built-in stock catalog ([EffectOrigin.stock])
  /// 2. Same-generation cross-model sibling catalogs ([EffectOrigin.crossModel])
  /// 3. Local custom `.ZD2` registry ([EffectOrigin.custom])
  /// 4. Extended `ZoomZdl7MasterCatalog` on Zoom Four ([EffectOrigin.crossModel])
  /// 5. Generic fallback definition ([EffectOrigin.unknown])
  static EffectDefinition getDefinition(DeviceFamily family, String effectId) {
    ensureInitialized();

    // Tier 1: Active device built-in stock catalog
    final stock = _lookupInFamilyMap(_catalogs[family], effectId);
    if (stock != null) {
      return stock;
    }

    // Tier 2: Same-generation cross-model sibling catalogs
    final crossModel = lookupCrossModelSibling(family, effectId);
    if (crossModel != null) {
      return crossModel;
    }

    // Tier 3: Local custom .ZD2 registry (beats param-less ZDL7 fallback on Zoom Four)
    final custom = _lookupCustomEffect(family, effectId);
    if (custom != null) {
      return custom;
    }

    // Tier 4: Extended ZDL7 master lookup for Zoom Four hardware
    if (family.isZoomFour) {
      final normalized = _canonicalHexLower(effectId) ?? effectId.trim().toLowerCase();
      final zdl7 = ZoomZdl7MasterCatalog.lookup(normalized, family);
      if (zdl7 != null) return zdl7;
    }

    // Fallback: Unknown / Bypass definition
    return createFallbackDefinition(family, effectId);
  }

  /// Alias for [getDefinition] emphasizing 4-tier provenance resolution.
  static EffectDefinition resolveDefinition(
    DeviceFamily family,
    String effectId,
  ) =>
      getDefinition(family, effectId);

  /// Creates a fallback [EffectDefinition] for unmapped DSP IDs.
  static EffectDefinition createFallbackDefinition(
    DeviceFamily family,
    String effectId,
  ) {
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
      origin: isBypass ? EffectOrigin.stock : EffectOrigin.unknown,
    );
  }

  /// Returns all built-in + runtime installed cross-model + compatible custom
  /// [EffectDefinition]s for a given [family].
  static List<EffectDefinition> getEffectsForFamily(DeviceFamily family) {
    ensureInitialized();
    final builtIn = _catalogs[family]?.values.toList() ?? const <EffectDefinition>[];
    final crossModel = getInstalledCrossModelEffectsForFamily(family);
    final custom = getCustomEffectsForFamily(family);
    if (crossModel.isEmpty && custom.isEmpty) {
      return builtIn;
    }

    final seenIds = <String>{
      for (final def in builtIn)
        _canonicalHexLower(def.effectId) ?? def.effectId.toLowerCase(),
    };
    final merged = List<EffectDefinition>.from(builtIn);
    for (final crossDef in crossModel) {
      final key = _canonicalHexLower(crossDef.effectId) ??
          crossDef.effectId.toLowerCase();
      if (seenIds.add(key)) {
        merged.add(crossDef);
      }
    }
    for (final customDef in custom) {
      final key = _canonicalHexLower(customDef.effectId) ??
          customDef.effectId.toLowerCase();
      if (seenIds.add(key)) {
        merged.add(customDef);
      }
    }
    return merged;
  }

  /// Convenience alias for [getEffectsForFamily].
  static List<EffectDefinition> getEffects(DeviceFamily family) =>
      getEffectsForFamily(family);

  /// Looks up a registered [EffectDefinition] by exact display [name] (case-insensitive)
  /// within [family].
  static EffectDefinition? getByName(DeviceFamily family, String name) {
    ensureInitialized();
    final target = name.trim().toLowerCase();
    for (final def in getEffectsForFamily(family)) {
      if (def.name.toLowerCase() == target) {
        return def;
      }
    }
    return null;
  }

  /// Returns all unique non-empty category names registered for a [family]
  /// in catalog/first-seen order (including `'Custom'` only when compatible
  /// custom effects exist).
  static List<String> getCategories(DeviceFamily family) {
    ensureInitialized();
    final effects = getEffectsForFamily(family);
    final categories = <String>{};
    for (final e in effects) {
      final cat = e.category.trim();
      if (cat.isNotEmpty) {
        categories.add(cat);
      }
    }
    return categories.toList(growable: false);
  }

  /// Clears registry state (primarily used in unit test isolation).
  @visibleForTesting
  static void reset() {
    _catalogs.clear();
    _customEffects.clear();
    _installedCrossModelIds.clear();
    _initialized = false;
    _notifyCatalogChanged();
  }
}

