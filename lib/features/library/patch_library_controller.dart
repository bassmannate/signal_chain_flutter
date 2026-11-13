import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/export/export_adapter_registry.dart';
import '../../core/export/export_file_writer.dart';
import '../../core/export/export_format.dart';
import '../../core/export/export_payload.dart';
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

  DeviceFamily? _deviceFilter;
  String _searchQuery = '';
  final Set<String> _selectedTags = {};

  List<Patch> _patches = [];
  bool _isLoading = false;
  String? _errorMessage;
  ExportFormat? _defaultExportFormat;

  PatchLibraryController({
    required this.repository,
    AppPreferencesRepository? preferencesRepository,
    ExportAdapterRegistry? exportRegistry,
    ExportFileWriter? exportFileWriter,
    DeviceFamily? initialDeviceFilter,
  })  : preferencesRepository = preferencesRepository ?? InMemoryPreferencesRepository(),
        exportRegistry = exportRegistry ?? ExportAdapterRegistry.standard(),
        exportFileWriter = exportFileWriter ?? const ExportFileWriter(),
        _deviceFilter = initialDeviceFilter;

  /// Currently filtered list of presets in the library.
  List<Patch> get patches => List.unmodifiable(_patches);

  /// Active device family filter, or null for all devices.
  DeviceFamily? get deviceFilter => _deviceFilter;

  /// Active text search query.
  String get searchQuery => _searchQuery;

  /// Currently selected tag filters.
  Set<String> get selectedTags => Set.unmodifiable(_selectedTags);

  /// True while reading or writing to storage.
  bool get isLoading => _isLoading;

  /// Most recent error message, or null.
  String? get errorMessage => _errorMessage;

  /// Persisted default export format, or null if not yet set.
  ExportFormat? get defaultExportFormat => _defaultExportFormat;

  /// Loads persisted user preferences (such as [defaultExportFormat]).
  Future<void> loadPreferences() async {
    _defaultExportFormat = await preferencesRepository.getDefaultExportFormat();
    notifyListeners();
  }

  /// Persists [format] as the default export format (or clears it if null).
  Future<void> setDefaultExportFormat(ExportFormat? format) async {
    _defaultExportFormat = format;
    await preferencesRepository.setDefaultExportFormat(format);
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
      _patches = await repository.getAllPatches(
        deviceFilter: _deviceFilter,
        searchQuery: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        tagsFilter: _selectedTags.isEmpty ? null : _selectedTags,
      );
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
