import 'dart:convert';
import 'dart:io';

import 'custom_effect_repository.dart';

/// Pure `dart:io` atomic JSON persistence for user-imported `.ZD2` custom effects.
class FileSystemCustomEffectRepository extends CustomEffectRepository {
  final File storageFile;

  const FileSystemCustomEffectRepository({required this.storageFile});

  /// Convenience factory storing `custom_effects.json` inside [storageDir].
  factory FileSystemCustomEffectRepository.inDirectory(Directory storageDir) {
    return FileSystemCustomEffectRepository(
      storageFile: File('${storageDir.path}/custom_effects.json'),
    );
  }

  Future<List<CustomEffectEntry>> _readEntries() async {
    if (!await storageFile.exists()) {
      return [];
    }
    try {
      final raw = await storageFile.readAsString();
      final decoded = json.decode(raw);
      final List<dynamic> items;
      if (decoded is Map<String, dynamic> && decoded['effects'] is List) {
        items = decoded['effects'] as List<dynamic>;
      } else if (decoded is List) {
        items = decoded;
      } else {
        return [];
      }

      final entries = <CustomEffectEntry>[];
      for (final item in items) {
        try {
          if (item is Map<String, dynamic>) {
            entries.add(CustomEffectEntry.fromJson(item));
          } else if (item is Map) {
            entries.add(
              CustomEffectEntry.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        } catch (_) {
          // Skip individual malformed entries while preserving valid ones.
        }
      }
      entries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return entries;
    } catch (_) {
      // Gracefully recover from corrupted or truncated JSON.
      return [];
    }
  }

  Future<void> _writeEntries(List<CustomEffectEntry> entries) async {
    final parent = storageFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final payload = <String, dynamic>{
      'version': 1,
      'effects': entries.map((e) => e.toJson()).toList(),
    };

    final tempFile = File(
      '${storageFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(encoder.convert(payload), flush: true);

    try {
      await tempFile.rename(storageFile.path);
    } catch (_) {
      await tempFile.copy(storageFile.path);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<List<CustomEffectEntry>> loadAll() => _readEntries();

  @override
  Future<void> upsert(CustomEffectEntry entry) async {
    final normalized = entry.copyWith(
      effectId: CustomEffectEntry.normalizeEffectId(entry.effectId),
    );
    final entries = await _readEntries();
    final idx = entries.indexWhere((e) => e.storageKey == normalized.storageKey);
    if (idx != -1) {
      entries[idx] = normalized;
    } else {
      entries.add(normalized);
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    await _writeEntries(entries);
  }

  @override
  Future<void> deleteById(String effectId, {String? generationTag}) async {
    final targetId = CustomEffectEntry.normalizeEffectId(effectId);
    final entries = await _readEntries();
    final before = entries.length;
    entries.removeWhere((entry) {
      if (CustomEffectEntry.normalizeEffectId(entry.effectId) != targetId) {
        return false;
      }
      if (generationTag != null && entry.generationTag != generationTag) {
        return false;
      }
      return true;
    });
    if (entries.length != before) {
      await _writeEntries(entries);
    }
  }

  @override
  Future<void> clear() async {
    await _writeEntries(const []);
  }
}

