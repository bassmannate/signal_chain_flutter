import 'package:flutter/material.dart';

import '../../core/import/import_batch_result.dart';
import '../../core/import/import_file_system.dart';
import '../../core/import/patch_importer.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../connection/device_connection_controller.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/studio_theme.dart';
import 'bank_manager_dialog.dart';
import 'patch_library_controller.dart';

/// Modal dialog for batch-restoring multiple presets from the local library,
/// a saved backup file/folder on disk, or a JSON/SysEx bundle sequentially into
/// connected hardware memory slots.
class BankRestoreDialog extends StatefulWidget {
  final PatchLibraryController libraryController;
  final PatchEditorController editorController;
  final DeviceConnectionController connectionController;
  final Duration interSlotDelay;
  final ImportFileSystem? fileSystemOverride;
  final String? initialDirectoryOverride;

  const BankRestoreDialog({
    super.key,
    required this.libraryController,
    required this.editorController,
    required this.connectionController,
    this.interSlotDelay = const Duration(milliseconds: 10),
    this.fileSystemOverride,
    this.initialDirectoryOverride,
  });

  static Future<int?> show(
    BuildContext context, {
    required PatchLibraryController libraryController,
    required PatchEditorController editorController,
    required DeviceConnectionController connectionController,
    Duration interSlotDelay = const Duration(milliseconds: 10),
    ImportFileSystem? fileSystemOverride,
    String? initialDirectoryOverride,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => BankRestoreDialog(
        libraryController: libraryController,
        editorController: editorController,
        connectionController: connectionController,
        interSlotDelay: interSlotDelay,
        fileSystemOverride: fileSystemOverride,
        initialDirectoryOverride: initialDirectoryOverride,
      ),
    );
  }

  @override
  State<BankRestoreDialog> createState() => _BankRestoreDialogState();
}

class _BankRestoreDialogState extends State<BankRestoreDialog> {
  int _sourceTab = 0; // 0 = Local Presets, 1 = From File / Folder, 2 = Bundle / SysEx
  int _startSlotIndex = 0;
  final Set<String> _selectedLibraryIds = {};
  final TextEditingController _bundleController = TextEditingController();
  final TextEditingController _dirController = TextEditingController();

  late final ImportFileSystem _fileSystem;
  String _currentDir = '';
  List<ImportQuickLocation> _quickLocations = const [];
  List<ImportFsEntry> _dirEntries = const [];
  bool _isBrowsing = false;
  String? _fsError;
  List<Patch> _fileDecodedPatches = [];
  final Set<int> _selectedFileIndices = {};
  String? _fileDiagnostic;
  int _filteredCrossGenCount = 0;

  List<Patch> _parsedBundlePatches = [];
  String? _bundleDiagnostic;
  String? _completionSummary;
  bool _initializedSelection = false;

  @override
  void initState() {
    super.initState();
    _fileSystem =
        widget.fileSystemOverride ?? widget.libraryController.importFileSystem;
    _initDefaultSelection();
    _initBrowser();
  }

  bool _isGenerationCompatible(Patch patch) {
    final targetFamily = widget.connectionController.activeFamily;
    if (targetFamily == DeviceFamily.unknown ||
        patch.deviceFamily == DeviceFamily.unknown) {
      return true;
    }
    return patch.deviceFamily.isSameGeneration(targetFamily);
  }

  void _initDefaultSelection() {
    if (_initializedSelection) return;
    _initializedSelection = true;
    for (final patch in widget.libraryController.patches) {
      if (_isGenerationCompatible(patch)) {
        _selectedLibraryIds.add(patch.id);
      }
    }
  }

  Future<void> _initBrowser() async {
    try {
      final quick = await _fileSystem.getQuickLocations();
      final startDir = widget.initialDirectoryOverride ??
          widget.libraryController.lastExportDirectory ??
          await _fileSystem.resolveDefaultImportDirectory();
      if (!mounted) return;
      _quickLocations = quick;
      await _navigateDir(startDir);
    } catch (_) {}
  }

