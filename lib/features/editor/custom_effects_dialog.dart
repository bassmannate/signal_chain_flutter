import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/import/import_file_system.dart';
import '../../core/storage/custom_effect_repository.dart';
import '../../core/zd2/zd2_parser.dart';
import '../../models/device_family.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../../protocols/zoom_file_transfer_service.dart';
import '../theme/horizontal_mouse_scroll_view.dart';
import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';

class _Zd2ImportOutcome {
  final String filename;
  final bool success;
  final String message;

  const _Zd2ImportOutcome({
    required this.filename,
    required this.success,
    required this.message,
  });
}

/// Dialog for managing and importing local Zoom `.ZD2` (`ZDLF`) custom effects.
///
/// Uses the zero-dependency [ImportFileSystem] browser so users can select one
/// or multiple `.zd2`/`.ZD2` files, inspect registered custom effects, and remove
/// them with undo-safe restoration.
class CustomEffectsDialog extends StatefulWidget {
  final PatchEditorController editorController;
  final CustomEffectRepository? repository;
  final ImportFileSystem? fileSystemOverride;
  final String? initialDirectoryOverride;

  const CustomEffectsDialog({
    super.key,
    required this.editorController,
    this.repository,
    this.fileSystemOverride,
    this.initialDirectoryOverride,
  });

  /// Opens [CustomEffectsDialog] modally.
  static Future<void> show({
    required BuildContext context,
    required PatchEditorController editorController,
    CustomEffectRepository? repository,
    ImportFileSystem? fileSystemOverride,
    String? initialDirectoryOverride,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => CustomEffectsDialog(
        editorController: editorController,
        repository: repository,
        fileSystemOverride: fileSystemOverride,
        initialDirectoryOverride: initialDirectoryOverride,
      ),
    );
  }

  @override
  State<CustomEffectsDialog> createState() => _CustomEffectsDialogState();
}

class _CustomEffectsDialogState extends State<CustomEffectsDialog> {
  static const Set<String> _zd2Extensions = {'.zd2'};

  late final ImportFileSystem _fileSystem;
  CustomEffectRepository? get _repository =>
      widget.repository ?? widget.editorController.customEffectRepository;

  bool _showFilePicker = false;
  bool _isBusy = false;
  bool _filterZd2Only = true;
  String _currentDir = '';
  String? _fsError;
  List<ImportQuickLocation> _quickLocations = const [];
  List<ImportFsEntry> _dirEntries = const [];
  final Set<String> _selectedFilePaths = {};

  List<CustomEffectEntry> _entries = const [];
  List<_Zd2ImportOutcome> _importOutcomes = const [];
  CustomEffectEntry? _lastRemovedEntry;

  @override
  void initState() {
    super.initState();
    _fileSystem = widget.fileSystemOverride ??
        widget.editorController.libraryController?.importFileSystem ??
        ((const bool.fromEnvironment('FLUTTER_TEST') ||
                Platform.environment.containsKey('FLUTTER_TEST'))
            ? InMemoryImportFileSystem()
            : const LocalImportFileSystem());
    widget.editorController.connectionController.addListener(_handleConnectionChanged);
    EffectCatalogRegistry.catalogRevision.addListener(_handleCatalogRevisionChanged);
    _loadEntries();
  }

  @override
  void dispose() {
    widget.editorController.connectionController
        .removeListener(_handleConnectionChanged);
    EffectCatalogRegistry.catalogRevision
        .removeListener(_handleCatalogRevisionChanged);
    super.dispose();
  }

  void _handleConnectionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleCatalogRevisionChanged() {
    if (!mounted) return;
    _syncEntriesFromRegistry();
  }

