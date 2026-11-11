import 'dart:convert';
import 'dart:typed_data';

import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../protocols/device_protocol.dart';
import '../midi/midi_message.dart';

/// Abstract contract for local patch library storage, indexing, and serialization.
abstract class PatchLibraryRepository {
  const PatchLibraryRepository();

  /// Retrieves all patches matching optional filters:
  /// - [deviceFilter]: restricts to a specific [DeviceFamily].
  /// - [searchQuery]: case-insensitive substring match on name, notes, author, or effect names.
  /// - [tagsFilter]: matches patches that contain all specified tags.
  Future<List<Patch>> getAllPatches({
    DeviceFamily? deviceFilter,
    String? searchQuery,
    Set<String>? tagsFilter,
  });

  /// Retrieves a specific [Patch] by unique [id], or null if not found.
  Future<Patch?> getPatchById(String id);

  /// Saves or updates a [Patch] in the repository.
  Future<void> savePatch(Patch patch);

  /// Deletes a patch by [id].
  Future<void> deletePatch(String id);

  /// Exports a [Patch] into a formatted JSON string.
  Future<String> exportPatchToJsonString(Patch patch) async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(patch.toJson());
  }

  /// Imports a [Patch] from a JSON string.
  Future<Patch> importPatchFromJsonString(String jsonString) async {
    final decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON map for patch definition');
    }
    return Patch.fromJson(decoded);
  }

  /// Encodes a [Patch] into device-native raw SysEx bytes using the given [protocol].
  Uint8List exportPatchSysEx(Patch patch, DeviceProtocol protocol) {
    return protocol.encodePatch(patch).data;
  }

  /// Decodes raw SysEx bytes into a [Patch] using the given [protocol].
  Patch importPatchSysEx(Uint8List sysexBytes, DeviceProtocol protocol) {
    return protocol.decodePatch(
      MidiMessage(sysexBytes, timestamp: DateTime.now()),
    );
  }

  /// Helper filter to evaluate whether a [patch] matches the given search criteria.
  static bool matchesFilter(
    Patch patch, {
    DeviceFamily? deviceFilter,
    String? searchQuery,
    Set<String>? tagsFilter,
  }) {
    if (deviceFilter != null && patch.deviceFamily != deviceFilter) {
      return false;
    }

    if (tagsFilter != null && tagsFilter.isNotEmpty) {
      final patchTagsLower = patch.tags.map((t) => t.toLowerCase()).toSet();
      for (final reqTag in tagsFilter) {
        if (!patchTagsLower.contains(reqTag.toLowerCase())) {
          return false;
        }
      }
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      final nameMatches = patch.name.toLowerCase().contains(q);
      final authorMatches = (patch.author ?? '').toLowerCase().contains(q);
      final notesMatches = (patch.notes ?? '').toLowerCase().contains(q);
      final effectMatches = patch.slots.any(
        (s) =>
            s.effectName.toLowerCase().contains(q) ||
            s.effectId.toLowerCase().contains(q),
      );

      if (!nameMatches && !authorMatches && !notesMatches && !effectMatches) {
        return false;
      }
    }

    return true;
  }
}