  Future<void> _navigateDir(String dirPath) async {
    final trimmed = dirPath.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _isBrowsing = true;
      _fsError = null;
      _currentDir = trimmed;
      _dirController.text = trimmed;
    });
    try {
      final entries = await _fileSystem.listDirectory(
        trimmed,
        allowedExtensions: PatchImporter.supportedExtensions,
      );
      if (!mounted) return;
      setState(() {
        _dirEntries = entries;
        _isBrowsing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dirEntries = const [];
        _fsError = 'Cannot open "$trimmed": $e';
        _isBrowsing = false;
      });
    }
  }

  Future<void> _navigateUp() async {
    if (_currentDir.isEmpty) return;
    final parent = await _fileSystem.parentDirectory(_currentDir);
    if (parent != null && mounted) {
      await _navigateDir(parent);
    }
  }

  Future<void> _decodeFile(ImportFsEntry entry) async {
    setState(() {
      _isBrowsing = true;
      _fsError = null;
    });
    final result = await widget.libraryController.importer.importFile(
      entry.path,
      fileSystem: _fileSystem,
      activeDeviceFamily: widget.connectionController.activeFamily,
    );
    if (!mounted) return;
    _applyDecodedFileResult(result, sourceLabel: entry.name);
  }

  Future<void> _decodeFolderBatch() async {
    if (_currentDir.isEmpty) return;
    setState(() {
      _isBrowsing = true;
      _fsError = null;
    });
    final result = await widget.libraryController.importer.importDirectory(
      _currentDir,
      fileSystem: _fileSystem,
      activeDeviceFamily: widget.connectionController.activeFamily,
    );
    if (!mounted) return;
    _applyDecodedFileResult(
      result,
      sourceLabel: ImportFileSystem.baseName(_currentDir),
    );
  }

  void _applyDecodedFileResult(
    ImportBatchResult result, {
    required String sourceLabel,
  }) {
    final decoded = result.entries.map((e) => e.patch).toList();
    int blockedCount = 0;
    final selected = <int>{};
    for (int i = 0; i < decoded.length; i++) {
      if (_isGenerationCompatible(decoded[i])) {
        selected.add(i);
      } else {
        blockedCount++;
      }
    }

    setState(() {
      _isBrowsing = false;
      _fileDecodedPatches = decoded;
      _selectedFileIndices
        ..clear()
        ..addAll(selected);
      _filteredCrossGenCount = blockedCount;
      if (decoded.isEmpty) {
        _fileDiagnostic = result.diagnostics.isNotEmpty
            ? result.diagnostics.first.message
            : 'No patches found in "$sourceLabel".';
      } else {
        _fileDiagnostic = blockedCount > 0
            ? 'Loaded ${decoded.length} patch(es) from "$sourceLabel" ($blockedCount incompatible generation excluded).'
            : 'Loaded ${decoded.length} compatible patch(es) from "$sourceLabel".';
      }
    });
  }

  @override
  void dispose() {
    _bundleController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  List<Patch> _resolveTargetPatches() {
    if (_sourceTab == 0) {
      return widget.libraryController.patches
          .where((p) =>
              _selectedLibraryIds.contains(p.id) && _isGenerationCompatible(p))
          .toList();
    }
    if (_sourceTab == 1) {
      final indices = _selectedFileIndices.toList()..sort();
      return [
        for (final i in indices)
          if (i >= 0 &&
              i < _fileDecodedPatches.length &&
              _isGenerationCompatible(_fileDecodedPatches[i]))
            _fileDecodedPatches[i],
      ];
    }
    return _parsedBundlePatches.where(_isGenerationCompatible).toList();
  }

  void _parseBundleText() {
    final result = widget.libraryController.importer.importText(
      _bundleController.text,
      sourceName: 'bank_restore_bundle',
      activeDeviceFamily: widget.connectionController.activeFamily,
    );
    final parsed = result.entries.map((e) => e.patch).toList();
    final compatibleCount = parsed.where(_isGenerationCompatible).length;
    final blockedCount = parsed.length - compatibleCount;
    setState(() {
      _parsedBundlePatches = parsed;
      if (parsed.isEmpty) {
        _bundleDiagnostic = result.diagnostics.isNotEmpty
            ? result.diagnostics.first.message
            : 'No patches found in pasted bundle.';
      } else {
        _bundleDiagnostic = blockedCount > 0
            ? 'Parsed $compatibleCount compatible patch(es) ($blockedCount incompatible generation excluded).'
            : 'Parsed $compatibleCount patch(es) ready for restore.';
      }
    });
  }

  Future<void> _startRestore() async {
    final patches = _resolveTargetPatches();
    if (patches.isEmpty) return;

    final targetFamily = widget.connectionController.activeFamily;
    Patch? firstModelMismatch;
    if (targetFamily != DeviceFamily.unknown) {
      for (final patch in patches) {
        if (patch.deviceFamily != DeviceFamily.unknown &&
            patch.deviceFamily != targetFamily &&
            patch.deviceFamily.isSameGeneration(targetFamily)) {
          firstModelMismatch = patch;
          break;
        }
      }
    }

    if (firstModelMismatch != null) {
      final proceed = await confirmDeviceMismatchDrop(
        context,
        patch: firstModelMismatch,
        targetFamily: targetFamily,
      );
      if (!proceed || !mounted) return;
    }

    setState(() {
      _completionSummary = null;
    });

    try {
      final written = await widget.editorController.restoreBankSlots(
        patches: patches,
        startSlotIndex: _startSlotIndex,
        interSlotDelay: widget.interSlotDelay,
      );
      if (mounted) {
        setState(() {
          _completionSummary = widget.editorController.bankRestoreStatus ??
              'Restored $written slot(s).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _completionSummary = 'Restore failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.libraryController,
        widget.editorController,
        widget.connectionController,
      ]),
      builder: (context, _) {
        final isConnected = widget.connectionController.isConnected;
        final isRestoring = widget.editorController.isRestoringBank;
        final totalSlots = widget.connectionController.activeFamily.totalMemorySlots;
        final libraryPatches = widget.libraryController.patches;
        final targetPatches = _resolveTargetPatches();
        final availableSlotsFromStart = totalSlots - _startSlotIndex;
        final effectiveWriteCount = targetPatches.length < availableSlotsFromStart
            ? targetPatches.length
            : availableSlotsFromStart;

        return Dialog(
          backgroundColor: StudioTheme.surfaceElevated,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.settings_backup_restore,
                        color: StudioTheme.colorFilterEq,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Restore Hardware Bank',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        key: const Key('close_bank_restore_button'),
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: isRestoring
                            ? null
                            : () => Navigator.of(context).pop(
                                  widget.editorController.bankRestoreCompletedCount,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Source Tabs
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: StudioTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: StudioTheme.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SourceTabButton(
                            key: const Key('restore_source_local_tab'),
                            label: 'Local Presets (${libraryPatches.length})',
                            isActive: _sourceTab == 0,
                            onTap: isRestoring
                                ? null
                                : () => setState(() => _sourceTab = 0),
                          ),
                        ),
                        Expanded(
                          child: _SourceTabButton(
                            key: const Key('restore_source_file_tab'),
                            label: 'From File / Folder',
                            isActive: _sourceTab == 1,
                            onTap: isRestoring
                                ? null
                                : () => setState(() => _sourceTab = 1),
                          ),
                        ),
                        Expanded(
                          child: _SourceTabButton(
                            key: const Key('restore_source_bundle_tab'),
                            label: 'Paste Bundle / SysEx',
                            isActive: _sourceTab == 2,
                            onTap: isRestoring
                                ? null
                                : () => setState(() => _sourceTab = 2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Starting slot selector
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Starting Hardware Slot:',
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            key: const Key('restore_start_slot_dropdown'),
                            value: _startSlotIndex.clamp(0, totalSlots - 1),
                            dropdownColor: StudioTheme.surfaceElevated,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            items: List.generate(totalSlots, (i) {
                              final label =
                                  '#${i.toString().padLeft(2, '0')} (${(i ~/ 10) + 1}-${(i % 10) + 1})';
                              return DropdownMenuItem(value: i, child: Text(label));
                            }),
                            onChanged: isRestoring
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setState(() => _startSlotIndex = val);
                                    }
                                  },
                          ),
                        ],
                      ),
                      Text(
                        effectiveWriteCount > 0
                            ? 'Target: #${_startSlotIndex.toString().padLeft(2, '0')} → #${(_startSlotIndex + effectiveWriteCount - 1).toString().padLeft(2, '0')} ($effectiveWriteCount slots)'
                            : 'Select presets to restore',
                        style: const TextStyle(
                          fontSize: 11,
                          color: StudioTheme.colorModulation,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Source Content
                  Expanded(
                    child: _sourceTab == 0
                        ? _buildLocalPresetsTab(libraryPatches, isRestoring)
                        : _sourceTab == 1
                            ? _buildFileFolderTab(isRestoring)
                            : _buildBundlePasteTab(isRestoring),
                  ),

                  // Progress & Status Area
                  if (isRestoring) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      key: const Key('bank_restore_progress_bar'),
                      value: widget.editorController.bankRestoreProgress > 0
                          ? widget.editorController.bankRestoreProgress
                          : null,
                      backgroundColor: StudioTheme.surfaceBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        StudioTheme.colorFilterEq,
                      ),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.editorController.bankRestoreStatus ??
                          'Restoring hardware slots...',
                      key: const Key('bank_restore_status_text'),
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ] else if (_completionSummary != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: StudioTheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: StudioTheme.colorModulation),
                      ),
                      child: Text(
                        _completionSummary!,
                        key: const Key('bank_restore_completion_text'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: StudioTheme.colorModulation,
                        ),
                      ),
                    ),
                  ],

                  if (!isConnected) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Connect a MIDI device before starting hardware bank restore.',
                      style: TextStyle(fontSize: 12, color: Colors.amberAccent),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isRestoring)
                        ElevatedButton.icon(
                          key: const Key('cancel_bank_restore_button'),
                          icon: const Icon(Icons.stop, size: 16),
                          label: const Text('Cancel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              widget.editorController.cancelBankRestore(),
                        )
                      else ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(
                            widget.editorController.bankRestoreCompletedCount,
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          key: const Key('start_bank_restore_button'),
                          icon: const Icon(Icons.upload, size: 16),
                          label: Text('Start Restore ($effectiveWriteCount)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StudioTheme.colorModulation,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: isConnected && effectiveWriteCount > 0
                              ? _startRestore
                              : null,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalPresetsTab(List<Patch> libraryPatches, bool isRestoring) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              key: const Key('restore_select_all_button'),
              onPressed: isRestoring || libraryPatches.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedLibraryIds.addAll(
                          libraryPatches
                              .where(_isGenerationCompatible)
                              .map((p) => p.id),
                        );
                      });
                    },
              child: const Text('Select All'),
            ),
            TextButton(
              key: const Key('restore_clear_selection_button'),
              onPressed: isRestoring || _selectedLibraryIds.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedLibraryIds.clear();
                      });
                    },
              child: const Text('Clear'),
            ),
            const Spacer(),
            Text(
              '${_selectedLibraryIds.length} selected',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const Divider(color: StudioTheme.surfaceBorder, height: 1),
        Expanded(
          child: libraryPatches.isEmpty
              ? const Center(
                  child: Text(
                    'No local presets available.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: libraryPatches.length,
                  itemBuilder: (context, index) {
                    final patch = libraryPatches[index];
                    final isCompatible = _isGenerationCompatible(patch);
                    final selected =
                        isCompatible && _selectedLibraryIds.contains(patch.id);
                    final isMismatch = isCompatible &&
                        patch.deviceFamily !=
                            widget.connectionController.activeFamily;
                    return CheckboxListTile(
                      key: Key('restore_select_patch_${patch.id}'),
                      value: selected,
                      dense: true,
                      activeColor: StudioTheme.colorModulation,
                      title: Text(
                        patch.name,
                        style: TextStyle(
                          color: isCompatible ? Colors.white : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        !isCompatible
                            ? '${patch.deviceFamily.displayName} (Incompatible Generation — Blocked)'
                            : isMismatch
                                ? '${patch.deviceFamily.displayName} (Same Gen Mismatch with ${widget.connectionController.activeFamily.displayName})'
                                : '${patch.deviceFamily.displayName} • ${patch.slots.length} slots',
                        style: TextStyle(
                          fontSize: 11,
                          color: !isCompatible
                              ? Colors.redAccent
                              : isMismatch
                                  ? Colors.orangeAccent
                                  : Colors.grey,
                        ),
                      ),
                      onChanged: (isRestoring || !isCompatible)
                          ? null
                          : (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedLibraryIds.add(patch.id);
                                } else {
                                  _selectedLibraryIds.remove(patch.id);
                                }
                              });
                            },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFileFolderTab(bool isRestoring) {
    final activeFamily = widget.connectionController.activeFamily;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_quickLocations.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickLocations.map((loc) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    key: Key('bank_restore_quick_loc_${loc.label}'),
                    label: Text(loc.label, style: const TextStyle(fontSize: 11)),
                    onPressed:
                        isRestoring ? null : () => _navigateDir(loc.path),
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              key: const Key('bank_restore_dir_up_button'),
              icon: const Icon(Icons.arrow_upward, size: 16),
              tooltip: 'Parent Folder',
              visualDensity: VisualDensity.compact,
              onPressed: isRestoring || _currentDir.isEmpty ? null : _navigateUp,
            ),
            Expanded(
              child: TextField(
                key: const Key('bank_restore_dir_path_field'),
                controller: _dirController,
                enabled: !isRestoring,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  hintText: 'Backup folder path...',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: StudioTheme.surface,
                ),
                onSubmitted: _navigateDir,
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              key: const Key('bank_restore_dir_go_button'),
              onPressed:
                  isRestoring ? null : () => _navigateDir(_dirController.text),
              child: const Text('Go', style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              key: const Key('bank_restore_load_folder_button'),
              icon: const Icon(Icons.drive_folder_upload, size: 14),
              label: const Text('Load Folder', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: StudioTheme.surface,
                foregroundColor: StudioTheme.colorModulation,
                side: const BorderSide(color: StudioTheme.colorModulation),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              onPressed: isRestoring || _currentDir.isEmpty
                  ? null
                  : _decodeFolderBatch,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: Material(
                  color: StudioTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: StudioTheme.surfaceBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _isBrowsing && _dirEntries.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _fsError != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  _fsError!,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.redAccent),
                                ),
                              ),
                            )
                          : _dirEntries.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No backup files (.json, .zptc, .syx)',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _dirEntries.length,
                                  itemBuilder: (context, index) {
                                    final entry = _dirEntries[index];
                                    return ListTile(
                                      key: Key('bank_restore_entry_${entry.name}'),
                                      dense: true,
                                      leading: Icon(
                                        entry.isDirectory
                                            ? Icons.folder
                                            : Icons.insert_drive_file,
                                        size: 16,
                                        color: entry.isDirectory
                                            ? StudioTheme.colorFilterEq
                                            : StudioTheme.colorModulation,
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
                                      onTap: isRestoring
                                          ? null
                                          : () {
                                              if (entry.isDirectory) {
                                                _navigateDir(entry.path);
                                              } else {
                                                _decodeFile(entry);
                                              }
                                            },
                                    );
                                  },
                                ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Material(
                  color: StudioTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: StudioTheme.surfaceBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_fileDiagnostic != null)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            _fileDiagnostic!,
                            key: const Key('bank_restore_file_diagnostic'),
                            style: TextStyle(
                              fontSize: 11,
                              color: _filteredCrossGenCount > 0
                                  ? Colors.orangeAccent
                                  : StudioTheme.colorDynamics,
                            ),
                          ),
                        ),
                      Expanded(
                        child: _fileDecodedPatches.isEmpty
                            ? const Center(
                                child: Text(
                                  'Select a backup file (.json / .syx / .zptc) or click Load Folder',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                itemCount: _fileDecodedPatches.length,
                                itemBuilder: (context, index) {
                                  final patch = _fileDecodedPatches[index];
                                  final compatible =
                                      _isGenerationCompatible(patch);
                                  final checked = compatible &&
                                      _selectedFileIndices.contains(index);
                                  return CheckboxListTile(
                                    key: Key('restore_file_patch_checkbox_$index'),
                                    value: checked,
                                    dense: true,
                                    activeColor: StudioTheme.colorModulation,
                                    title: Text(
                                      patch.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: compatible
                                            ? Colors.white
                                            : Colors.grey,
                                      ),
                                    ),
                                    subtitle: Text(
                                      !compatible
                                          ? '${patch.deviceFamily.displayName} (Incompatible Generation)'
                                          : '${patch.deviceFamily.displayName} • ${patch.slots.length} fx${patch.deviceFamily != activeFamily && activeFamily != DeviceFamily.unknown ? ' • Cross-Model' : ''}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: !compatible
                                            ? Colors.redAccent
                                            : Colors.grey,
                                      ),
                                    ),
                                    onChanged: (isRestoring || !compatible)
                                        ? null
                                        : (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedFileIndices.add(index);
                                              } else {
                                                _selectedFileIndices
                                                    .remove(index);
                                              }
                                            });
                                          },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBundlePasteTab(bool isRestoring) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste a Signal Chain JSON library bundle or multi-message SysEx hex dump (F0 ... F7):',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            key: const Key('restore_bundle_paste_input'),
            controller: _bundleController,
            enabled: !isRestoring,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: '{"format": "signal_chain_library", ...} or F0 52 00 ... F7',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 11),
              filled: true,
              fillColor: StudioTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              key: const Key('restore_parse_bundle_button'),
              icon: const Icon(Icons.playlist_add_check, size: 16),
              label: const Text('Parse Bundle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: StudioTheme.surface,
                foregroundColor: StudioTheme.colorModulation,
              ),
              onPressed: isRestoring ? null : _parseBundleText,
            ),
            const SizedBox(width: 10),
            if (_bundleDiagnostic != null)
              Expanded(
                child: Text(
                  _bundleDiagnostic!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _parsedBundlePatches.isNotEmpty
                        ? StudioTheme.colorDynamics
                        : Colors.amberAccent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SourceTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _SourceTabButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? StudioTheme.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? Border.all(color: StudioTheme.colorModulation.withValues(alpha: 0.6))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : Colors.grey,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