  Future<void> _rescanPedal() async {
    final connection = widget.editorController.connectionController;
    if (!connection.isConnected || !connection.activeFamily.isZoom6E) return;
    setState(() {
      _isBusy = true;
      _importOutcomes = const [];
      _lastRemovedEntry = null;
    });
    try {
      await connection.scanInstalledEffects();
      await _loadEntries();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _loadEntries() async {
    final repo = _repository;
    if (repo != null) {
      final persisted = await repo.loadAll();
      if (persisted.isNotEmpty) {
        // Ensure registry reflects persisted entries while preserving any
        // extra entries already registered in-memory (e.g. in tests).
        for (final entry in persisted) {
          EffectCatalogRegistry.registerCustomEffect(
            entry.toEffectDefinition(),
            generation: entry.generation,
            notify: false,
          );
        }
      }
    }
    _syncEntriesFromRegistry();
  }

  void _syncEntriesFromRegistry() {
    final registered = EffectCatalogRegistry.getRegisteredCustomEffects();
    final mapped = registered.map((r) {
      final def = r.definition;
      return CustomEffectEntry(
        effectId: def.effectId,
        name: def.name,
        version: def.version,
        description: def.description,
        sourceFilename: def.sourceFilename,
        generationTag: r.generation?.name,
        dspLoad: def.dspLoad ?? 0,
        parameters: def.parameters,
        importedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }).toList();
    mapped.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _entries = mapped;
    });
  }

  Future<void> _toggleFilePicker() async {
    if (_showFilePicker) {
      setState(() => _showFilePicker = false);
      return;
    }
    setState(() {
      _showFilePicker = true;
      _isBusy = true;
      _fsError = null;
    });
    try {
      final quick = await _fileSystem.getQuickLocations();
      final startDir = widget.initialDirectoryOverride ??
          await _fileSystem.resolveDefaultImportDirectory();
      if (!mounted) return;
      _quickLocations = quick;
      await _navigateTo(startDir);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fsError = 'Unable to open directory: $e';
        _isBusy = false;
      });
    }
  }

  Future<void> _navigateTo(String dirPath) async {
    setState(() {
      _isBusy = true;
      _fsError = null;
      _currentDir = dirPath;
      _selectedFilePaths.clear();
    });
    try {
      final entries = await _fileSystem.listDirectory(
        dirPath,
        allowedExtensions: _filterZd2Only ? _zd2Extensions : null,
      );
      if (!mounted) return;
      setState(() {
        _dirEntries = entries;
        _isBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dirEntries = const [];
        _fsError = 'Cannot read "$dirPath": $e';
        _isBusy = false;
      });
    }
  }

  Future<void> _navigateUp() async {
    if (_currentDir.isEmpty) return;
    final parent = await _fileSystem.parentDirectory(_currentDir);
    if (parent != null && mounted) {
      await _navigateTo(parent);
    }
  }

  void _toggleFileSelection(String path) {
    setState(() {
      if (_selectedFilePaths.contains(path)) {
        _selectedFilePaths.remove(path);
      } else {
        _selectedFilePaths.add(path);
      }
    });
  }

  void _toggleSelectAll() {
    final files = _dirEntries
        .where((e) => !e.isDirectory)
        .map((e) => e.path)
        .toList();
    if (files.isEmpty) return;
    setState(() {
      final allSelected = files.every(_selectedFilePaths.contains);
      if (allSelected) {
        _selectedFilePaths.clear();
      } else {
        _selectedFilePaths
          ..clear()
          ..addAll(files);
      }
    });
  }

  Future<void> _importFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    setState(() {
      _isBusy = true;
      _importOutcomes = const [];
      _lastRemovedEntry = null;
    });

    final outcomes = <_Zd2ImportOutcome>[];
    bool anyImported = false;

    for (final path in paths) {
      final filename = ImportFileSystem.baseName(path);
      try {
        final bytes = await _fileSystem.readFileBytes(path);
        final parsed = Zd2Parser.parse(bytes, sourceFilename: filename);
        final entry = CustomEffectEntry.fromParsedZd2(parsed);

        if (_repository != null) {
          await _repository!.upsert(entry);
        }
        EffectCatalogRegistry.registerCustomEffect(
          entry.toEffectDefinition(),
          generation: entry.generation,
        );
        anyImported = true;
        outcomes.add(_Zd2ImportOutcome(
          filename: filename,
          success: true,
          message:
              'Imported "${entry.name}" (${entry.effectId}, ${entry.parameters.length} params)',
        ));
      } on Zd2ParseException catch (e) {
        outcomes.add(_Zd2ImportOutcome(
          filename: filename,
          success: false,
          message: e.message,
        ));
      } catch (e) {
        outcomes.add(_Zd2ImportOutcome(
          filename: filename,
          success: false,
          message: 'Failed to read file: $e',
        ));
      }
    }

    if (anyImported) {
      widget.editorController.refreshEffectDefinitionsFromCatalog();
    }

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _selectedFilePaths.clear();
      _importOutcomes = outcomes;
    });
    _syncEntriesFromRegistry();
  }

  Future<void> _deleteEntry(CustomEffectEntry entry) async {
    if (_repository != null) {
      await _repository!.deleteById(
        entry.effectId,
        generationTag: entry.generationTag,
      );
    }
    EffectCatalogRegistry.unregisterCustomEffect(
      entry.effectId,
      generation: entry.generation,
    );
    widget.editorController.refreshEffectDefinitionsFromCatalog();

    if (!mounted) return;
    setState(() {
      _lastRemovedEntry = entry;
      _importOutcomes = const [];
    });
    _syncEntriesFromRegistry();
  }

  Future<void> _undoLastDelete() async {
    final removed = _lastRemovedEntry;
    if (removed == null) return;

    if (_repository != null) {
      await _repository!.upsert(removed);
    }
    EffectCatalogRegistry.registerCustomEffect(
      removed.toEffectDefinition(),
      generation: removed.generation,
    );
    widget.editorController.refreshEffectDefinitionsFromCatalog();

    if (!mounted) return;
    setState(() {
      _lastRemovedEntry = null;
    });
    _syncEntriesFromRegistry();
  }

  String _generationBadgeLabel(DeviceGeneration? gen) {
    switch (gen) {
      case DeviceGeneration.zoomMsPlus:
        return 'MS+';
      case DeviceGeneration.zoomFour:
        return 'Zoom Four';
      case DeviceGeneration.zoomOn:
      case DeviceGeneration.line6Pod:
      case DeviceGeneration.unknown:
      case null:
        return 'Universal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final isCompact = mediaSize.width < 600;
    final isShort = mediaSize.height < 520;
    final dialogWidth = math.min(600.0, math.max(260.0, mediaSize.width - 32));
    final connection = widget.editorController.connectionController;
    final isZoomConnected =
        connection.isConnected && connection.activeFamily.isZoom6E;
    final isScanningPedal = connection.isScanningEffects;

    return AlertDialog(
      backgroundColor: StudioTheme.surfaceElevated,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 36,
        vertical: isShort ? 10 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.extension,
            size: 20,
            color: StudioTheme.colorCustom,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Custom Effects (.ZD2)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: StudioTheme.colorCustom.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: StudioTheme.colorCustom.withValues(alpha: 0.7),
              ),
            ),
            child: Text(
              '${_entries.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: StudioTheme.colorCustom,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Action Row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        key: const Key('custom_effects_import_button'),
                        icon: Icon(
                          _showFilePicker
                              ? Icons.folder_off_outlined
                              : Icons.file_upload_outlined,
                          size: 16,
                        ),
                        label: Text(
                          _showFilePicker
                              ? 'Hide File Browser'
                              : 'Import .ZD2 File(s)...',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StudioTheme.colorCustom,
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed:
                            (_isBusy || isScanningPedal) ? null : _toggleFilePicker,
                      ),
                      if (isZoomConnected)
                        OutlinedButton.icon(
                          key: const Key('custom_effects_rescan_pedal_button'),
                          icon: isScanningPedal
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: StudioTheme.colorModulation,
                                  ),
                                )
                              : const Icon(Icons.sync, size: 15),
                          label: Text(
                            isScanningPedal ? 'Scanning...' : 'Rescan Pedal',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: StudioTheme.colorModulation,
                            side: const BorderSide(
                              color: StudioTheme.colorModulation,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed:
                              (_isBusy || isScanningPedal) ? null : _rescanPedal,
                        ),
                    ],
                  ),
                  const Text(
                    'Zoom ZDLF (.ZD2) format',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),

              if (isZoomConnected &&
                  (isScanningPedal ||
                      connection.installedEffectIds != null ||
                      connection.effectScanError != null)) ...[
                const SizedBox(height: 10),
                _buildPedalInventorySummary(connection),
              ],

              if (_showFilePicker) ...[
                const SizedBox(height: 10),
                _buildFileBrowserPane(isShort: isShort),
              ],

              if (_importOutcomes.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildImportOutcomesBanner(),
              ],

              if (_lastRemovedEntry != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('custom_effects_undo_banner'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: StudioTheme.colorPreamp.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: StudioTheme.colorPreamp.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: StudioTheme.colorPreamp,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Removed "${_lastRemovedEntry!.name}" (${_lastRemovedEntry!.effectId})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('undo_delete_custom_effect_button'),
                        onPressed: _undoLastDelete,
                        child: const Text(
                          'UNDO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: StudioTheme.colorPreamp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(color: StudioTheme.surfaceBorder, height: 1),
              const SizedBox(height: 10),

              if (_entries.isEmpty)
                Container(
                  key: const Key('custom_effects_empty_state'),
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StudioTheme.surfaceBorder),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.extension_off, size: 32, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No Custom Effects Imported',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Import Zoom .ZD2 files to resolve third-party or custom DSP effects with full parameter labels.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: isShort ? 180 : 280),
                  child: ListView.separated(
                    key: const Key('custom_effects_list'),
                    shrinkWrap: true,
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) => _buildEntryCard(_entries[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('custom_effects_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildPedalInventorySummary(dynamic connection) {
    final bool scanning = connection.isScanningEffects as bool;
    final Set<String>? installedIds = connection.installedEffectIds as Set<String>?;
    final String? scanStatus = connection.effectScanStatusMessage as String?;
    final String? scanError = connection.effectScanError as String?;
    final int stockCount = (connection.discoveredStockIds as Set<String>).length;
    final int crossCount =
        (connection.discoveredCrossModelIds as Set<String>).length;
    final int customCount =
        (connection.discoveredCustomIds as Set<String>).length;
    final DeviceEffectDiscoveryResult? discoveryResult =
        connection.lastEffectDiscoveryResult as DeviceEffectDiscoveryResult?;
    final List<FailedCustomEffectDiscovery> failedEffects =
        discoveryResult?.failedCustomEffects ?? const [];

    return Container(
      key: const Key('custom_effects_pedal_summary'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scanError != null && installedIds == null
              ? StudioTheme.colorPreamp.withValues(alpha: 0.7)
              : StudioTheme.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scanning)
            Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: StudioTheme.colorCustom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scanStatus ?? 'Scanning onboard effects...',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: StudioTheme.colorCustom,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else if (installedIds != null)
            Row(
              children: [
                const Icon(
                  Icons.usb,
                  size: 14,
                  color: StudioTheme.colorConnected,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Onboard Pedal Effects: $stockCount stock • $crossCount cross-model • $customCount custom',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (!scanning &&
              (failedEffects.isNotEmpty ||
                  (scanError != null && scanError.isNotEmpty))) ...[
            if (installedIds != null) const SizedBox(height: 6),
            Row(
              key: const Key('custom_effects_scan_warning'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: StudioTheme.colorPreamp,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: failedEffects.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Could not read ${failedEffects.length} onboard effect file(s):',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: StudioTheme.colorPreamp,
                              ),
                            ),
                            const SizedBox(height: 2),
                            for (final f in failedEffects)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '• ${f.filename} (${f.effectId}): ${f.reason}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: StudioTheme.colorPreamp,
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Text(
                          scanError!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: StudioTheme.colorPreamp,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileBrowserPane({required bool isShort}) {
    final fileEntries = _dirEntries.where((e) => !e.isDirectory).toList();
    final allSelected = fileEntries.isNotEmpty &&
        fileEntries.every((e) => _selectedFilePaths.contains(e.path));

    return Container(
      key: const Key('zd2_file_browser_pane'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.colorCustom.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_quickLocations.isNotEmpty) ...[
            HorizontalMouseScrollView(
              child: Row(
                children: _quickLocations.map((loc) {
                  final isSelected = _currentDir == loc.path;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      key: Key('zd2_quick_loc_${loc.label}'),
                      label: Text(
                        loc.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                      backgroundColor: isSelected
                          ? StudioTheme.colorCustom.withValues(alpha: 0.2)
                          : StudioTheme.surfaceElevated,
                      side: BorderSide(
                        color: isSelected
                            ? StudioTheme.colorCustom
                            : StudioTheme.surfaceBorder,
                      ),
                      onPressed: _isBusy ? null : () => _navigateTo(loc.path),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
          ],

          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                key: const Key('zd2_up_dir_button'),
                icon: const Icon(Icons.arrow_upward, size: 16),
                tooltip: 'Parent Folder',
                visualDensity: VisualDensity.compact,
                onPressed: _isBusy || _currentDir.isEmpty ? null : _navigateUp,
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: StudioTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Text(
                  _currentDir.isEmpty ? '...' : _currentDir,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ),
              FilterChip(
                key: const Key('zd2_filter_toggle'),
                label: Text(
                  _filterZd2Only ? '.ZD2 only' : 'All files',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: _filterZd2Only,
                onSelected: (val) {
                  setState(() => _filterZd2Only = val);
                  if (_currentDir.isNotEmpty) {
                    _navigateTo(_currentDir);
                  }
                },
              ),
              if (fileEntries.isNotEmpty) ...[
                TextButton(
                  key: const Key('zd2_select_all_button'),
                  onPressed: _isBusy ? null : _toggleSelectAll,
                  child: Text(
                    allSelected ? 'Deselect All' : 'Select All',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                if (_selectedFilePaths.isNotEmpty)
                  ElevatedButton.icon(
                    key: const Key('zd2_import_selected_button'),
                    icon: const Icon(Icons.playlist_add, size: 14),
                    label: Text(
                      'Import Selected (${_selectedFilePaths.length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioTheme.colorCustom,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: _isBusy
                        ? null
                        : () {
                            final ordered = _dirEntries
                                .where((e) =>
                                    !e.isDirectory &&
                                    _selectedFilePaths.contains(e.path))
                                .map((e) => e.path)
                                .toList();
                            _importFiles(ordered);
                          },
                  ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          SizedBox(
            height: isShort ? 110 : 155,
            child: Material(
              color: StudioTheme.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: StudioTheme.surfaceBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isBusy && _dirEntries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _fsError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              _fsError!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.redAccent,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _dirEntries.isEmpty
                          ? const Center(
                              child: Text(
                                'No .ZD2 files found in this folder',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _dirEntries.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: StudioTheme.surfaceBorder,
                              ),
                              itemBuilder: (context, idx) {
                                final entry = _dirEntries[idx];
                                if (entry.isDirectory) {
                                  return ListTile(
                                    key: Key('zd2_dir_${entry.name}'),
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    leading: const Icon(
                                      Icons.folder,
                                      size: 16,
                                      color: StudioTheme.colorFilterEq,
                                    ),
                                    title: Text(
                                      entry.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                    onTap: _isBusy
                                        ? null
                                        : () => _navigateTo(entry.path),
                                  );
                                }

                                final checked =
                                    _selectedFilePaths.contains(entry.path);
                                return ListTile(
                                  key: Key('zd2_file_${entry.name}'),
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  leading: Checkbox(
                                    key: Key('zd2_checkbox_${entry.name}'),
                                    value: checked,
                                    activeColor: StudioTheme.colorCustom,
                                    onChanged: _isBusy
                                        ? null
                                        : (_) => _toggleFileSelection(entry.path),
                                  ),
                                  title: Text(
                                    entry.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                  trailing: TextButton(
                                    key: Key('zd2_import_single_${entry.name}'),
                                    onPressed: _isBusy
                                        ? null
                                        : () => _importFiles([entry.path]),
                                    child: const Text(
                                      'Import',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: StudioTheme.colorCustom,
                                      ),
                                    ),
                                  ),
                                  onTap: _isBusy
                                      ? null
                                      : () => _toggleFileSelection(entry.path),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportOutcomesBanner() {
    return Container(
      key: const Key('zd2_import_outcomes'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _importOutcomes.map((o) {
          final color = o.success ? StudioTheme.colorDynamics : Colors.redAccent;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  o.success ? Icons.check_circle_outline : Icons.error_outline,
                  size: 15,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${o.filename}: ${o.message}',
                    style: TextStyle(fontSize: 11.5, color: color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEntryCard(CustomEffectEntry entry) {
    final genLabel = _generationBadgeLabel(entry.generation);
    final metaParts = <String>[
      entry.effectId,
      '${entry.parameters.length} params',
      if (entry.version != null && entry.version!.isNotEmpty) 'v${entry.version}',
      if (entry.sourceFilename != null && entry.sourceFilename!.isNotEmpty)
        entry.sourceFilename!,
    ];

    return Container(
      key: Key('custom_effect_item_${entry.effectId}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: StudioTheme.colorCustom,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: StudioTheme.colorCustom.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: StudioTheme.colorCustom.withValues(alpha: 0.7),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'CUSTOM',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: StudioTheme.colorCustom,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: StudioTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: StudioTheme.surfaceBorder),
                      ),
                      child: Text(
                        genLabel,
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  metaParts.join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: Colors.grey.shade400,
                  ),
                ),
                if (entry.description != null &&
                    entry.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: Key('delete_custom_effect_${entry.effectId}'),
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.redAccent,
            ),
            tooltip: 'Remove custom effect',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: () => _deleteEntry(entry),
          ),
        ],
      ),
    );
  }
}

