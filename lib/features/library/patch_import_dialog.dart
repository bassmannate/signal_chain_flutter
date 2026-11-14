import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/import/import_batch_result.dart';
import '../../core/import/import_file_system.dart';
import '../../core/import/import_format.dart';
import '../../core/import/imported_patch_entry.dart';
import '../../core/import/patch_importer.dart';
import '../../models/device_family.dart';
import '../../models/patch_diff.dart';
import '../editor/patch_diff_dialog.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/studio_theme.dart';
import 'patch_library_controller.dart';

/// Responsive, keyboard-safe dialog for importing patches and batch folders
/// from Signal Chain JSON, Zoom PTCF, Symbiosis `.zptc`, MultiStomp Studio,
/// Raw SysEx (`.syx`), or clipboard text.
class PatchImportDialog extends StatefulWidget {
  final PatchLibraryController libraryController;
  final PatchEditorController editorController;
  final ImportFileSystem? fileSystemOverride;
  final String? initialDirectoryOverride;

  const PatchImportDialog({
    super.key,
    required this.libraryController,
    required this.editorController,
    this.fileSystemOverride,
    this.initialDirectoryOverride,
  });

  @override
  State<PatchImportDialog> createState() => _PatchImportDialogState();
}

class _PatchImportDialogState extends State<PatchImportDialog> {
  int _activeTabIndex = 0; // 0 = Browse Files, 1 = Paste JSON / SysEx
  late final ImportFileSystem _fileSystem;
  late final TextEditingController _pasteController;

  String _currentDir = '';
  List<ImportQuickLocation> _quickLocations = const [];
  List<ImportFsEntry> _dirEntries = const [];
  bool _filterSupportedOnly = true;
  bool _isBusy = false;
  String? _fsError;
  String? _selectedFilePath;
  final Set<String> _selectedBrowserFilePaths = {};

  ImportBatchResult? _result;
  final Set<int> _selectedIndices = {};
  bool _alsoSaveOnLoad = false;
  bool _alsoLoadIntoEditor = false;

