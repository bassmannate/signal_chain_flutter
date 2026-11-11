import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../protocols/device_protocol.dart';
import 'patch_library_repository.dart';

/// Pure `dart:io` file-system implementation of [PatchLibraryRepository].
///
/// Stores user presets as structured `.json` documents within a designated [storageDir],
/// providing atomic write safety (write-to-temp-then-rename) to prevent corruption during
/// unexpected process interruptions, alongside raw SysEx (`.syx` / `.ptcf`) file utilities.
class FileSystemPatchLibraryRepository extends PatchLibraryRepository {
  final Directory storageDir;

  const FileSystemPatchLibraryRepository({
    required this.storageDir,
  });

  /// Sanitizes a patch ID for safe file naming on POSIX and Windows filesystems.
  static String sanitizeFilename(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^\w\-]'), '_');
    return sanitized.isEmpty ? 'patch_unnamed' : sanitized;
  }

  File _getPatchFile(String id) {
    final filename = '${sanitizeFilename(id)}.json';
    return File('${storageDir.path}/$filename');
  }

  @override
  Future<List<Patch>> getAllPatches({
    DeviceFamily? deviceFilter,
    String? searchQuery,
    Set<String>? tagsFilter,
  }) async {
    if (!await storageDir.exists()) {
      return const [];
    }

    final patches = <Patch>[];
    final entities = await storageDir.list(followLinks: false).toList();

    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final data = json.decode(content);
          if (data is Map<String, dynamic> && data.containsKey('id') && data.containsKey('name')) {
            final patch = Patch.fromJson(data);
            if (PatchLibraryRepository.matchesFilter(
              patch,
              deviceFilter: deviceFilter,
              searchQuery: searchQuery,
              tagsFilter: tagsFilter,
            )) {
              patches.add(patch);
            }
          }
        } catch (_) {
          // Gracefully ignore unreadable or non-patch JSON files
        }
      }
    }

    return patches;
  }

  @override
  Future<Patch?> getPatchById(String id) async {
    if (!await storageDir.exists()) {
      return null;
    }

    // 1. Direct file check based on sanitized id
    final directFile = _getPatchFile(id);
    if (await directFile.exists()) {
      try {
        final content = await directFile.readAsString();
        final data = json.decode(content);
        if (data is Map<String, dynamic>) {
          final patch = Patch.fromJson(data);
          if (patch.id == id) return patch;
        }
      } catch (_) {
        // Fall back to scanning if file was corrupted or mismatched
      }
    }

    // 2. Scan all files in directory if direct lookup mismatched
    final all = await getAllPatches();
    for (final patch in all) {
      if (patch.id == id) return patch;
    }

    return null;
  }

  @override
  Future<void> savePatch(Patch patch) async {
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }

    final targetFile = _getPatchFile(patch.id);
    final tempFile = File(
      '${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}',
    );

    final jsonString = await exportPatchToJsonString(patch);

    // Atomic write pattern: write to temp file, flush to disk, then rename
    await tempFile.writeAsString(jsonString, flush: true);

    try {
      await tempFile.rename(targetFile.path);
    } catch (_) {
      // Fallback for cross-device link limits or OS-specific rename constraints
      await tempFile.copy(targetFile.path);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<void> deletePatch(String id) async {
    if (!await storageDir.exists()) return;

    final targetFile = _getPatchFile(id);
    if (await targetFile.exists()) {
      await targetFile.delete();
      return;
    }

    // If filename differs from sanitized ID, scan and delete matching file
    final entities = await storageDir.list(followLinks: false).toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final data = json.decode(content);
          if (data is Map<String, dynamic> && data['id'] == id) {
            await entity.delete();
            return;
          }
        } catch (_) {}
      }
    }
  }

  /// Exports a patch to a JSON file on disk.
  Future<File> exportPatchToFile(Patch patch, File targetFile) async {
    final parent = targetFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final jsonStr = await exportPatchToJsonString(patch);
    return targetFile.writeAsString(jsonStr, flush: true);
  }

  /// Imports a patch from a JSON file on disk.
  Future<Patch> importPatchFromFile(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Patch file does not exist', file.path);
    }
    final content = await file.readAsString();
    return importPatchFromJsonString(content);
  }

  /// Exports a patch as raw SysEx binary bytes (`.syx` or `.ptcf`) into a target file.
  Future<File> exportPatchSysExToFile(
    Patch patch,
    DeviceProtocol protocol,
    File targetFile,
  ) async {
    final parent = targetFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final bytes = exportPatchSysEx(patch, protocol);
    return targetFile.writeAsBytes(bytes, flush: true);
  }

  /// Imports a patch from raw SysEx binary bytes (`.syx` or `.ptcf`) read from a file.
  Future<Patch> importPatchSysExFromFile(
    File file,
    DeviceProtocol protocol,
  ) async {
    if (!await file.exists()) {
      throw FileSystemException('SysEx file does not exist', file.path);
    }
    final bytes = await file.readAsBytes();
    return importPatchSysEx(Uint8List.fromList(bytes), protocol);
  }
}

