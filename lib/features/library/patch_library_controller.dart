import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/export/export_adapter.dart';
import '../../core/export/export_adapter_registry.dart';
import '../../core/export/export_file_writer.dart';
import '../../core/export/export_format.dart';
import '../../core/export/export_payload.dart';
import '../../core/import/import_batch_result.dart';
import '../../core/import/import_file_system.dart';
import '../../core/import/import_format.dart';
import '../../core/import/imported_patch_entry.dart';
import '../../core/import/patch_importer.dart';
import '../../core/storage/app_preferences_repository.dart';
import '../../core/storage/patch_library_repository.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../protocols/device_protocol.dart';
import '../editor/patch_editor_controller.dart';

/// Controller managing patch library persistence, search queries, device family
/// filtering, tag filtering, and JSON/SysEx import/export.
class PatchLibraryController extends ChangeNotifier {
  final PatchLibraryRepository repository;
  final AppPreferencesRepository preferencesRepository;
  final ExportAdapterRegistry exportRegistry;
  final ExportFileWriter exportFileWriter;
  final PatchImporter importer;
  final ImportFileSystem importFileSystem;

  DeviceFamily? _deviceFilter;
  String _searchQuery = '';
  final Set<String> _selectedTags = {};
  final Set<String> _availableTags = {};

  List<Patch> _patches = [];
  bool _isLoading = false;
  String? _errorMessage;
  ExportFormat? _defaultExportFormat;
  String? _lastExportDirectory;

  PatchLibraryController({
    required this.repository,
    AppPreferencesRepository? preferencesRepository,
    ExportAdapterRegistry? exportRegistry,
    ExportFileWriter? exportFileWriter,
    PatchImporter? importer,
    ImportFileSystem? importFileSystem,
    DeviceFamily? initialDeviceFilter,
  })  : preferencesRepository = preferencesRepository ?? InMemoryPreferencesRepository(),
        exportRegistry = exportRegistry ?? ExportAdapterRegistry.standard(),
        exportFileWriter = exportFileWriter ?? const ExportFileWriter(),
        importer = importer ?? PatchImporter.standard(),
        importFileSystem = importFileSystem ??
            ((const bool.fromEnvironment('FLUTTER_TEST') ||
                    Platform.environment['FLUTTER_TEST'] == 'true')
                ? InMemoryImportFileSystem()
                : const LocalImportFileSystem()),
        _deviceFilter = initialDeviceFilter;

  /// Currently filtered list of presets in the library.
  List<Patch> get patches => List.unmodifiable(_patches);

  /// Active device family filter, or null for all devices.
  DeviceFamily? get deviceFilter => _deviceFilter;

  /// Active text search query.
  String get searchQuery => _searchQuery;

  /// Currently selected tag filters.
  Set<String> get selectedTags => Set.unmodifiable(_selectedTags);

  /// All distinct tags present across the library repository, sorted alphabetically.
  List<String> get availableTags {
    final sorted = _availableTags.toList()..sort();
    return List.unmodifiable(sorted);
  }

  /// True while reading or writing to storage.
  bool get isLoading => _isLoading;

  /// Most recent error message, or null.
  String? get errorMessage => _errorMessage;

  /// Persisted default export format, or null if not yet set.
  ExportFormat? get defaultExportFormat => _defaultExportFormat;

  /// Persisted last-selected destination directory for exports/backups, or null.
  String? get lastExportDirectory => _lastExportDirectory;

  /// Loads persisted user preferences (such as [defaultExportFormat] and [lastExportDirectory]).
  Future<void> loadPreferences() async {
    _defaultExportFormat = await preferencesRepository.getDefaultExportFormat();
    _lastExportDirectory = await preferencesRepository.getLastExportDirectory();
    notifyListeners();
  }

  /// Persists [format] as the default export format (or clears it if null).
  Future<void> setDefaultExportFormat(ExportFormat? format) async {
    _defaultExportFormat = format;
    await preferencesRepository.setDefaultExportFormat(format);
    notifyListeners();
  }

  /// Persists [directoryPath] as the default export directory (or clears it if null).
  Future<void> setLastExportDirectory(String? directoryPath) async {
    final trimmed = directoryPath?.trim();
    _lastExportDirectory = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await preferencesRepository.setLastExportDirectory(_lastExportDirectory);
    notifyListeners();
  }

  /// Serializes a single [patch] using the adapter for [format].
  ExportPayload exportPatchWithFormat(Patch patch, ExportFormat format) {
    return exportRegistry.adapterFor(format).exportPatch(patch);
  }

