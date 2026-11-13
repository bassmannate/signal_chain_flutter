import '../../models/setlist.dart';

/// Abstract contract for persisting ordered live performance [Setlist]s.
abstract class SetlistRepository {
  const SetlistRepository();

  Future<List<Setlist>> getAllSetlists();
  Future<Setlist?> getSetlistById(String id);
  Future<void> saveSetlist(Setlist setlist);
  Future<void> deleteSetlist(String id);
}

/// Deterministic in-memory [SetlistRepository] for unit and widget tests.
class InMemorySetlistRepository extends SetlistRepository {
  final Map<String, Setlist> _store = {};

  InMemorySetlistRepository({List<Setlist> initialSetlists = const []}) {
    for (final s in initialSetlists) {
      _store[s.id] = s;
    }
  }

  @override
  Future<List<Setlist>> getAllSetlists() async {
    return List.unmodifiable(_store.values);
  }

  @override
  Future<Setlist?> getSetlistById(String id) async => _store[id];

  @override
  Future<void> saveSetlist(Setlist setlist) async {
    _store[setlist.id] = setlist;
  }

  @override
  Future<void> deleteSetlist(String id) async {
    _store.remove(id);
  }
}

