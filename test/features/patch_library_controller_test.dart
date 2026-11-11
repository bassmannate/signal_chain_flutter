import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  const p1 = Patch(
    id: 'patch_1',
    name: 'Modern Slap',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    tags: ['slap', 'funk'],
    author: 'Marcus',
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'p0',
              name: 'Level',
              min: 0,
              max: 100,
              defaultValue: 50,
            ),
            currentValue: 80.0,
          ),
        ],
      ),
    ],
  );

  const p2 = Patch(
    id: 'patch_2',
    name: 'Vintage Rock SVT',
    deviceFamily: DeviceFamily.line6BassPodPro,
    tags: ['rock', 'svt'],
    author: 'Geddy',
    slots: [],
  );

  const p3 = Patch(
    id: 'patch_3',
    name: 'Chorus Delay Space',
    deviceFamily: DeviceFamily.zoomMs70cdrPlus,
    tags: ['ambient', 'space'],
    author: 'Justin',
    slots: [],
  );

  group('PatchLibraryController Unit Tests', () {
    late InMemoryPatchLibraryRepository repository;
    late PatchLibraryController controller;

    setUp(() async {
      repository = InMemoryPatchLibraryRepository(
        initialPatches: [p1, p2, p3],
      );
      controller = PatchLibraryController(repository: repository);
      await controller.refresh();
    });

    test('loads and displays all patches initially', () {
      expect(controller.patches.length, equals(3));
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
    });

    test('filters patches by DeviceFamily', () async {
      await controller.setDeviceFilter(DeviceFamily.zoomMs60bPlus);
      expect(controller.patches.length, equals(1));
      expect(controller.patches.first.id, equals('patch_1'));

      await controller.setDeviceFilter(DeviceFamily.line6BassPodPro);
      expect(controller.patches.length, equals(1));
      expect(controller.patches.first.id, equals('patch_2'));

      await controller.setDeviceFilter(null);
      expect(controller.patches.length, equals(3));
    });

    test('filters patches by search query', () async {
      await controller.setSearchQuery('SVT');
      expect(controller.patches.length, equals(1));
      expect(controller.patches.first.name, equals('Vintage Rock SVT'));

      await controller.setSearchQuery('Marcus');
      expect(controller.patches.length, equals(1));
      expect(controller.patches.first.author, equals('Marcus'));

      await controller.setSearchQuery('');
      expect(controller.patches.length, equals(3));
    });

    test('filters patches by tag matching', () async {
      await controller.toggleTag('funk');
      expect(controller.patches.length, equals(1));
      expect(controller.patches.first.id, equals('patch_1'));

      await controller.toggleTag('funk');
      expect(controller.patches.length, equals(3));
    });

    test('saves new patch and refreshes active list', () async {
      const newPatch = Patch(
        id: 'patch_4',
        name: 'Heavy Fuzz',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        tags: ['fuzz'],
      );

      await controller.savePatch(newPatch);

      expect(controller.patches.length, equals(4));
      expect(controller.patches.any((p) => p.id == 'patch_4'), isTrue);
    });

    test('deletes patch by id and updates list', () async {
      await controller.deletePatch('patch_2');

      expect(controller.patches.length, equals(2));
      expect(controller.patches.any((p) => p.id == 'patch_2'), isFalse);
    });

    test('exports and imports JSON presets', () async {
      final jsonString = await controller.exportPatchToJson(p1);
      expect(jsonString, contains('"name": "Modern Slap"'));

      const importedJson = '''
      {
        "id": "patch_imported",
        "name": "Imported Slap",
        "deviceFamily": "zoomMs60bPlus",
        "slots": []
      }
      ''';

      final imported = await controller.importPatchFromJson(importedJson);
      expect(imported.id, equals('patch_imported'));
      expect(imported.name, equals('Imported Slap'));
      expect(controller.patches.length, equals(4));
    });

    test('exports and imports raw SysEx bytes', () async {
      const protocol = ZoomMsPlusProtocol();
      final sysexBytes = controller.exportPatchSysEx(p1, protocol);
      expect(sysexBytes.length, greaterThan(10));

      final imported = await controller.importPatchSysEx(sysexBytes, protocol);
      expect(imported.name, equals('Modern Slap'));
    });
  });
}