  /// Serializes [patchesOverride] (or the current library patches) using [format].
  ExportPayload exportLibraryWithFormat(
    ExportFormat format, {
    List<Patch>? patchesOverride,
    String libraryName = 'signal_chain_library',
  }) {
    final targetPatches = patchesOverride ?? _patches;
    return exportRegistry.adapterFor(format).exportLibrary(
          targetPatches,
          libraryName: libraryName,
        );
  }

  /// Writes [payload] to disk via [exportFileWriter] and returns the output path.
  Future<String> saveExportToFile(
    ExportPayload payload, {
    Directory? targetDir,
    String? nameOverride,
  }) {
    return exportFileWriter.writePayload(
      payload,
      targetDir: targetDir,
      nameOverride: nameOverride,
    );
  }

  /// Refreshes the patch list from [repository] using current filters.
  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final hasFilters = _deviceFilter != null ||
          _searchQuery.trim().isNotEmpty ||
          _selectedTags.isNotEmpty;
      final allPatches = await repository.getAllPatches();
      _availableTags
        ..clear()
        ..addAll(allPatches.expand((p) => p.tags));

      if (!hasFilters) {
        _patches = allPatches;
      } else {
        _patches = await repository.getAllPatches(
          deviceFilter: _deviceFilter,
          searchQuery: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
          tagsFilter: _selectedTags.isEmpty ? null : _selectedTags,
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to load presets: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the active device family filter and reloads.
  Future<void> setDeviceFilter(DeviceFamily? family) async {
    if (_deviceFilter != family) {
      _deviceFilter = family;
      await refresh();
    }
  }

  /// Sets the text search query and reloads.
  Future<void> setSearchQuery(String query) async {
    if (_searchQuery != query) {
      _searchQuery = query;
      await refresh();
    }
  }

  /// Toggles a tag filter on or off.
  Future<void> toggleTag(String tag) async {
    if (_selectedTags.contains(tag)) {
      _selectedTags.remove(tag);
    } else {
      _selectedTags.add(tag);
    }
    await refresh();
  }

  /// Clears all filters (device, search query, and tags).
  Future<void> clearFilters() async {
    _deviceFilter = null;
    _searchQuery = '';
    _selectedTags.clear();
    await refresh();
  }

  /// Saves or updates [patch] in the repository and refreshes the list.
  Future<void> savePatch(Patch patch) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await repository.savePatch(patch);
      await refresh();
    } catch (e) {
      _errorMessage = 'Failed to save preset: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Saves a duplicate copy of [source] under [newName] with a collision-safe ID,
  /// leaving the original preset untouched.
  Future<Patch> duplicatePatch(
    Patch source, {
    required String newName,
  }) async {
    final resolvedName =
        newName.trim().isEmpty ? '${source.name} Copy' : newName.trim();
    final existing = await repository.getAllPatches();
    final usedIds = existing.map((p) => p.id).toSet();
    final now = DateTime.now();
    final stem = ExportAdapter.sanitizeFileStem(resolvedName, fallback: 'patch');
    var candidateId = 'copy_${stem}_${now.microsecondsSinceEpoch}';
    int suffix = 1;
    while (usedIds.contains(candidateId)) {
      candidateId = 'copy_${stem}_${now.microsecondsSinceEpoch}_$suffix';
      suffix++;
    }

    final copy = Patch(
      id: candidateId,
      name: resolvedName,
      deviceFamily: source.deviceFamily,
      programNumber: null,
      slots: source.slots,
      tags: source.tags,
      author: source.author,
      notes: source.notes,
      updatedAt: now,
      metadata: source.metadata,
    );

    await savePatch(copy);
    return copy;
  }

  /// Saves a hardware bank slot patch into the local library under a unique ID.
  Future<Patch> saveHardwareSlotToLibrary(
    Patch slotPatch, {
    int? slotIndex,
  }) async {
    final existing = await repository.getAllPatches();
    final usedIds = existing.map((p) => p.id).toSet();
    final now = DateTime.now();
    final resolvedSlot = slotIndex ?? slotPatch.programNumber;
    final stem = ExportAdapter.sanitizeFileStem(slotPatch.name, fallback: 'slot');
    final slotTag = resolvedSlot != null
        ? resolvedSlot.toString().padLeft(2, '0')
        : 'hw';
    var candidateId = 'hw_slot_${slotTag}_${stem}_${now.microsecondsSinceEpoch}';
    int suffix = 1;
    while (usedIds.contains(candidateId)) {
      candidateId =
          'hw_slot_${slotTag}_${stem}_${now.microsecondsSinceEpoch}_$suffix';
      suffix++;
    }

    final saved = slotPatch.copyWith(
      id: candidateId,
      programNumber: resolvedSlot,
      updatedAt: now,
    );

    await savePatch(saved);
    return saved;
  }

  /// Deletes a patch by [id] and refreshes the list.
  Future<void> deletePatch(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await repository.deletePatch(id);
      await refresh();
    } catch (e) {
      _errorMessage = 'Failed to delete preset: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Loads [patch] from the library directly into [editorController].
  void loadIntoEditor(Patch patch, PatchEditorController editorController) {
    editorController.loadPatch(patch);
  }

  /// Exports [patch] to a formatted JSON string.
  Future<String> exportPatchToJson(Patch patch) {
    return repository.exportPatchToJsonString(patch);
  }

  /// Imports a [Patch] from [jsonString], saves it to repository, and refreshes.
  Future<Patch> importPatchFromJson(String jsonString) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final patch = await repository.importPatchFromJsonString(jsonString);
      await repository.savePatch(patch);
      await refresh();
      return patch;
    } catch (e) {
      _errorMessage = 'Failed to import JSON preset: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Encodes [patch] to native SysEx bytes using [protocol].
  Uint8List exportPatchSysEx(Patch patch, DeviceProtocol protocol) {
    return repository.exportPatchSysEx(patch, protocol);
  }

  /// Imports a list of decoded [ImportedPatchEntry] items into [repository]
  /// with collision-safe IDs, then refreshes the library once.
  Future<List<Patch>> importEntries(List<ImportedPatchEntry> entries) async {
    if (entries.isEmpty) return const [];

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final existing = await repository.getAllPatches();
      final usedIds = existing.map((p) => p.id).toSet();
      final saved = <Patch>[];
      final now = DateTime.now();

      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        var patch = entry.patch;
        final resolvedId = _resolveUniqueImportId(
          patch: patch,
          format: entry.detectedFormat,
          usedIds: usedIds,
          timestampMicros: now.microsecondsSinceEpoch,
          index: i,
        );
        usedIds.add(resolvedId);

        patch = patch.copyWith(
          id: resolvedId,
          updatedAt: patch.updatedAt ?? now,
        );
        await repository.savePatch(patch);
        saved.add(patch);
      }

      await refresh();
      return saved;
    } catch (e) {
      _errorMessage = 'Failed to import presets: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Decodes a file via [importer] using [importFileSystem].
  Future<ImportBatchResult> previewImportFile(
    String filePath, {
    DeviceFamily? activeDeviceFamily,
  }) {
    return importer.importFile(
      filePath,
      fileSystem: importFileSystem,
      activeDeviceFamily: activeDeviceFamily,
    );
  }

  /// Scans and decodes a folder via [importer] using [importFileSystem].
  Future<ImportBatchResult> previewImportDirectory(
    String dirPath, {
    bool recursive = false,
    DeviceFamily? activeDeviceFamily,
  }) {
    return importer.importDirectory(
      dirPath,
      fileSystem: importFileSystem,
      recursive: recursive,
      activeDeviceFamily: activeDeviceFamily,
    );
  }

  static String _resolveUniqueImportId({
    required Patch patch,
    required ImportFormat format,
    required Set<String> usedIds,
    required int timestampMicros,
    required int index,
  }) {
    final isGenericProtocolId = patch.id.isEmpty ||
        patch.id == 'zoom_active_patch' ||
        patch.id == 'line6_active_patch' ||
        patch.id.startsWith('zoom_slot_') ||
        patch.id.startsWith('line6_slot_');

    // Preserve explicit Native JSON IDs when not colliding with existing entries.
    if (format == ImportFormat.signalChainJson &&
        !isGenericProtocolId &&
        !usedIds.contains(patch.id)) {
      return patch.id;
    }

    final stem = ExportAdapter.sanitizeFileStem(patch.name, fallback: 'patch');
    var candidate = 'import_${stem}_${timestampMicros}_$index';
    int suffix = 1;
    while (usedIds.contains(candidate)) {
      candidate = 'import_${stem}_${timestampMicros}_${index}_$suffix';
      suffix++;
    }
    return candidate;
  }

  /// Imports a patch from native [sysexBytes] using [protocol], saves it, and refreshes.
  Future<Patch> importPatchSysEx(
    Uint8List sysexBytes,
    DeviceProtocol protocol,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final patch = repository.importPatchSysEx(sysexBytes, protocol);
      await repository.savePatch(patch);
      await refresh();
      return patch;
    } catch (e) {
      _errorMessage = 'Failed to import SysEx preset: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}
