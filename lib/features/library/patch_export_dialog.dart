import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/export_format.dart';
import '../../core/export/export_payload.dart';
import '../../core/import/import_file_system.dart';
import '../../models/patch.dart';
import '../theme/studio_theme.dart';
import 'patch_library_controller.dart';

/// Responsive, keyboard-safe dialog for exporting a single [Patch] or a
/// [List<Patch>] library/bank into native or external web-tool formats.
class PatchExportDialog extends StatefulWidget {
  final PatchLibraryController libraryController;
  final Patch? singlePatch;
  final List<Patch>? libraryPatches;
  final String title;
  final String defaultLibraryName;
  final Directory? exportDirectoryOverride;
  final ImportFileSystem? fileSystemOverride;

  const PatchExportDialog._({
    super.key,
    required this.libraryController,
    this.singlePatch,
    this.libraryPatches,
    required this.title,
    this.defaultLibraryName = 'signal_chain_library',
    this.exportDirectoryOverride,
    this.fileSystemOverride,
  });

  factory PatchExportDialog.patch({
    Key? key,
    required PatchLibraryController libraryController,
    required Patch patch,
    Directory? exportDirectoryOverride,
    ImportFileSystem? fileSystemOverride,
  }) {
    return PatchExportDialog._(
      key: key,
      libraryController: libraryController,
      singlePatch: patch,
      title: 'Export: ${patch.name}',
      exportDirectoryOverride: exportDirectoryOverride,
      fileSystemOverride: fileSystemOverride,
    );
  }

  factory PatchExportDialog.library({
    Key? key,
    required PatchLibraryController libraryController,
    required List<Patch> patches,
    String title = 'Export Preset Library',
    String defaultLibraryName = 'signal_chain_library',
    Directory? exportDirectoryOverride,
    ImportFileSystem? fileSystemOverride,
  }) {
    return PatchExportDialog._(
      key: key,
      libraryController: libraryController,
      libraryPatches: patches,
      title: title,
      defaultLibraryName: defaultLibraryName,
      exportDirectoryOverride: exportDirectoryOverride,
      fileSystemOverride: fileSystemOverride,
    );
  }

  @override
  State<PatchExportDialog> createState() => _PatchExportDialogState();
}

class _PatchExportDialogState extends State<PatchExportDialog> {
  late List<ExportFormat> _availableFormats;
  late ExportFormat _selectedFormat;
  late bool _setAsDefault;
  late ExportPayload _payload;
  late final TextEditingController _nameController;
  late final TextEditingController _dirController;
  late final TextEditingController _newFolderController;
  late final ImportFileSystem _fileSystem;

  String _currentDir = '';
  bool _hasCustomDirectory = false;
  bool _showFolderBrowser = false;
  bool _isBrowsing = false;
  String? _browseError;
  List<ImportQuickLocation> _quickLocations = const [];
  List<ImportFsEntry> _subfolders = const [];
  bool _showNewFolderInput = false;
  bool _isSaving = false;

  bool get _isLibraryMode => widget.libraryPatches != null;

  @override
  void initState() {
    super.initState();
    _fileSystem =
        widget.fileSystemOverride ?? widget.libraryController.importFileSystem;

    final registry = widget.libraryController.exportRegistry;
    if (_isLibraryMode) {
      _availableFormats = registry.allAdapters.map((a) => a.format).toList();
    } else {
      final family = widget.singlePatch!.deviceFamily;
      _availableFormats =
          registry.adaptersForDevice(family).map((a) => a.format).toList();
    }

    if (_availableFormats.isEmpty) {
      _availableFormats = [ExportFormat.nativeJson];
    }

    final savedDefault = widget.libraryController.defaultExportFormat;
    if (savedDefault != null && _availableFormats.contains(savedDefault)) {
      _selectedFormat = savedDefault;
      _setAsDefault = true;
    } else {
      _selectedFormat = _availableFormats.first;
      _setAsDefault = false;
    }

    _payload = _buildPayload(_selectedFormat);
    _nameController = TextEditingController(text: _payload.suggestedName);

    final initialDir = widget.exportDirectoryOverride?.path ??
        widget.libraryController.lastExportDirectory;
    _hasCustomDirectory = initialDir != null && initialDir.trim().isNotEmpty;
    _currentDir = initialDir?.trim() ?? '';
    _dirController = TextEditingController(text: _currentDir);
    _newFolderController = TextEditingController();
    _initDirectory();
  }

  Future<void> _initDirectory() async {
    try {
      final quick = await _fileSystem.getQuickLocations();
      String startDir = _currentDir;
      if (startDir.isEmpty) {
        startDir = await _fileSystem.resolveDefaultImportDirectory();
      }
      if (!mounted) return;
      setState(() {
        _quickLocations = quick;
        _currentDir = startDir;
        if (_dirController.text.isEmpty) {
          _dirController.text = startDir;
        }
      });
    } catch (_) {
      // Leave user editable field ready even if quick locations cannot be read
    }
  }

