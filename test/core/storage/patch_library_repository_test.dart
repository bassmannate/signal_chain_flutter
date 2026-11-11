import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/storage/file_system_patch_library_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/line6_bass_pod_pro_protocol.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  final testPatch1 = Patch(
    id: 'patch_slap_funk',
    name: 'Slap Funk Machine',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    programNumber: 0,
    tags: const ['funk', 'slap', 'bright'],
    author: 'Flea',
    notes: 'Aggressive compression and punchy EQ',
    updatedAt: DateTime.utc(2026, 11, 10, 10, 0, 0),
    slots: const [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'sense_0',
              name: 'Sense',
              min: 0,
              max: 10,
              defaultValue: 6,
            ),
            currentValue: 7,
          ),
        ],
      ),
    ],
    metadata: const {'tempo': 115},
  );

  final testPatch2 = Patch(
    id: 'patch_vintage_dub',
    name: 'Vintage Dub Reggae',
    deviceFamily: DeviceFamily.line6BassPodPro,
    programNumber: 15,
    tags: const ['reggae', 'dub', 'warm'],
    author: 'Family Man',
    notes: 'Subby low end with B-15 style warmth',
    updatedAt: DateTime.utc(2026, 11, 10, 11, 0, 0),
    slots: const [
      EffectSlot(
        slotIndex: 0,
        effectId: 'line6_amp_11',
        effectName: 'Motor City (B-15)',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'bass',
              name: 'Bass',
              min: 0,
              max: 127,
              defaultValue: 64,
            ),
            currentValue: 110,
          ),
        ],
      ),
    ],
    metadata: const {'tempo': 72},
  );

  final testPatch3 = Patch(
    id: 'patch_modern_rock',
    name: 'Modern Rock Grit',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    programNumber: 1,
    tags: const ['rock', 'overdrive', 'modern'],
    author: 'Chris Wolstenholme',
    notes: 'High gain drive with scooped mids',
    slots: const [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x03000060',
        effectName: 'Dark OD',
        isEnabled: true,
        parameters: [],
      ),
    ],
  );

  group('InMemoryPatchLibraryRepository', () {
    late InMemoryPatchLibraryRepository repo;

    setUp(() {
      repo = InMemoryPatchLibraryRepository();
    });

    test('supports standard CRUD operations', () async {
      expect(await repo.getAllPatches(), isEmpty);
      expect(repo.count, equals(0));

      // Save
      await repo.savePatch(testPatch1);
      expect(repo.count, equals(1));

      // Get by ID
      final retrieved = await repo.getPatchById(testPatch1.id);
      expect(retrieved, equals(testPatch1));

      // Update
      final updated = testPatch1.copyWith(name: 'Updated Funk');
      await repo.savePatch(updated);
      expect(repo.count, equals(1));
      expect((await repo.getPatchById(testPatch1.id))?.name, equals('Updated Funk'));

      // Delete
      await repo.deletePatch(testPatch1.id);
      expect(repo.count, equals(0));
      expect(await repo.getPatchById(testPatch1.id), isNull);
    });

    test('filters patches by DeviceFamily', () async {
      await repo.savePatch(testPatch1);
      await repo.savePatch(testPatch2);
      await repo.savePatch(testPatch3);

      final zoomPatches = await repo.getAllPatches(deviceFilter: DeviceFamily.zoomMs60bPlus);
      expect(zoomPatches.length, equals(2));
      expect(zoomPatches.map((p) => p.id), containsAll(['patch_slap_funk', 'patch_modern_rock']));

      final line6Patches = await repo.getAllPatches(deviceFilter: DeviceFamily.line6BassPodPro);
      expect(line6Patches.length, equals(1));
      expect(line6Patches.first.id, equals('patch_vintage_dub'));
    });

    test('filters patches by text search query across name, author, notes, and effects', () async {
      await repo.savePatch(testPatch1);
      await repo.savePatch(testPatch2);
      await repo.savePatch(testPatch3);

      // Search by patch name
      final byName = await repo.getAllPatches(searchQuery: 'reggae');
      expect(byName.length, equals(1));
      expect(byName.first.id, equals('patch_vintage_dub'));

      // Search by author (case-insensitive)
      final byAuthor = await repo.getAllPatches(searchQuery: 'flea');
      expect(byAuthor.length, equals(1));
      expect(byAuthor.first.id, equals('patch_slap_funk'));

      // Search by notes
      final byNotes = await repo.getAllPatches(searchQuery: 'scooped mids');
      expect(byNotes.length, equals(1));
      expect(byNotes.first.id, equals('patch_modern_rock'));

      // Search by effect name inside chain
      final byEffect = await repo.getAllPatches(searchQuery: 'DYN Comp');
      expect(byEffect.length, equals(1));
      expect(byEffect.first.id, equals('patch_slap_funk'));
    });

    test('filters patches by multiple tags requiring all matches', () async {
      await repo.savePatch(testPatch1); // funk, slap, bright
      await repo.savePatch(testPatch2); // reggae, dub, warm
      await repo.savePatch(testPatch3); // rock, overdrive, modern

      final singleTag = await repo.getAllPatches(tagsFilter: {'funk'});
      expect(singleTag.length, equals(1));
      expect(singleTag.first.id, equals('patch_slap_funk'));

      final multiTagMatch = await repo.getAllPatches(tagsFilter: {'funk', 'slap'});
      expect(multiTagMatch.length, equals(1));

      final noMatch = await repo.getAllPatches(tagsFilter: {'funk', 'reggae'});
      expect(noMatch, isEmpty);
    });

    test('exports to formatted JSON and imports back identically', () async {
      final jsonStr = await repo.exportPatchToJsonString(testPatch1);
      expect(jsonStr, contains('"id": "patch_slap_funk"'));
      expect(jsonStr, contains('"deviceFamily": "zoomMs60bPlus"'));

      final imported = await repo.importPatchFromJsonString(jsonStr);
      expect(imported, equals(testPatch1));
    });

    test('exports and imports Zoom MS Plus raw SysEx', () {
      const zoomProtocol = ZoomMsPlusProtocol();
      final sysexBytes = repo.exportPatchSysEx(testPatch1, zoomProtocol);

      expect(sysexBytes, isNotEmpty);
      expect(sysexBytes.first, equals(0xF0));
      expect(sysexBytes.last, equals(0xF7));

      final imported = repo.importPatchSysEx(sysexBytes, zoomProtocol);
      expect(imported.name, equals(testPatch1.name));
      expect(imported.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));
      expect(imported.slots.isNotEmpty, isTrue);
    });

    test('exports and imports Line 6 Bass Pod Pro raw SysEx', () {
      const line6Protocol = Line6BassPodProProtocol();
      final sysexBytes = repo.exportPatchSysEx(testPatch2, line6Protocol);

      expect(sysexBytes, isNotEmpty);
      expect(sysexBytes.first, equals(0xF0));
      expect(sysexBytes.last, equals(0xF7));

      final imported = repo.importPatchSysEx(sysexBytes, line6Protocol);
      expect(imported.deviceFamily, equals(DeviceFamily.line6BassPodPro));
      expect(imported.slots.isNotEmpty, isTrue);
    });
  });

  group('FileSystemPatchLibraryRepository', () {
    late Directory tempDir;
    late FileSystemPatchLibraryRepository repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('signal_chain_test_');
      repo = FileSystemPatchLibraryRepository(storageDir: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates storage directory on demand and saves patch via atomic temp file', () async {
      final nonExistentDir = Directory('${tempDir.path}/sub_library');
      final customRepo = FileSystemPatchLibraryRepository(storageDir: nonExistentDir);

      expect(await nonExistentDir.exists(), isFalse);
      await customRepo.savePatch(testPatch1);
      expect(await nonExistentDir.exists(), isTrue);

      final patchFile = File('${nonExistentDir.path}/${testPatch1.id}.json');
      expect(await patchFile.exists(), isTrue);

      // Verify no residual temp files remain
      final files = await nonExistentDir.list().toList();
      final tempFiles = files.where((f) => f.path.contains('.tmp_'));
      expect(tempFiles, isEmpty);
    });

    test('reads saved patch back with complete integrity', () async {
      await repo.savePatch(testPatch1);
      final loaded = await repo.getPatchById(testPatch1.id);

      expect(loaded, isNotNull);
      expect(loaded, equals(testPatch1));
      expect(loaded!.tags, equals(['funk', 'slap', 'bright']));
      expect(loaded.author, equals('Flea'));
      expect(loaded.notes, equals('Aggressive compression and punchy EQ'));
      expect(loaded.updatedAt, equals(testPatch1.updatedAt));
    });

    test('supports full CRUD cycle on filesystem', () async {
      expect(await repo.getAllPatches(), isEmpty);

      // Create
      await repo.savePatch(testPatch1);
      expect((await repo.getAllPatches()).length, equals(1));

      // Read
      final read = await repo.getPatchById(testPatch1.id);
      expect(read?.name, equals('Slap Funk Machine'));

      // Update
      final updated = testPatch1.copyWith(name: 'Super Slap');
      await repo.savePatch(updated);
      expect((await repo.getAllPatches()).length, equals(1));
      expect((await repo.getPatchById(testPatch1.id))?.name, equals('Super Slap'));

      // Delete
      await repo.deletePatch(testPatch1.id);
      expect(await repo.getAllPatches(), isEmpty);
      expect(await repo.getPatchById(testPatch1.id), isNull);
    });

    test('supports filtering by DeviceFamily and Search Query from filesystem storage', () async {
      await repo.savePatch(testPatch1);
      await repo.savePatch(testPatch2);
      await repo.savePatch(testPatch3);

      final zoomPatches = await repo.getAllPatches(deviceFilter: DeviceFamily.zoomMs60bPlus);
      expect(zoomPatches.length, equals(2));

      final reggaeMatches = await repo.getAllPatches(searchQuery: 'Reggae');
      expect(reggaeMatches.length, equals(1));
      expect(reggaeMatches.first.id, equals('patch_vintage_dub'));

      final tagMatches = await repo.getAllPatches(tagsFilter: {'dub'});
      expect(tagMatches.length, equals(1));
      expect(tagMatches.first.id, equals('patch_vintage_dub'));
    });

    test('exports patch to JSON file and imports back from file', () async {
      final targetFile = File('${tempDir.path}/exports/exported_patch.json');
      await repo.exportPatchToFile(testPatch1, targetFile);

      expect(await targetFile.exists(), isTrue);
      final imported = await repo.importPatchFromFile(targetFile);
      expect(imported, equals(testPatch1));
    });

    test('exports patch to SysEx .syx file and imports back from .syx file', () async {
      const protocol = ZoomMsPlusProtocol();
      final targetSyxFile = File('${tempDir.path}/exports/slap.syx');

      await repo.exportPatchSysExToFile(testPatch1, protocol, targetSyxFile);
      expect(await targetSyxFile.exists(), isTrue);

      final imported = await repo.importPatchSysExFromFile(targetSyxFile, protocol);
      expect(imported.name, equals(testPatch1.name));
      expect(imported.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));
    });

    test('gracefully ignores non-patch JSON files in storage directory', () async {
      await repo.savePatch(testPatch1);

      // Create an extraneous unrelated JSON file
      final otherFile = File('${tempDir.path}/unrelated_config.json');
      await otherFile.writeAsString('{"version": "1.0", "theme": "dark"}');

      final patches = await repo.getAllPatches();
      expect(patches.length, equals(1));
      expect(patches.first.id, equals(testPatch1.id));
    });
  });
}
