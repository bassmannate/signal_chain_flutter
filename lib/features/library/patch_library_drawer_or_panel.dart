import 'package:flutter/material.dart';

import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/studio_theme.dart';
import 'patch_library_controller.dart';

/// Responsive preset library browser showing search, device filters, tags,
/// and patch cards with load, export, and delete capabilities.
class PatchLibraryDrawerOrPanel extends StatelessWidget {
  final PatchLibraryController libraryController;
  final PatchEditorController editorController;
  final bool isPanel; // true if side panel, false if in drawer / bottom sheet

  const PatchLibraryDrawerOrPanel({
    super.key,
    required this.libraryController,
    required this.editorController,
    this.isPanel = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: libraryController,
      builder: (context, _) {
        final patches = libraryController.patches;
        final selectedFamily = libraryController.deviceFilter;

        return Container(
          width: isPanel ? 340 : double.infinity,
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            border: isPanel
                ? const Border(
                    left: BorderSide(color: StudioTheme.surfaceBorder, width: 1),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.library_music, size: 20, color: StudioTheme.colorModulation),
                    const SizedBox(width: 8),
                    const Text(
                      'PRESET LIBRARY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
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
          ),
        );
      },
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
              // Export JSON
              IconButton(
                key: Key('export_patch_${patch.id}_button'),
                icon: const Icon(Icons.share, size: 16, color: Colors.grey),
                tooltip: 'Export JSON',
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

  Future<void> _exportPatch(BuildContext context, Patch patch) async {
    final jsonStr = await libraryController.exportPatchToJson(patch);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: StudioTheme.surfaceElevated,
          title: Text('Export JSON: ${patch.name}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: SelectableText(
                jsonStr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
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

