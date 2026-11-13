import 'dart:convert';
import 'dart:io';

import '../../models/setlist.dart';
import 'setlist_repository.dart';

/// Pure `dart:io` atomic JSON persistence for [Setlist] objects.
class FileSystemSetlistRepository extends SetlistRepository {
  final Directory storageDir;

  const FileSystemSetlistRepository({required this.storageDir});

  static String sanitizeFilename(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^\w\-]'), '_');
    return sanitized.isEmpty ? 'setlist_unnamed' : sanitized;
  }

  File _getSetlistFile(String id) {
    return File('${storageDir.path}/${sanitizeFilename(id)}.json');
  }

  @override
  Future<List<Setlist>> getAllSetlists() async {
    if (!await storageDir.exists()) {
      return const [];
    }

    final setlists = <Setlist>[];
    final entities = await storageDir.list(followLinks: false).toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final data = json.decode(content);
          if (data is Map<String, dynamic> &&
              data.containsKey('id') &&
              data.containsKey('name')) {
            setlists.add(Setlist.fromJson(data));
          }
        } catch (_) {
          // Gracefully ignore unreadable or corrupted setlist JSON files.
        }
      }
    }
    setlists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return setlists;
  }

  @override
  Future<Setlist?> getSetlistById(String id) async {
    if (!await storageDir.exists()) return null;
    final directFile = _getSetlistFile(id);
    if (await directFile.exists()) {
      try {
        final data = json.decode(await directFile.readAsString());
        if (data is Map<String, dynamic>) {
          final setlist = Setlist.fromJson(data);
          if (setlist.id == id) return setlist;
        }
      } catch (_) {}
    }

    final all = await getAllSetlists();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<void> saveSetlist(Setlist setlist) async {
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    final targetFile = _getSetlistFile(setlist.id);
    final tempFile = File(
      '${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(encoder.convert(setlist.toJson()), flush: true);

    try {
      await tempFile.rename(targetFile.path);
    } catch (_) {
      await tempFile.copy(targetFile.path);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<void> deleteSetlist(String id) async {
    if (!await storageDir.exists()) return;
    final directFile = _getSetlistFile(id);
    if (await directFile.exists()) {
      await directFile.delete();
      return;
    }
    final entities = await storageDir.list(followLinks: false).toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final data = json.decode(await entity.readAsString());
          if (data is Map<String, dynamic> && data['id'] == id) {
            await entity.delete();
            return;
          }
        } catch (_) {}
      }
    }
  }
}

