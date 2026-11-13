import 'package:flutter/material.dart';

import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/studio_theme.dart';
import 'hardware_bank_browser_widget.dart';
import 'patch_export_dialog.dart';
import 'patch_import_dialog.dart';
import 'patch_library_controller.dart';

/// Responsive preset library and hardware bank browser showing search, device filters,
/// tags, patch cards with load/export/delete capabilities, and hardware slot management.
class PatchLibraryDrawerOrPanel extends StatefulWidget {
  final PatchLibraryController libraryController;
  final PatchEditorController editorController;
  final bool isPanel; // true if side panel, false if in drawer / bottom sheet
  final int initialTabIndex;
  final double panelWidth;

  const PatchLibraryDrawerOrPanel({
    super.key,
    required this.libraryController,
    required this.editorController,
    this.isPanel = true,
    this.initialTabIndex = 0,
    this.panelWidth = 340,
  });

  @override
  State<PatchLibraryDrawerOrPanel> createState() => _PatchLibraryDrawerOrPanelState();
}

class _PatchLibraryDrawerOrPanelState extends State<PatchLibraryDrawerOrPanel> {
  late int _selectedTabIndex;

  PatchLibraryController get libraryController => widget.libraryController;
  PatchEditorController get editorController => widget.editorController;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.libraryController,
      builder: (context, _) {
        final patches = widget.libraryController.patches;
        final selectedFamily = widget.libraryController.deviceFilter;

        return Container(
          width: widget.isPanel ? widget.panelWidth : double.infinity,
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            border: widget.isPanel
                ? const Border(
                    left: BorderSide(color: StudioTheme.surfaceBorder, width: 1),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Segmented Tab Toggle: [Local Presets] | [Hardware Bank]
              Container(
                margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: StudioTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const Key('library_tab_local'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() => _selectedTabIndex = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 0 ? StudioTheme.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: _selectedTabIndex == 0
                                ? Border.all(color: StudioTheme.surfaceBorder)
                                : null,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder,
                                  size: 14,
                                  color: _selectedTabIndex == 0
                                      ? StudioTheme.colorModulation
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Local Presets',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTabIndex == 0 ? Colors.white : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        key: const Key('library_tab_hardware'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() => _selectedTabIndex = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 1 ? StudioTheme.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: _selectedTabIndex == 1
                                ? Border.all(color: StudioTheme.surfaceBorder)
                                : null,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.memory,
                                  size: 14,
                                  color: _selectedTabIndex == 1
                                      ? StudioTheme.colorFilterEq
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Hardware Bank',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTabIndex == 1 ? Colors.white : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Active Tab Content
              Expanded(
                child: _selectedTabIndex == 1
                    ? HardwareBankBrowserWidget(
                        connectionController: widget.editorController.connectionController,
                        editorController: widget.editorController,
                        libraryController: widget.libraryController,
                        isPanel: false,
                      )
                    : _buildLocalLibraryContent(context, patches, selectedFamily),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocalLibraryContent(
    BuildContext context,
    List<Patch> patches,
    DeviceFamily? selectedFamily,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, top: 16, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.library_music, size: 18, color: StudioTheme.colorModulation),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'PRESET LIBRARY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const Key('export_library_button'),
                      icon: const Icon(
                        Icons.ios_share,
                        size: 19,
                        color: StudioTheme.colorModulation,
                      ),
                      tooltip: 'Export Library',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: patches.isEmpty
                          ? null
                          : () => showDialog<bool>(
                                context: context,
                                builder: (_) => PatchExportDialog.library(
                                  libraryController: libraryController,
                                  patches: patches,
                                  title: 'Export Preset Library (${patches.length})',
                                ),
                              ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('import_preset_button'),
                      icon: const Icon(
                        Icons.file_download_outlined,
                        size: 20,
                        color: StudioTheme.colorModulation,
                      ),
                      tooltip: 'Import Patches (.json, .zptc, .syx)',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showImportDialog(context),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: StudioTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: StudioTheme.surfaceBorder),
                      ),
                      child: Text(
                        '${patches.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: StudioTheme.colorModulation,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  key: const Key('library_search_input'),
                  decoration: InputDecoration(
                    hintText: 'Search presets...',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                    suffixIcon: libraryController.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => libraryController.setSearchQuery(''),
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: (text) => libraryController.setSearchQuery(text),
                ),
              ),

              // Device Family Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: selectedFamily == null,
                      onSelected: (_) => libraryController.setDeviceFilter(null),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('MS-60B+'),
                      selected: selectedFamily == DeviceFamily.zoomMs60bPlus,
                      onSelected: (_) => libraryController.setDeviceFilter(DeviceFamily.zoomMs60bPlus),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Bass Pod Pro'),
                      selected: selectedFamily == DeviceFamily.line6BassPodPro,
                      onSelected: (_) => libraryController.setDeviceFilter(DeviceFamily.line6BassPodPro),
                    ),
                  ],
                ),
              ),
              const Divider(color: StudioTheme.surfaceBorder, height: 1),

              // Preset List
              Expanded(
                child: libraryController.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : patches.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                libraryController.searchQuery.isNotEmpty || selectedFamily != null
                                    ? 'No presets matching filters'
                                    : 'Library is empty',
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.separated(
                            key: const Key('preset_list_view'),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            itemCount: patches.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final patch = patches[index];
                              return _buildPatchCard(context, patch);
                            },
                          ),
              ),
            ],
          );
  }

  Widget _buildPatchCard(BuildContext context, Patch patch) {
    final isZoom = patch.deviceFamily.isZoomMsPlus;
    final deviceColor = isZoom ? StudioTheme.colorDynamics : StudioTheme.colorAmpCab;

    return Container(
      key: Key('preset_card_${patch.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patch Name & Device Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  patch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: deviceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: deviceColor, width: 0.8),
                ),
                child: Text(
                  patch.deviceFamily.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: deviceColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Author / Slot count
          Text(
            '${patch.slots.length} effect blocks${patch.author != null ? ' • by ${patch.author}' : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),

          // Tags
          if (patch.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: patch.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),

          // Actions: Load, Export, Delete
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Export JSON / SysEx
              IconButton(
                key: Key('export_patch_${patch.id}_button'),
                icon: const Icon(Icons.share, size: 16, color: Colors.grey),
                tooltip: 'Export JSON / SysEx',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _exportPatch(context, patch),
              ),
              const SizedBox(width: 12),

              // Delete
              IconButton(
                key: Key('delete_patch_${patch.id}_button'),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                tooltip: 'Delete Preset',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _confirmDelete(context, patch),
              ),
              const SizedBox(width: 12),

              // Load into Editor
              ElevatedButton(
                key: Key('load_patch_${patch.id}_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StudioTheme.colorModulation.withValues(alpha: 0.2),
                  foregroundColor: StudioTheme.colorModulation,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  libraryController.loadIntoEditor(patch, editorController);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Loaded "${patch.name}" into editor'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: const Text('Load', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => PatchImportDialog(
        libraryController: libraryController,
        editorController: editorController,
      ),
    );
  }

  Future<void> _exportPatch(BuildContext context, Patch patch) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => PatchExportDialog.patch(
        libraryController: libraryController,
        patch: patch,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Patch patch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: StudioTheme.surfaceElevated,
          title: const Text('Delete Preset?'),
          content: Text('Are you sure you want to delete "${patch.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await libraryController.deletePatch(patch.id);
    }
  }
}