  Future<void> _loadDirectory(String path, {bool markCustom = true}) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _isBrowsing = true;
      _browseError = null;
      _currentDir = trimmed;
      _dirController.text = trimmed;
      if (markCustom) {
        _hasCustomDirectory = true;
      }
    });

    try {
      final entries = await _fileSystem.listDirectory(trimmed);
      if (!mounted) return;
      setState(() {
        _subfolders = entries.where((e) => e.isDirectory).toList();
        _isBrowsing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subfolders = const [];
        _browseError = 'Directory not listed ($e) — will be created on save.';
        _isBrowsing = false;
      });
    }
  }

  Future<void> _navigateUp() async {
    final current = _dirController.text.trim().isNotEmpty
        ? _dirController.text.trim()
        : _currentDir;
    if (current.isEmpty) return;
    final parent = await _fileSystem.parentDirectory(current);
    if (parent != null && mounted) {
      await _loadDirectory(parent);
    }
  }

  Future<void> _createNewFolder() async {
    final folderName = _newFolderController.text.trim();
    if (folderName.isEmpty) return;
    final sanitized = folderName.replaceAll('/', '_').replaceAll('\\', '_');
    final base = _dirController.text.trim().isNotEmpty
        ? _dirController.text.trim()
        : _currentDir;
    final sep = _fileSystem.pathSeparator;
    final targetPath = base.endsWith(sep) ? '$base$sanitized' : '$base$sep$sanitized';
    await _fileSystem.createDirectory(targetPath);
    if (!mounted) return;
    _newFolderController.clear();
    setState(() => _showNewFolderInput = false);
    await _loadDirectory(targetPath);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dirController.dispose();
    _newFolderController.dispose();
    super.dispose();
  }

  ExportPayload _buildPayload(ExportFormat format) {
    if (_isLibraryMode) {
      return widget.libraryController.exportLibraryWithFormat(
        format,
        patchesOverride: widget.libraryPatches,
        libraryName: widget.defaultLibraryName,
      );
    }
    return widget.libraryController.exportPatchWithFormat(
      widget.singlePatch!,
      format,
    );
  }

  void _onFormatChanged(ExportFormat? newFormat) {
    if (newFormat == null || newFormat == _selectedFormat) return;
    setState(() {
      _selectedFormat = newFormat;
      _setAsDefault = widget.libraryController.defaultExportFormat == newFormat;
      _payload = _buildPayload(newFormat);
      _nameController.text = _payload.suggestedName;
    });
  }

  Future<void> _onToggleDefault(bool? value) async {
    final checked = value ?? false;
    setState(() => _setAsDefault = checked);
    if (checked) {
      await widget.libraryController.setDefaultExportFormat(_selectedFormat);
    } else if (widget.libraryController.defaultExportFormat == _selectedFormat) {
      await widget.libraryController.setDefaultExportFormat(null);
    }
  }

  Future<void> _saveToDisk() async {
    setState(() => _isSaving = true);
    try {
      if (_setAsDefault) {
        await widget.libraryController.setDefaultExportFormat(_selectedFormat);
      }
      final typedDir = _dirController.text.trim();
      final effectiveTargetDir = widget.exportDirectoryOverride ??
          (_hasCustomDirectory && typedDir.isNotEmpty
              ? Directory(typedDir)
              : null);
      if (_hasCustomDirectory && typedDir.isNotEmpty) {
        await widget.libraryController.setLastExportDirectory(typedDir);
      }
      final savedPath = await widget.libraryController.saveExportToFile(
        _payload,
        targetDir: effectiveTargetDir,
        nameOverride: _nameController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to $savedPath'),
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final isCompact = mediaSize.width < 600;
    final isShort = mediaSize.height < 500;
    final dialogWidth = math.min(540.0, math.max(260.0, mediaSize.width - 32));

    return AlertDialog(
      backgroundColor: StudioTheme.surfaceElevated,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: isShort ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      title: Row(
        children: [
          const Icon(Icons.share, size: 18, color: StudioTheme.colorModulation),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              // Format Dropdown
              DropdownButtonFormField<ExportFormat>(
                key: const Key('export_format_dropdown'),
                initialValue: _selectedFormat,
                isExpanded: true,
                dropdownColor: StudioTheme.surfaceElevated,
                decoration: const InputDecoration(
                  labelText: 'Export Format',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: StudioTheme.surface,
                  isDense: true,
                ),
                items: _availableFormats.map((fmt) {
                  return DropdownMenuItem<ExportFormat>(
                    value: fmt,
                    child: Text(
                      fmt.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: _onFormatChanged,
              ),
              const SizedBox(height: 6),
              Text(
                _selectedFormat.subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),

              // Set as Default Checkbox
              CheckboxListTile(
                key: const Key('set_default_export_checkbox'),
                value: _setAsDefault,
                onChanged: _onToggleDefault,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: StudioTheme.colorModulation,
                title: const Text(
                  'Set as default format',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),

              // Editable Filename / Folder Name
              TextField(
                key: const Key('export_filename_field'),
                controller: _nameController,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  labelText: _payload.isDirectoryExport ? 'Folder Name' : 'File Name',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: StudioTheme.surface,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),

              // Destination Folder Path + Browse Toggle
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('export_destination_dir_field'),
                      controller: _dirController,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Destination Folder',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: StudioTheme.surface,
                        isDense: true,
                      ),
                      onChanged: (value) {
                        _currentDir = value.trim();
                        _hasCustomDirectory = true;
                      },
                      onSubmitted: (value) => _loadDirectory(value),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    key: const Key('export_browse_folder_button'),
                    icon: Icon(
                      _showFolderBrowser ? Icons.folder_open : Icons.folder,
                      size: 16,
                    ),
                    label: Text(
                      _showFolderBrowser ? 'Hide' : 'Browse...',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      final next = !_showFolderBrowser;
                      setState(() => _showFolderBrowser = next);
                      if (next) {
                        _loadDirectory(
                          _dirController.text.isNotEmpty
                              ? _dirController.text
                              : _currentDir,
                          markCustom: _hasCustomDirectory,
                        );
                      }
                    },
                  ),
                ],
              ),
              if (_showFolderBrowser) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('export_folder_browser_panel'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StudioTheme.surfaceBorder),
                  ),
                  child: Column(
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
                                  key: Key('export_quick_loc_${loc.label}'),
                                  label: Text(
                                    loc.label,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () => _loadDirectory(loc.path),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('export_dir_up_button'),
                            icon: const Icon(Icons.arrow_upward, size: 14),
                            label: const Text('..', style: TextStyle(fontSize: 12)),
                            onPressed: _navigateUp,
                          ),
                          OutlinedButton.icon(
                            key: const Key('export_dir_go_button'),
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text('Open', style: TextStyle(fontSize: 12)),
                            onPressed: () => _loadDirectory(_dirController.text),
                          ),
                          OutlinedButton.icon(
                            key: const Key('export_new_folder_button'),
                            icon: const Icon(Icons.create_new_folder_outlined, size: 14),
                            label: const Text('New Folder', style: TextStyle(fontSize: 12)),
                            onPressed: () => setState(
                              () => _showNewFolderInput = !_showNewFolderInput,
                            ),
                          ),
                        ],
                      ),
                      if (_showNewFolderInput) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('export_new_folder_name_field'),
                                controller: _newFolderController,
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: 'New folder name...',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: StudioTheme.surfaceElevated,
                                ),
                                onSubmitted: (_) => _createNewFolder(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              key: const Key('export_new_folder_confirm_button'),
                              onPressed: _createNewFolder,
                              child: const Text('Create', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                      if (_browseError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _browseError!,
                          style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Material(
                        type: MaterialType.transparency,
                        child: SizedBox(
                          height: 110,
                          child: _isBrowsing
                              ? const Center(child: CircularProgressIndicator())
                              : _subfolders.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No subfolders here',
                                        style: TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _subfolders.length,
                                      itemBuilder: (context, index) {
                                        final folder = _subfolders[index];
                                        return ListTile(
                                          key: Key('export_subfolder_item_${folder.name}'),
                                          dense: true,
                                          leading: const Icon(
                                            Icons.folder,
                                            size: 16,
                                            color: StudioTheme.colorFilterEq,
                                          ),
                                          title: Text(
                                            folder.name,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          onTap: () => _loadDirectory(folder.path),
                                        );
                                      },
                                    ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Compatibility Warning Banner
              if (_payload.warnings.isNotEmpty) ...[
                Container(
                  key: const Key('export_warning_banner'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _payload.warnings.join(' '),
                          style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Preview Box
              Container(
                constraints: BoxConstraints(maxHeight: isShort ? 110 : 180),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _payload.previewText,
                    key: const Key('export_payload_preview'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_selectedFormat.supportsTextCopy && !_payload.isDirectoryExport)
          TextButton.icon(
            key: const Key('export_copy_button'),
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _payload.previewText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          key: const Key('export_save_button'),
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _payload.isDirectoryExport ? Icons.create_new_folder_outlined : Icons.save_alt,
                  size: 16,
                ),
          label: Text(_payload.isDirectoryExport ? 'Save Folder' : 'Save File'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioTheme.colorModulation,
            foregroundColor: Colors.black,
          ),
          onPressed: _isSaving || _payload.exportedPatchCount == 0 ? null : _saveToDisk,
        ),
      ],
    );
  }
}

