import 'package:flutter/foundation.dart';

import '../../models/device_family.dart';
import '../../models/parameter_descriptor.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../zd2/zd2_parser.dart';

/// Persisted local custom `.ZD2` effect entry.
@immutable
class CustomEffectEntry {
  final String effectId;
  final String name;
  final String? version;
  final String? description;
  final String? sourceFilename;
  final int groupByte;
  final String rawGroupName;
  final int targetMask;
  final String? generationTag;
  final int dspLoad;
  final List<ParameterDescriptor> parameters;
  final DateTime importedAt;

  const CustomEffectEntry({
    required this.effectId,
    required this.name,
    this.version,
    this.description,
    this.sourceFilename,
    this.groupByte = 0,
    this.rawGroupName = '',
    this.targetMask = 0,
    this.generationTag,
    this.dspLoad = 0,
    this.parameters = const [],
    required this.importedAt,
  });

  /// Normalizes a hex DSP ID to uppercase `'0xXXXXXXXX'` format.
  static String normalizeEffectId(String raw) {
    final clean = raw.trim();
    final lower = clean.toLowerCase();
    final hexPart = lower.startsWith('0x') ? lower.substring(2) : lower;
    if (hexPart.isNotEmpty && RegExp(r'^[0-9a-f]+$').hasMatch(hexPart)) {
      final parsed = int.tryParse(hexPart, radix: 16);
      if (parsed != null) {
        return '0x${parsed.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      }
    }
    return clean.toUpperCase();
  }

  /// Creates a [CustomEffectEntry] from a [ParsedZd2Effect].
  factory CustomEffectEntry.fromParsedZd2(
    ParsedZd2Effect parsed, {
    DateTime? importedAt,
  }) {
    return CustomEffectEntry(
      effectId: normalizeEffectId(parsed.effectId),
      name: parsed.name,
      version: parsed.version,
      description: parsed.description,
      sourceFilename: parsed.sourceFilename,
      groupByte: parsed.groupByte,
      rawGroupName: parsed.groupName,
      targetMask: parsed.targetMask,
      generationTag: parsed.generation?.name,
      dspLoad: parsed.dspLoad,
      parameters: parsed.parameters,
      importedAt: (importedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Resolves [generationTag] back into a [DeviceGeneration], or `null` if agnostic.
  DeviceGeneration? get generation {
    final tag = generationTag?.trim();
    if (tag == null || tag.isEmpty) return null;
    for (final g in DeviceGeneration.values) {
      if (g.name == tag && g != DeviceGeneration.unknown) {
        return g;
      }
    }
    return null;
  }

  /// Stable composite storage key combining normalized uppercase hex ID and generation scope.
  String get storageKey =>
      '${normalizeEffectId(effectId)}|${generationTag ?? 'any'}';

  /// Converts this entry into a catalog [EffectDefinition] for [family].
  EffectDefinition toEffectDefinition([
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
  ]) {
    return EffectDefinition(
      effectId: normalizeEffectId(effectId),
      name: name.trim().isNotEmpty ? name.trim() : 'Custom ($effectId)',
      category: 'Custom',
      deviceFamily: family,
      parameters: parameters,
      dspLoad: dspLoad > 0 ? dspLoad : null,
      origin: EffectOrigin.custom,
      sourceModelLabel: 'Custom',
      sourceFilename: sourceFilename,
      description: description,
      version: version,
    );
  }

  /// Converts this entry into a [RegisteredCustomEffect] for [EffectCatalogRegistry].
  RegisteredCustomEffect toRegistryRecord() {
    final defaultFamily = generation == DeviceGeneration.zoomFour
        ? DeviceFamily.zoomB1xFour
        : DeviceFamily.zoomMs60bPlus;
    return RegisteredCustomEffect(
      definition: toEffectDefinition(defaultFamily),
      generation: generation,
    );
  }

  CustomEffectEntry copyWith({
    String? effectId,
    String? name,
    String? version,
    String? description,
    String? sourceFilename,
    int? groupByte,
    String? rawGroupName,
    int? targetMask,
    String? generationTag,
    int? dspLoad,
    List<ParameterDescriptor>? parameters,
    DateTime? importedAt,
  }) {
    return CustomEffectEntry(
      effectId: effectId ?? this.effectId,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      sourceFilename: sourceFilename ?? this.sourceFilename,
      groupByte: groupByte ?? this.groupByte,
      rawGroupName: rawGroupName ?? this.rawGroupName,
      targetMask: targetMask ?? this.targetMask,
      generationTag: generationTag ?? this.generationTag,
      dspLoad: dspLoad ?? this.dspLoad,
      parameters: parameters ?? this.parameters,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'effectId': normalizeEffectId(effectId),
        'name': name,
        if (version != null) 'version': version,
        if (description != null) 'description': description,
        if (sourceFilename != null) 'sourceFilename': sourceFilename,
        'groupByte': groupByte,
        'rawGroupName': rawGroupName,
        'targetMask': targetMask,
        if (generationTag != null) 'generationTag': generationTag,
        'dspLoad': dspLoad,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        'importedAt': importedAt.toUtc().toIso8601String(),
      };

  factory CustomEffectEntry.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'] as List<dynamic>? ?? const [];
    final params = <ParameterDescriptor>[];
    for (final p in rawParams) {
      if (p is Map<String, dynamic>) {
        params.add(ParameterDescriptor.fromJson(p));
      } else if (p is Map) {
        params.add(ParameterDescriptor.fromJson(Map<String, dynamic>.from(p)));
      }
    }

    final rawImportedAt = json['importedAt'] as String?;
    final parsedDate =
        rawImportedAt != null ? DateTime.tryParse(rawImportedAt) : null;

    return CustomEffectEntry(
      effectId: normalizeEffectId(json['effectId'] as String? ?? '0x00000000'),
      name: json['name'] as String? ?? 'Custom Effect',
      version: json['version'] as String?,
      description: json['description'] as String?,
      sourceFilename: json['sourceFilename'] as String?,
      groupByte: (json['groupByte'] as num?)?.toInt() ?? 0,
      rawGroupName: json['rawGroupName'] as String? ?? '',
      targetMask: (json['targetMask'] as num?)?.toInt() ?? 0,
      generationTag: json['generationTag'] as String?,
      dspLoad: (json['dspLoad'] as num?)?.toInt() ?? 0,
      parameters: params,
      importedAt: (parsedDate ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          .toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomEffectEntry &&
          runtimeType == other.runtimeType &&
          normalizeEffectId(effectId) == normalizeEffectId(other.effectId) &&
          name == other.name &&
          version == other.version &&
          description == other.description &&
          sourceFilename == other.sourceFilename &&
          groupByte == other.groupByte &&
          rawGroupName == other.rawGroupName &&
          targetMask == other.targetMask &&
          generationTag == other.generationTag &&
          dspLoad == other.dspLoad &&
          importedAt == other.importedAt &&
          listEquals(parameters, other.parameters);

  @override
  int get hashCode => Object.hash(
        normalizeEffectId(effectId),
        name,
        version,
        description,
        sourceFilename,
        groupByte,
        rawGroupName,
        targetMask,
        generationTag,
        dspLoad,
        importedAt,
        Object.hashAll(parameters),
      );
}

/// Abstract persistence interface for user-imported local `.ZD2` custom effects.
abstract class CustomEffectRepository {
  const CustomEffectRepository();

  /// Loads all persisted [CustomEffectEntry] records.
  Future<List<CustomEffectEntry>> loadAll();

  /// Inserts or replaces a [CustomEffectEntry] (keyed by normalized uppercase hex
  /// `effectId` + optional generation scope).
  Future<void> upsert(CustomEffectEntry entry);

  /// Deletes persisted entry/entries matching [effectId] (optionally scoped by [generationTag]).
  Future<void> deleteById(String effectId, {String? generationTag});

  /// Removes all persisted custom effects.
  Future<void> clear();
}

/// Deterministic in-memory implementation of [CustomEffectRepository] for tests and fallback.
class InMemoryCustomEffectRepository extends CustomEffectRepository {
  final Map<String, CustomEffectEntry> _entries = {};

  InMemoryCustomEffectRepository({Iterable<CustomEffectEntry>? initialEntries}) {
    if (initialEntries != null) {
      for (final entry in initialEntries) {
        final normalized = entry.copyWith(
          effectId: CustomEffectEntry.normalizeEffectId(entry.effectId),
        );
        _entries[normalized.storageKey] = normalized;
      }
    }
  }

  @override
  Future<List<CustomEffectEntry>> loadAll() async {
    final list = _entries.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<void> upsert(CustomEffectEntry entry) async {
    final normalized = entry.copyWith(
      effectId: CustomEffectEntry.normalizeEffectId(entry.effectId),
    );
    _entries[normalized.storageKey] = normalized;
  }

  @override
  Future<void> deleteById(String effectId, {String? generationTag}) async {
    final targetId = CustomEffectEntry.normalizeEffectId(effectId);
    _entries.removeWhere((_, entry) {
      if (CustomEffectEntry.normalizeEffectId(entry.effectId) != targetId) {
        return false;
      }
      if (generationTag != null && entry.generationTag != generationTag) {
        return false;
      }
      return true;
    });
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}

