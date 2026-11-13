import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/storage/file_system_setlist_repository.dart';
import 'package:signal_chain_flutter/core/storage/setlist_repository.dart';
import 'package:signal_chain_flutter/models/setlist.dart';

void main() {
  group('SetlistRepository Implementations', () {
    const sampleSetlist = Setlist(
      id: 'set_gig_1',
      name: 'Saturday Set',
      notes: 'Main stage',
      entries: [
        SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Song 1'),
        SetlistEntry(id: 'e2', patchId: 'p2', tempoOverride: 128),
      ],
    );

    test('InMemorySetlistRepository supports CRUD', () async {
      final repo = InMemorySetlistRepository();
      expect(await repo.getAllSetlists(), isEmpty);

      await repo.saveSetlist(sampleSetlist);
      final loaded = await repo.getSetlistById('set_gig_1');
      expect(loaded, equals(sampleSetlist));
      expect((await repo.getAllSetlists()).length, equals(1));

      await repo.deleteSetlist('set_gig_1');
      expect(await repo.getSetlistById('set_gig_1'), isNull);
    });

    test('FileSystemSetlistRepository persists atomically and ignores corrupt files', () async {
      final tempDir = await Directory.systemTemp.createTemp('signal_chain_setlist_test_');
      try {
        final repo = FileSystemSetlistRepository(storageDir: tempDir);
        await repo.saveSetlist(sampleSetlist);

        // Corrupt JSON file should be safely ignored
        await File('${tempDir.path}/corrupt.json').writeAsString('{bad json');

        final all = await repo.getAllSetlists();
        expect(all.length, equals(1));
        expect(all.first.name, equals('Saturday Set'));
        expect(all.first.entries.length, equals(2));

        final fetched = await repo.getSetlistById('set_gig_1');
        expect(fetched, equals(sampleSetlist));

        await repo.deleteSetlist('set_gig_1');
        expect(await repo.getSetlistById('set_gig_1'), isNull);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}

