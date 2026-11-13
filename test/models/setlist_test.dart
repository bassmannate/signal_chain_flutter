import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/models/setlist.dart';

void main() {
  group('Setlist & SetlistEntry Models', () {
    test('SetlistEntry supports copyWith, equality, and JSON round-trip', () {
      const entry = SetlistEntry(
        id: 'entry_1',
        patchId: 'patch_slap',
        songTitle: 'Higher Ground',
        performanceNotes: 'Engage envelope filter on verse',
        tempoOverride: 118,
      );

      final jsonMap = entry.toJson();
      final decoded = SetlistEntry.fromJson(jsonMap);
      expect(decoded, equals(entry));
      expect(decoded.hashCode, equals(entry.hashCode));

      final updated = entry.copyWith(
        songTitle: 'Superstition',
        clearTempoOverride: true,
      );
      expect(updated.songTitle, equals('Superstition'));
      expect(updated.tempoOverride, isNull);
      expect(updated.patchId, equals('patch_slap'));
    });

    test('Setlist supports immutable entries and JSON round-trip', () {
      final now = DateTime.utc(2026, 11, 13, 8, 0);
      final setlist = Setlist(
        id: 'set_1',
        name: 'Friday Night Gig',
        notes: 'Club set - 45 min',
        updatedAt: now,
        entries: const [
          SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Opener'),
          SetlistEntry(id: 'e2', patchId: 'p2', tempoOverride: 132),
        ],
      );

      final rawJson = jsonEncode(setlist.toJson());
      final decoded = Setlist.fromJson(
        jsonDecode(rawJson) as Map<String, dynamic>,
      );

      expect(decoded, equals(setlist));
      expect(decoded.entries.length, equals(2));
      expect(decoded.entries[1].tempoOverride, equals(132));
    });
  });
}