  @override
  void initState() {
    super.initState();
    _fileSystem =
        widget.fileSystemOverride ?? widget.libraryController.importFileSystem;
    _pasteController = TextEditingController();
    _initBrowser();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  DeviceFamily get _activeFamily =>
      widget.editorController.connectionController.activeFamily;

  PatchImporter get _importer => widget.libraryController.importer;

  Future<void> _initBrowser() async {
    setState(() {
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
      _selectedBrowserFilePaths.clear();
    });

    try {
      final entries = await _fileSystem.listDirectory(
        dirPath,
        allowedExtensions:
            _filterSupportedOnly ? PatchImporter.supportedExtensions : null,
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

  Future<void> _selectFile(ImportFsEntry entry) async {
    setState(() {
      _isBusy = true;
      _selectedFilePath = entry.path;
    });
    final res = await _importer.importFile(
      entry.path,
      fileSystem: _fileSystem,
      activeDeviceFamily: _activeFamily,
    );
    if (!mounted) return;
    _applyImportResult(res);
  }

  void _toggleBrowserFile(String path) {
    setState(() {
      if (_selectedBrowserFilePaths.contains(path)) {
        _selectedBrowserFilePaths.remove(path);
      } else {
        _selectedBrowserFilePaths.add(path);
      }
    });
  }

  void _toggleSelectAllFiles() {
    final filePaths = _dirEntries
        .where((e) => !e.isDirectory)
        .map((e) => e.path)
        .toList();
    if (filePaths.isEmpty) return;
    setState(() {
      final allChecked =
          filePaths.every((path) => _selectedBrowserFilePaths.contains(path));
      if (allChecked) {
        _selectedBrowserFilePaths.clear();
      } else {
        _selectedBrowserFilePaths
          ..clear()
          ..addAll(filePaths);
      }
    });
  }

  Future<void> _decodeSelectedFiles() async {
    final selectedPaths = _dirEntries
        .where((e) => !e.isDirectory && _selectedBrowserFilePaths.contains(e.path))
        .map((e) => e.path)
        .toList();
    if (selectedPaths.isEmpty) return;

    setState(() {
      _isBusy = true;
      _selectedFilePath = selectedPaths.length == 1 ? selectedPaths.first : null;
    });

    var aggregate = const ImportBatchResult();
    for (final filePath in selectedPaths) {
      final res = await _importer.importFile(
        filePath,
        fileSystem: _fileSystem,
        activeDeviceFamily: _activeFamily,
      );
      aggregate = aggregate.merge(res);
    }
    if (!mounted) return;
    _applyImportResult(aggregate);
  }

  Future<void> _importCurrentFolder() async {
    if (_currentDir.isEmpty) return;
    setState(() {
      _isBusy = true;
      _selectedFilePath = null;
    });
    final res = await _importer.importDirectory(
      _currentDir,
      fileSystem: _fileSystem,
      activeDeviceFamily: _activeFamily,
    );
    if (!mounted) return;
    _applyImportResult(res);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    _pasteController.text = text;
    if (text.trim().isNotEmpty) {
      _parsePastedText();
    }
  }

  void _parsePastedText() {
    final res = _importer.importText(
      _pasteController.text,
      sourceName: 'clipboard',
      activeDeviceFamily: _activeFamily,
    );
    _applyImportResult(res);
  }

  void _applyImportResult(ImportBatchResult res) {
    setState(() {
      _isBusy = false;
      _result = res;
      _alsoLoadIntoEditor = false;
      _selectedIndices
        ..clear()
        ..addAll(List<int>.generate(res.entries.length, (i) => i));
    });
  }

  void _toggleSelectAll(bool? value) {
    final entries = _result?.entries ?? const [];
    setState(() {
      if (value == true) {
        _selectedIndices
          ..clear()
          ..addAll(List<int>.generate(entries.length, (i) => i));
      } else {
        _selectedIndices.clear();
      }
    });
  }

  List<ImportedPatchEntry> get _selectedEntries {
    final entries = _result?.entries ?? const [];
    final indices = _selectedIndices.toList()..sort();
    return [
      for (final idx in indices)
        if (idx >= 0 && idx < entries.length) entries[idx],
    ];
  }

  Future<void> _addToLibrary() async {
    final selected = _selectedEntries;
    if (selected.isEmpty) return;

    setState(() => _isBusy = true);
    try {
      final saved = await widget.libraryController.importEntries(selected);
      if (_alsoLoadIntoEditor && selected.length == 1 && saved.isNotEmpty) {
        final entry = selected.first;
        final patchToLoad = saved.first;
        final connection = widget.editorController.connectionController;
        if (!connection.isConnected &&
            entry.isDeviceMismatch(connection.activeFamily) &&
            entry.inferredDeviceFamily != DeviceFamily.unknown) {
          connection.selectDeviceFamily(entry.inferredDeviceFamily);
        }
        widget.editorController.loadPatch(patchToLoad);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${saved.length} patch${saved.length == 1 ? '' : 'es'} to library'
            '${(_alsoLoadIntoEditor && selected.length == 1) ? ' and loaded into editor' : ''}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _loadIntoEditor() async {
    final selected = _selectedEntries;
    if (selected.length != 1) return;

    final entry = selected.first;
    var patchToLoad = entry.patch;

    setState(() => _isBusy = true);
    try {
      if (_alsoSaveOnLoad) {
        final saved = await widget.libraryController.importEntries([entry]);
        if (saved.isNotEmpty) {
          patchToLoad = saved.first;
        }
      }

      final connection = widget.editorController.connectionController;
      final isConnected = connection.isConnected;
      final previousFamily = connection.activeFamily;
      final isMismatch = entry.isDeviceMismatch(previousFamily);

      if (!isConnected &&
          isMismatch &&
          entry.inferredDeviceFamily != DeviceFamily.unknown) {
        connection.selectDeviceFamily(entry.inferredDeviceFamily);
      }

      widget.editorController.loadPatch(patchToLoad);

      if (!mounted) return;
      final String message;
      if (isConnected && isMismatch) {
        message =
            'Loaded "${patchToLoad.name}" into editor (targets ${entry.inferredDeviceFamily.displayName}; active hardware is ${previousFamily.displayName})';
      } else {
        message = 'Loaded "${patchToLoad.name}" into editor';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load patch: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final isCompact = mediaSize.width < 600;
    final isShort = mediaSize.height < 520;
    final dialogWidth = math.min(620.0, math.max(260.0, mediaSize.width - 32));
    final selected = _selectedEntries;

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
            Icons.file_download_outlined,
            size: 20,
            color: StudioTheme.colorModulation,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Import Patches',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              // Mode Toggle: File & Folder Browser | Paste JSON / SysEx
              _buildModeTabs(),
              const SizedBox(height: 10),

              if (_activeTabIndex == 0)
                _buildFileBrowserPane(isShort: isShort)
              else
                _buildPastePane(isShort: isShort),

              if (_result != null) ...[
                const SizedBox(height: 12),
                _buildPreviewPane(isShort: isShort),
              ],

              if (selected.length == 1) ...[
                const SizedBox(height: 6),
                CheckboxListTile(
                  key: const Key('import_also_load_into_editor_checkbox'),
                  value: _alsoLoadIntoEditor,
                  onChanged: (v) =>
                      setState(() => _alsoLoadIntoEditor = v ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: StudioTheme.colorModulation,
                  title: const Text(
                    'Also load into Editor',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                CheckboxListTile(
                  key: const Key('import_also_save_checkbox'),
                  value: _alsoSaveOnLoad,
                  onChanged: (v) => setState(() => _alsoSaveOnLoad = v ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: StudioTheme.colorModulation,
                  title: const Text(
                    'Also save to local library when loading into editor',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('import_cancel_button'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          key: const Key('import_load_editor_button'),
          icon: const Icon(Icons.play_arrow_rounded, size: 16),
          label: const Text('Load into Editor'),
          style: OutlinedButton.styleFrom(
            foregroundColor: StudioTheme.colorDynamics,
            side: BorderSide(
              color: selected.length == 1
                  ? StudioTheme.colorDynamics
                  : StudioTheme.surfaceBorder,
            ),
          ),
          onPressed: _isBusy || selected.length != 1 ? null : _loadIntoEditor,
        ),
        ElevatedButton.icon(
          key: const Key('import_add_library_button'),
          icon: const Icon(Icons.library_add, size: 16),
          label: Text(
            selected.length > 1
                ? 'Import to Library (${selected.length})'
                : 'Import to Library',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioTheme.colorModulation,
            foregroundColor: Colors.black,
          ),
          onPressed: _isBusy || selected.isEmpty ? null : _addToLibrary,
        ),
      ],
    );
  }

  Widget _buildModeTabs() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('import_tab_browse'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _activeTabIndex = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeTabIndex == 0
                      ? StudioTheme.surfaceElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: _activeTabIndex == 0
                      ? Border.all(color: StudioTheme.surfaceBorder)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 14,
                      color: _activeTabIndex == 0
                          ? StudioTheme.colorModulation
                          : Colors.grey,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'File & Folder',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              _activeTabIndex == 0 ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              key: const Key('import_tab_paste'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _activeTabIndex = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeTabIndex == 1
                      ? StudioTheme.surfaceElevated
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: _activeTabIndex == 1
                      ? Border.all(color: StudioTheme.surfaceBorder)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.content_paste,
                      size: 14,
                      color: _activeTabIndex == 1
                          ? StudioTheme.colorModulation
                          : Colors.grey,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Paste JSON / SysEx',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              _activeTabIndex == 1 ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileBrowserPane({required bool isShort}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quick Location Chips
        if (_quickLocations.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickLocations.map((loc) {
                final isSelected = _currentDir == loc.path;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    key: Key('import_quick_loc_${loc.label}'),
                    avatar: Icon(
                      Icons.folder_special,
                      size: 14,
                      color: isSelected
                          ? StudioTheme.colorModulation
                          : Colors.grey,
                    ),
                    label: Text(
                      loc.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                    backgroundColor: isSelected
                        ? StudioTheme.colorModulation.withValues(alpha: 0.18)
                        : StudioTheme.surface,
                    side: BorderSide(
                      color: isSelected
                          ? StudioTheme.colorModulation
                          : StudioTheme.surfaceBorder,
                    ),
                    onPressed: _isBusy ? null : () => _navigateTo(loc.path),
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 8),

        // Current Path Bar + Up + Filter + Import Folder
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              key: const Key('import_up_dir_button'),
              icon: const Icon(Icons.arrow_upward, size: 16),
              tooltip: 'Parent Folder',
              visualDensity: VisualDensity.compact,
              onPressed: _isBusy || _currentDir.isEmpty ? null : _navigateUp,
            ),
            Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: StudioTheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: StudioTheme.surfaceBorder),
              ),
              child: Text(
                _currentDir.isEmpty ? '...' : _currentDir,
                key: const Key('import_current_path_text'),
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
              key: const Key('import_filter_toggle'),
              label: Text(
                _filterSupportedOnly ? '.json/.zptc/.syx' : 'All files',
                style: const TextStyle(fontSize: 11),
              ),
              selected: _filterSupportedOnly,
              onSelected: (val) {
                setState(() => _filterSupportedOnly = val);
                if (_currentDir.isNotEmpty) {
                  _navigateTo(_currentDir);
                }
              },
            ),
            ElevatedButton.icon(
              key: const Key('import_folder_button'),
              icon: const Icon(Icons.drive_folder_upload, size: 15),
              label: const Text('Import Folder', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: StudioTheme.surface,
                foregroundColor: StudioTheme.colorModulation,
                side: const BorderSide(color: StudioTheme.colorModulation),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              onPressed:
                  _isBusy || _currentDir.isEmpty ? null : _importCurrentFolder,
            ),
            if (_dirEntries.any((e) => !e.isDirectory)) ...[
              TextButton.icon(
                key: const Key('import_browser_select_all_files_button'),
                icon: const Icon(Icons.select_all, size: 14),
                label: Text(
                  _dirEntries
                          .where((e) => !e.isDirectory)
                          .every((e) => _selectedBrowserFilePaths.contains(e.path))
                      ? 'Deselect All Files'
                      : 'Select All Files',
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: _isBusy ? null : _toggleSelectAllFiles,
              ),
              if (_selectedBrowserFilePaths.isNotEmpty)
                ElevatedButton.icon(
                  key: const Key('import_browser_decode_selected_button'),
                  icon: const Icon(Icons.playlist_add_check, size: 14),
                  label: Text(
                    'Decode Selected (${_selectedBrowserFilePaths.length})',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StudioTheme.colorDynamics,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _isBusy ? null : _decodeSelectedFiles,
                ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Directory Listing
        SizedBox(
          height: isShort ? 120 : 170,
          child: Material(
            color: StudioTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: StudioTheme.surfaceBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: _isBusy && _dirEntries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _fsError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _fsError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.redAccent,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _dirEntries.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching patch files in this folder',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          key: const Key('import_file_list'),
                          itemCount: _dirEntries.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: StudioTheme.surfaceBorder,
                          ),
                          itemBuilder: (context, index) {
                            final entry = _dirEntries[index];
                            final isSelected = _selectedFilePath == entry.path;
                            final isMultiChecked =
                                !entry.isDirectory &&
                                _selectedBrowserFilePaths.contains(entry.path);
                            return ListTile(
                              key: Key('import_fs_entry_${entry.name}'),
                              dense: true,
                              selected: isSelected || isMultiChecked,
                              selectedTileColor: StudioTheme.colorModulation
                                  .withValues(alpha: 0.14),
                              leading: entry.isDirectory
                                  ? const Icon(
                                      Icons.folder,
                                      size: 18,
                                      color: StudioTheme.colorFilterEq,
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Checkbox(
                                          key: Key('import_browser_file_checkbox_${entry.name}'),
                                          value: isMultiChecked,
                                          onChanged: _isBusy
                                              ? null
                                              : (_) => _toggleBrowserFile(entry.path),
                                          visualDensity: VisualDensity.compact,
                                          activeColor: StudioTheme.colorModulation,
                                        ),
                                        Icon(
                                          _iconForFileName(entry.name),
                                          size: 18,
                                          color: StudioTheme.colorModulation,
                                        ),
                                      ],
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
                              trailing: entry.isDirectory
                                  ? const Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: Colors.grey,
                                    )
                                  : Text(
                                      '${entry.sizeBytes} B',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                              onTap: _isBusy
                                  ? null
                                  : () {
                                      if (entry.isDirectory) {
                                        _navigateTo(entry.path);
                                      } else {
                                        _selectFile(entry);
                                      }
                                    },
                            );
                          },
                        ),
          ),
        ),
      ],
    );
  }

  Widget _buildPastePane({required bool isShort}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Paste Signal Chain JSON (patch or bundle) or SysEx hex:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: const Key('import_paste_clipboard_button'),
                  icon: const Icon(Icons.content_paste, size: 14),
                  label: const Text('Paste from Clipboard',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _pasteFromClipboard,
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  key: const Key('import_parse_text_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StudioTheme.surface,
                    foregroundColor: StudioTheme.colorModulation,
                    side: const BorderSide(color: StudioTheme.colorModulation),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _parsePastedText,
                  child: const Text('Parse', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('import_paste_text_field'),
          controller: _pasteController,
          maxLines: isShort ? 3 : 6,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            hintText:
                '{\n  "name": "My Patch",\n  "deviceFamily": "zoomMs60bPlus",\n  "slots": []\n}\n\nOR:\nF0 52 00 6E ... F7',
            border: OutlineInputBorder(),
            fillColor: StudioTheme.surface,
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPane({required bool isShort}) {
    final res = _result!;
    final entries = res.entries;
    final errors = res.allErrors;
    final warnings = res.allWarnings;
    final allSelected =
        entries.isNotEmpty && _selectedIndices.length == entries.length;

    final formatLabel = _summarizeFormats(entries);
    final deviceLabel = _summarizeDevices(entries);

    return Material(
      key: const Key('import_preview_pane'),
      color: StudioTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Badges + Select All
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BadgeChip(
                    key: const Key('import_format_badge'),
                    label: formatLabel,
                    color: StudioTheme.colorModulation,
                  ),
                  if (deviceLabel != null)
                    _BadgeChip(
                      key: const Key('import_device_badge'),
                      label: deviceLabel,
                      color: StudioTheme.colorDynamics,
                    ),
                  Text(
                    '${entries.length} patch${entries.length == 1 ? '' : 'es'}'
                    '${res.skippedCount > 0 ? ' • ${res.skippedCount} skipped' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
              if (entries.length > 1)
                InkWell(
                  onTap: () => _toggleSelectAll(!allSelected),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const Key('import_select_all_checkbox'),
                        value: allSelected,
                        onChanged: _toggleSelectAll,
                        visualDensity: VisualDensity.compact,
                        activeColor: StudioTheme.colorModulation,
                      ),
                      const Text(
                        'Select all',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Error Banner
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('import_error_banner'),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errors.join('\n'),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Warning Banner
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('import_warning_banner'),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warnings.join('\n'),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.amberAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Decoded Entries Checklist
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: isShort ? 110 : 165),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: StudioTheme.surfaceBorder),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final checked = _selectedIndices.contains(index);
                  final hasMismatch = entry.isDeviceMismatch(_activeFamily);
                  return CheckboxListTile(
                    key: Key('import_entry_checkbox_$index'),
                    value: checked,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: StudioTheme.colorModulation,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIndices.add(index);
                        } else {
                          _selectedIndices.remove(index);
                        }
                      });
                    },
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.patch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (hasMismatch || entry.warnings.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: Colors.amberAccent,
                            ),
                          ),
                        if (widget.editorController.patch != null)
                          IconButton(
                            key: Key('import_entry_diff_$index'),
                            icon: const Icon(Icons.compare_arrows, size: 15, color: Colors.grey),
                            tooltip: 'Compare with Active Editor',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                            onPressed: () {
                              final current = widget.editorController.patch!;
                              PatchDiffDialog.show(
                                context,
                                baseLabel: 'Active Editor',
                                targetLabel: 'Imported',
                                diff: PatchDiff.compute(current, entry.patch),
                              );
                            },
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${entry.inferredDeviceFamily.displayName} • '
                      '${entry.patch.slots.length} slot${entry.patch.slots.length == 1 ? '' : 's'}'
                      '${entry.patch.programNumber != null ? ' • #${entry.patch.programNumber.toString().padLeft(2, '0')}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  static IconData _iconForFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.json')) return Icons.data_object;
    if (lower.endsWith('.zptc')) return Icons.audio_file;
    if (lower.endsWith('.syx')) return Icons.memory;
    return Icons.insert_drive_file;
  }

  static String _summarizeFormats(List<ImportedPatchEntry> entries) {
    if (entries.isEmpty) return ImportFormat.unknown.displayName;
    final formats = entries.map((e) => e.detectedFormat).toSet();
    if (formats.length == 1) return formats.first.displayName;
    return 'Mixed (${formats.length} formats)';
  }

  static String? _summarizeDevices(List<ImportedPatchEntry> entries) {
    if (entries.isEmpty) return null;
    final families = entries.map((e) => e.inferredDeviceFamily).toSet();
    if (families.length == 1) return families.first.displayName;
    return 'Mixed (${families.length} devices)';
  }
}

class _BadgeChip extends StatelessWidget {
  final String label;
  final Color color;

  const _BadgeChip({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

