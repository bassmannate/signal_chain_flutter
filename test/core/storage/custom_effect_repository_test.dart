import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/storage/custom_effect_repository.dart';
import 'package:signal_chain_flutter/core/storage/file_system_custom_effect_repository.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';

void main() {
  group('FileSystemCustomEffectRepository', () {
    late Directory tempDir;
    late FileSystemCustomEffectRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('custom_fx_repo_test_');
      repo = FileSystemCustomEffectRepository.inDirectory(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    CustomEffectEntry sampleEntry({
      String effectId = '0x04000999',
      String name = 'MY NAM',
      String? version = '1.00',
      String? generationTag = 'zoomMsPlus',
    }) {
      return CustomEffectEntry(
        effectId: effectId,
        name: name,
        version: version,
        description: 'Custom neural amp block',
        sourceFilename: 'MY_NAM.ZD2',
        groupByte: 0x04,
        rawGroupName: 'PREAMP',
        targetMask: 0x00080000,
        generationTag: generationTag,
        dspLoad: 22,
        parameters: const [
          ParameterDescriptor(
            id: 'gain_0',
            name: 'Gain',
            min: 0,
            max: 100,
            defaultValue: 55,
          ),
          ParameterDescriptor(
            id: 'mode_1',
            name: 'Mode',
            min: 0,
            max: 1,
            defaultValue: 0,
            labels: ['LO', 'HI'],
            valueLabels: ['LO', 'HI'],
          ),
        ],
        importedAt: DateTime.utc(2026, 11, 22, 12, 30, 0),
      );
    }

    test('performs atomic write/reload round-trip preserving all fields and parameters', () async {
      expect(await repo.loadAll(), isEmpty);

      final entry = sampleEntry(effectId: '04000999'); // unprefixed lowercase input
      await repo.upsert(entry);

      expect(await repo.storageFile.exists(), isTrue);

      // Reload from a fresh repository instance pointing at the same file
      final reloadedRepo = FileSystemCustomEffectRepository(storageFile: repo.storageFile);
      final loaded = await reloadedRepo.loadAll();

      expect(loaded.length, equals(1));
      final restored = loaded.first;
      expect(restored.effectId, equals('0x04000999'));
      expect(restored.name, equals('MY NAM'));
      expect(restored.version, equals('1.00'));
      expect(restored.description, equals('Custom neural amp block'));
      expect(restored.sourceFilename, equals('MY_NAM.ZD2'));
      expect(restored.groupByte, equals(0x04));
      expect(restored.rawGroupName, equals('PREAMP'));
      expect(restored.targetMask, equals(0x00080000));
      expect(restored.generation, equals(DeviceGeneration.zoomMsPlus));
      expect(restored.dspLoad, equals(22));
      expect(restored.importedAt, equals(DateTime.utc(2026, 11, 22, 12, 30, 0)));
      expect(restored.parameters.length, equals(2));
      expect(restored.parameters[0].name, equals('Gain'));
      expect(restored.parameters[0].defaultValue, equals(55));
      expect(restored.parameters[1].labels, equals(['LO', 'HI']));
    });

    test('upsert overwrites existing entry with same ID and generation scope without duplication', () async {
      await repo.upsert(sampleEntry(name: 'NAM v1', version: '1.00'));
      await repo.upsert(sampleEntry(name: 'NAM v2', version: '2.00'));

      final loaded = await repo.loadAll();
      expect(loaded.length, equals(1));
      expect(loaded.first.name, equals('NAM v2'));
      expect(loaded.first.version, equals('2.00'));
    });

    test('supports deleteById and clear', () async {
      await repo.upsert(sampleEntry(effectId: '0x04000991', name: 'Alpha'));
      await repo.upsert(sampleEntry(effectId: '0x04000992', name: 'Beta'));

      expect((await repo.loadAll()).length, equals(2));

      await repo.deleteById('0x04000991');
      final afterDelete = await repo.loadAll();
      expect(afterDelete.length, equals(1));
      expect(afterDelete.first.effectId, equals('0x04000992'));

      await repo.clear();
      expect(await repo.loadAll(), isEmpty);
    });

    test('recovers gracefully from corrupted or truncated JSON file', () async {
      await repo.storageFile.parent.create(recursive: true);
      await repo.storageFile.writeAsString('{broken json [');

      expect(await repo.loadAll(), isEmpty);

      // Subsequent upsert overwrites the corrupt file cleanly
      await repo.upsert(sampleEntry(name: 'Recovered FX'));
      final loaded = await repo.loadAll();
      expect(loaded.length, equals(1));
      expect(loaded.first.name, equals('Recovered FX'));
    });
  });

  group('InMemoryCustomEffectRepository', () {
    test('supports loadAll, upsert overwrite, deleteById, and clear', () async {
      final repo = InMemoryCustomEffectRepository();
      final entry = CustomEffectEntry(
        effectId: '0x01000099',
        name: 'Mem FX',
        importedAt: DateTime.utc(2026, 1, 1),
      );
      await repo.upsert(entry);
      expect((await repo.loadAll()).length, equals(1));

      await repo.upsert(entry.copyWith(name: 'Mem FX Updated'));
      final updated = await repo.loadAll();
      expect(updated.length, equals(1));
      expect(updated.first.name, equals('Mem FX Updated'));

      await repo.deleteById('01000099');
      expect(await repo.loadAll(), isEmpty);
    });
  });
}

