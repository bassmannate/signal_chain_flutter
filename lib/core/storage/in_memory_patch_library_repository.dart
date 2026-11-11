import '../../models/device_family.dart';
import '../../models/patch.dart';
import 'patch_library_repository.dart';

/// Pure in-memory implementation of [PatchLibraryRepository] for testing and UI preview states.
class InMemoryPatchLibraryRepository extends PatchLibraryRepository {
  final Map<String, Patch> _patches = {};

  InMemoryPatchLibraryRepository({List<Patch>? initialPatches}) {
    if (initialPatches != null) {
      for (final p in initialPatches) {
        _patches[p.id] = p;
      }
    }
  }

  @override
  Future<List<Patch>> getAllPatches({
    DeviceFamily? deviceFilter,
    String? searchQuery,
    Set<String>? tagsFilter,
  }) async {
    return _patches.values.where((patch) {
      return PatchLibraryRepository.matchesFilter(
        patch,
        deviceFilter: deviceFilter,
        searchQuery: searchQuery,
        tagsFilter: tagsFilter,
      );
    }).toList();
  }

  @override
  Future<Patch?> getPatchById(String id) async {
    return _patches[id];
  }

  @override
  Future<void> savePatch(Patch patch) async {
    _patches[patch.id] = patch;
  }

  @override
  Future<void> deletePatch(String id) async {
    _patches.remove(id);
  }

  /// Clears all stored patches in memory.
  void clear() {
    _patches.clear();
  }

  /// Number of patches currently held in memory.
  int get count => _patches.length;
}

