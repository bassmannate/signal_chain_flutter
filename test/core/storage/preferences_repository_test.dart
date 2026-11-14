import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/file_system_preferences_repository.dart';

void main() {
  group('InMemoryPreferencesRepository', () {
    test('stores and clears default export format', () async {
      final repo = InMemoryPreferencesRepository();
      expect(await repo.getDefaultExportFormat(), isNull);

      await repo.setDefaultExportFormat(ExportFormat.symbiosisZptc);
      expect(await repo.getDefaultExportFormat(), equals(ExportFormat.symbiosisZptc));

      await repo.setDefaultExportFormat(null);
      expect(await repo.getDefaultExportFormat(), isNull);
    });

    test('stores and clears last export directory', () async {
      final repo = InMemoryPreferencesRepository();
      expect(await repo.getLastExportDirectory(), isNull);

      await repo.setLastExportDirectory('/custom/exports');
      expect(await repo.getLastExportDirectory(), equals('/custom/exports'));

      await repo.setLastExportDirectory(null);
      expect(await repo.getLastExportDirectory(), isNull);
    });
  });

  group('FileSystemPreferencesRepository', () {
    test('persists default export format across repository instances', () async {
      final tempDir = await Directory.systemTemp.createTemp('signal_chain_prefs_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final prefsFile = File('${tempDir.path}${Platform.pathSeparator}preferences.json');
      final repo1 = FileSystemPreferencesRepository(preferencesFile: prefsFile);
      expect(await repo1.getDefaultExportFormat(), isNull);

      await repo1.setDefaultExportFormat(ExportFormat.zoomMultistompStudio);
      expect(await prefsFile.exists(), isTrue);

      final repo2 = FileSystemPreferencesRepository(preferencesFile: prefsFile);
      expect(await repo2.getDefaultExportFormat(), equals(ExportFormat.zoomMultistompStudio));

      await repo2.setDefaultExportFormat(null);
      expect(await repo1.getDefaultExportFormat(), isNull);
    });

    test('handles corrupted JSON gracefully', () async {
      final tempDir = await Directory.systemTemp.createTemp('signal_chain_prefs_corrupt_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final prefsFile = File('${tempDir.path}${Platform.pathSeparator}preferences.json');
      await prefsFile.writeAsString('{not valid json');

      final repo = FileSystemPreferencesRepository(preferencesFile: prefsFile);
      expect(await repo.getDefaultExportFormat(), isNull);
    });

    test('persists last export directory across repository instances', () async {
      final tempDir = await Directory.systemTemp.createTemp('signal_chain_prefs_dir_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final prefsFile = File('${tempDir.path}${Platform.pathSeparator}preferences.json');
      final repo1 = FileSystemPreferencesRepository(preferencesFile: prefsFile);
      expect(await repo1.getLastExportDirectory(), isNull);

      await repo1.setLastExportDirectory('/home/user/pedal_backups');
      final repo2 = FileSystemPreferencesRepository(preferencesFile: prefsFile);
      expect(
        await repo2.getLastExportDirectory(),
        equals('/home/user/pedal_backups'),
      );

      await repo2.setLastExportDirectory(null);
      final repo3 = FileSystemPreferencesRepository(preferencesFile: prefsFile);
      expect(await repo3.getLastExportDirectory(), isNull);
    });
  });
}

