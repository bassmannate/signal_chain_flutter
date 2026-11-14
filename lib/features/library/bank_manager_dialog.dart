import 'package:flutter/material.dart';

import '../../models/bank_slot_descriptor.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../connection/device_connection_controller.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/responsive_layout.dart';
import '../theme/studio_theme.dart';
import 'bank_restore_dialog.dart';
import 'patch_library_controller.dart';
import 'save_copy_as_dialog.dart';

/// Drag payload representing a preset dragged from the local preset library.
class LibraryPatchDragPayload {
  final Patch patch;

  const LibraryPatchDragPayload(this.patch);
}

/// Drag payload representing a populated preset dragged from a hardware bank slot.
class HardwareSlotDragPayload {
  final BankSlotDescriptor slot;
  final Patch patch;

  const HardwareSlotDragPayload({
    required this.slot,
    required this.patch,
  });
}

/// Builds a [Draggable] on desktop or a [LongPressDraggable] on touch devices so
/// vertical scrolling inside library and bank lists never collides with drag gestures.
Widget buildAdaptiveDraggable<T extends Object>(
  BuildContext context, {
  required T data,
  required Widget feedback,
  required Widget child,
  Widget? childWhenDragging,
}) {
  if (ResponsiveLayoutMetrics.isTouchPlatform(context)) {
    return LongPressDraggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }
  return Draggable<T>(
    data: data,
    feedback: feedback,
    childWhenDragging: childWhenDragging,
    child: child,
  );
}

/// Builds compact floating drag feedback styled consistently for preset and slot cards.
Widget buildPresetDragFeedback(String title, String subtitle) {
  return Material(
    color: Colors.transparent,
    child: Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: StudioTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.colorModulation, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: StudioTheme.colorModulation),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Hard-blocks writing a patch built for an incompatible hardware generation
/// onto the connected hardware target.
Future<void> showGenerationIncompatibleDialog(
  BuildContext context, {
  required Patch patch,
  required DeviceFamily targetFamily,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('generation_incompatible_dialog'),
      backgroundColor: StudioTheme.surfaceElevated,
      title: const Row(
        children: [
          Icon(Icons.block, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Incompatible Hardware Generation',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
      content: Text(
        '"${patch.name}" belongs to ${patch.deviceFamily.displayName} '
        '(${patch.deviceFamily.generation.displayName}), which is a different hardware '
        'generation from the connected ${targetFamily.displayName} '
        '(${targetFamily.generation.displayName}).\n\n'
        'Patches from a different hardware generation cannot be written to this device.',
        style: const TextStyle(fontSize: 13, color: Colors.white70),
      ),
      actions: [
        ElevatedButton(
          key: const Key('generation_incompatible_ok_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Prompts the user before writing a patch built for a different [DeviceFamily]
/// within the same [DeviceGeneration] onto the connected hardware target.
Future<bool> confirmDeviceMismatchDrop(
  BuildContext context, {
  required Patch patch,
  required DeviceFamily targetFamily,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('device_mismatch_drop_dialog'),
      backgroundColor: StudioTheme.surfaceElevated,
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Device Family Mismatch',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
      content: Text(
        '"${patch.name}" targets ${patch.deviceFamily.displayName}, '
        'but the connected pedal is ${targetFamily.displayName} '
        '(same generation: ${targetFamily.generation.displayName}).\n\n'
        'Write it to hardware anyway? Unsupported effects may be skipped or mapped differently.',
        style: const TextStyle(fontSize: 13, color: Colors.white70),
      ),
      actions: [
        TextButton(
          key: const Key('mismatch_drop_cancel_button'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          key: const Key('mismatch_drop_confirm_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Write Anyway'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Handles dropping a [LibraryPatchDragPayload] onto hardware slot [slotIndex],
/// hard-blocking cross-generation presets, prompting on same-generation model mismatch,
/// and writing directly to hardware.
Future<bool> handleLibraryPatchDropToSlot(
  BuildContext context, {
  required LibraryPatchDragPayload payload,
  required int slotIndex,
  required DeviceConnectionController connectionController,
  required PatchEditorController editorController,
}) async {
  final targetFamily = connectionController.activeFamily;
  if (targetFamily != DeviceFamily.unknown && payload.patch.deviceFamily != targetFamily) {
    if (payload.patch.deviceFamily != DeviceFamily.unknown &&
        !payload.patch.deviceFamily.isSameGeneration(targetFamily)) {
      editorController.reportCrossGenerationWriteError(
        patchDevice: payload.patch.deviceFamily,
        targetDevice: targetFamily,
      );
      if (context.mounted) {
        await showGenerationIncompatibleDialog(
          context,
          patch: payload.patch,
          targetFamily: targetFamily,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Blocked: Cannot write ${payload.patch.deviceFamily.displayName} patch to ${targetFamily.displayName}.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }

    final proceed = await confirmDeviceMismatchDrop(
      context,
      patch: payload.patch,
      targetFamily: targetFamily,
    );
    if (!proceed) return false;
  }

  await editorController.savePatchToDeviceSlot(slotIndex, payload.patch);
  final ok = editorController.errorMessage == null;
  if (!context.mounted) return ok;

  final padded = slotIndex.toString().padLeft(2, '0');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? 'Wrote "${payload.patch.name}" to hardware slot #$padded'
            : (editorController.errorMessage ?? 'Failed to write to hardware slot #$padded'),
      ),
      backgroundColor: ok ? StudioTheme.surfaceElevated : Colors.redAccent,
    ),
  );
  return ok;
}

/// Handles dropping a [HardwareSlotDragPayload] into [libraryController].
Future<Patch> handleHardwareSlotDropToLibrary(
  BuildContext context, {
  required HardwareSlotDragPayload payload,
  required PatchLibraryController libraryController,
}) async {
  final saved = await libraryController.saveHardwareSlotToLibrary(
    payload.patch,
    slotIndex: payload.slot.index,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved hardware slot #${payload.slot.formattedSlotIndex} as "${saved.name}" in library',
        ),
        backgroundColor: StudioTheme.surfaceElevated,
      ),
    );
  }
  return saved;
}

/// Prompts with [SaveCopyAsDialog] and duplicates [source] in [libraryController].
Future<Patch?> promptAndDuplicateLibraryPatch(
  BuildContext context, {
  required PatchLibraryController libraryController,
  required Patch source,
}) async {
  final newName = await SaveCopyAsDialog.show(
    context,
    initialName: '${source.name} Copy',
    title: 'Duplicate Preset As...',
  );
  if (newName == null) return null;

  final copy = await libraryController.duplicatePatch(source, newName: newName);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved copy "${copy.name}" to library'),
        backgroundColor: StudioTheme.surfaceElevated,
      ),
    );
  }
  return copy;
}

/// Side-by-side drag-and-drop workspace connecting the local preset library with
/// connected hardware bank slots, including family/tag filtering and batch restore.
class BankManagerDialog extends StatefulWidget {
  final PatchLibraryController libraryController;
  final PatchEditorController editorController;
  final DeviceConnectionController connectionController;
  final Duration restoreInterSlotDelay;

  const BankManagerDialog({
    super.key,
    required this.libraryController,
    required this.editorController,
    required this.connectionController,
    this.restoreInterSlotDelay = const Duration(milliseconds: 10),
  });

  static Future<void> show(
    BuildContext context, {
    required PatchLibraryController libraryController,
    required PatchEditorController editorController,
    required DeviceConnectionController connectionController,
    Duration restoreInterSlotDelay = const Duration(milliseconds: 10),
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BankManagerDialog(
        libraryController: libraryController,
        editorController: editorController,
        connectionController: connectionController,
        restoreInterSlotDelay: restoreInterSlotDelay,
      ),
    );
  }

  @override
  State<BankManagerDialog> createState() => _BankManagerDialogState();
}

class _BankManagerDialogState extends State<BankManagerDialog> {
  final TextEditingController _librarySearchController = TextEditingController();
  final TextEditingController _slotSearchController = TextEditingController();
  String _slotSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _librarySearchController.text = widget.libraryController.searchQuery;
  }

  @override
  void dispose() {
    _librarySearchController.dispose();
    _slotSearchController.dispose();
    super.dispose();
  }

  List<BankSlotDescriptor> _filterSlots(List<BankSlotDescriptor> slots) {
    final query = _slotSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return slots;
    return slots.where((slot) {
      return slot.name.toLowerCase().contains(query) ||
          slot.formattedSlotIndex.contains(query) ||
          slot.bankAndProgramNumber.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final maxWidth = (media.width * 0.92).clamp(320.0, 1080.0);
    final maxHeight = (media.height * 0.88).clamp(340.0, 760.0);

    return Dialog(
      backgroundColor: StudioTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.libraryController,
            widget.editorController,
            widget.connectionController,
          ]),
          builder: (context, _) {
            return Column(
              children: [
                _buildTopBar(context),
                if (widget.editorController.isRestoringBank)
                  _buildRestoreProgressBanner(context),
                const Divider(color: StudioTheme.surfaceBorder, height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 640;
                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(child: _buildLocalLibraryPane(context)),
                            const VerticalDivider(
                              color: StudioTheme.surfaceBorder,
                              width: 1,
                            ),
                            Expanded(child: _buildHardwareBankPane(context)),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(child: _buildLocalLibraryPane(context)),
                          const Divider(
                            color: StudioTheme.surfaceBorder,
                            height: 1,
                          ),
                          Expanded(child: _buildHardwareBankPane(context)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final activeFamily = widget.connectionController.activeFamily;
    final isSyncing = widget.connectionController.isSyncingBank;
    final isConnected = widget.connectionController.isConnected;
    final isRestoring = widget.editorController.isRestoringBank;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz, color: StudioTheme.colorFilterEq, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Bank Manager',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Drag presets ↔ hardware slots (${activeFamily.displayName})',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('bank_manager_restore_bank_button'),
                icon: const Icon(Icons.playlist_play, size: 16),
                label: const Text('Restore Bank...', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: StudioTheme.colorFilterEq,
                  side: const BorderSide(color: StudioTheme.colorFilterEq),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: (!isConnected || isRestoring)
                    ? null
                    : () => BankRestoreDialog.show(
                          context,
                          libraryController: widget.libraryController,
                          editorController: widget.editorController,
                          connectionController: widget.connectionController,
                          interSlotDelay: widget.restoreInterSlotDelay,
                        ),
              ),
              OutlinedButton.icon(
                key: const Key('bank_manager_sync_button'),
                icon: Icon(
                  isSyncing ? Icons.stop : Icons.sync,
                  size: 16,
                ),
                label: Text(
                  isSyncing ? 'Cancel Sync' : 'Sync Bank',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      isSyncing ? Colors.orangeAccent : StudioTheme.colorModulation,
                  side: BorderSide(
                    color: isSyncing
                        ? Colors.orangeAccent
                        : StudioTheme.colorModulation,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: !isConnected
                    ? null
                    : () {
                        if (isSyncing) {
                          widget.connectionController.cancelBankSync();
                        } else {
                          widget.connectionController.syncDeviceBank();
                        }
                      },
              ),
              IconButton(
                key: const Key('bank_manager_close_button'),
                icon: const Icon(Icons.close, color: Colors.grey),
                tooltip: 'Close Bank Manager',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRestoreProgressBanner(BuildContext context) {
    final editor = widget.editorController;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: StudioTheme.surfaceElevated,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  editor.bankRestoreStatus ?? 'Restoring hardware slots...',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  key: const Key('bank_manager_restore_progress_bar'),
                  value: editor.bankRestoreProgress > 0
                      ? editor.bankRestoreProgress
                      : null,
                  backgroundColor: StudioTheme.surfaceBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    StudioTheme.colorFilterEq,
                  ),
                  minHeight: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            key: const Key('bank_manager_cancel_restore_button'),
            icon: const Icon(Icons.stop, size: 15, color: Colors.orangeAccent),
            label: const Text(
              'Cancel',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
            onPressed: editor.cancelBankRestore,
          ),
        ],
      ),
    );
  }

  Widget _buildLocalLibraryPane(BuildContext context) {
    final patches = widget.libraryController.patches;
    final selectedFamily = widget.libraryController.deviceFilter;
    final tags = widget.libraryController.availableTags;
    final selectedTags = widget.libraryController.selectedTags;

    return DragTarget<HardwareSlotDragPayload>(
      key: const Key('bank_manager_library_drop_zone'),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => handleHardwareSlotDropToLibrary(
        context,
        payload: details.data,
        libraryController: widget.libraryController,
      ),
      builder: (context, candidateData, _) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isHovering
                ? StudioTheme.colorModulation.withValues(alpha: 0.08)
                : Colors.transparent,
            border: isHovering
                ? Border.all(color: StudioTheme.colorModulation, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    const Text(
                      'LOCAL PRESETS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: StudioTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: StudioTheme.surfaceBorder),
                      ),
                      child: Text(
                        '${patches.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              if (isHovering)
                Container(
                  key: const Key('library_drop_hover_banner'),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: StudioTheme.colorModulation.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: StudioTheme.colorModulation),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.save_alt, size: 15, color: StudioTheme.colorModulation),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Drop hardware slot here to save a copy in Local Library',
                          style: TextStyle(
                            fontSize: 11,
                            color: StudioTheme.colorModulation,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  key: const Key('bank_manager_library_search_input'),
                  controller: _librarySearchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search local presets...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: StudioTheme.surfaceElevated,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: StudioTheme.surfaceBorder),
                    ),
                  ),
                  onChanged: widget.libraryController.setSearchQuery,
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: selectedFamily == null,
                      onSelected: (_) => widget.libraryController.setDeviceFilter(null),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('MS-60B+'),
                      selected: selectedFamily == DeviceFamily.zoomMs60bPlus,
                      onSelected: (_) => widget.libraryController
                          .setDeviceFilter(DeviceFamily.zoomMs60bPlus),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('Bass Pod Pro'),
                      selected: selectedFamily == DeviceFamily.line6BassPodPro,
                      onSelected: (_) => widget.libraryController
                          .setDeviceFilter(DeviceFamily.line6BassPodPro),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      for (final tag in tags) ...[
                        FilterChip(
                          key: Key('bank_manager_tag_chip_$tag'),
                          label: Text('#$tag'),
                          selected: selectedTags.contains(tag),
                          onSelected: (_) => widget.libraryController.toggleTag(tag),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ],
                ),
              ),
              const Divider(color: StudioTheme.surfaceBorder, height: 1),
              Expanded(
                child: patches.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching local presets',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: patches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) =>
                            _buildLocalPresetDragCard(context, patches[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocalPresetDragCard(BuildContext context, Patch patch) {
    final activeFamily = widget.connectionController.activeFamily;
    final isCrossGen = activeFamily != DeviceFamily.unknown &&
        patch.deviceFamily != DeviceFamily.unknown &&
        !patch.deviceFamily.isSameGeneration(activeFamily);
    final isMismatch = !isCrossGen &&
        activeFamily != DeviceFamily.unknown &&
        patch.deviceFamily != activeFamily;

    final card = Card(
      key: Key('bank_manager_preset_card_${patch.id}'),
      color: StudioTheme.surfaceElevated,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: isCrossGen
              ? Colors.redAccent.withValues(alpha: 0.55)
              : isMismatch
                  ? Colors.orangeAccent.withValues(alpha: 0.45)
                  : StudioTheme.surfaceBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCrossGen
                        ? '${patch.deviceFamily.displayName} • Incompatible Gen'
                        : '${patch.deviceFamily.displayName} • ${patch.slots.length} fx',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isCrossGen
                          ? Colors.redAccent
                          : isMismatch
                              ? Colors.orangeAccent
                              : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('bank_manager_duplicate_patch_${patch.id}_button'),
              icon: const Icon(Icons.copy, size: 15, color: Colors.grey),
              tooltip: 'Save Copy As...',
              visualDensity: VisualDensity.compact,
              onPressed: () => promptAndDuplicateLibraryPatch(
                context,
                libraryController: widget.libraryController,
                source: patch,
              ),
            ),
          ],
        ),
      ),
    );

    return buildAdaptiveDraggable<LibraryPatchDragPayload>(
      context,
      data: LibraryPatchDragPayload(patch),
      feedback: buildPresetDragFeedback(
        patch.name,
        patch.deviceFamily.displayName,
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );
  }

  Widget _buildHardwareBankPane(BuildContext context) {
    final slots = _filterSlots(widget.connectionController.bankSlots);
    final activeSlotIndex = widget.connectionController.activeHardwareSlotIndex;
    final isConnected = widget.connectionController.isConnected;
    final activeFamily = widget.connectionController.activeFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              const Text(
                'HARDWARE BANK SLOTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: StudioTheme.colorFilterEq,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: StudioTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Text(
                  '${slots.length}',
                  style: const TextStyle(fontSize: 10, color: StudioTheme.colorFilterEq),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            key: const Key('bank_manager_slot_search_input'),
            controller: _slotSearchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Filter hardware slots...',
              hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
              prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: StudioTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: StudioTheme.surfaceBorder),
              ),
            ),
            onChanged: (val) => setState(() => _slotSearchQuery = val),
          ),
        ),
        const Divider(color: StudioTheme.surfaceBorder, height: 1),
        Expanded(
          child: slots.isEmpty
              ? const Center(
                  child: Text(
                    'No matching hardware slots',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: slots.length,
                  itemBuilder: (context, index) => _buildHardwareSlotTargetCard(
                    context,
                    slot: slots[index],
                    isActive: activeSlotIndex == slots[index].index,
                    isConnected: isConnected,
                    activeFamily: activeFamily,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHardwareSlotTargetCard(
    BuildContext context, {
    required BankSlotDescriptor slot,
    required bool isActive,
    required bool isConnected,
    required DeviceFamily activeFamily,
  }) {
    final slotPatch = slot.patch;

    return DragTarget<LibraryPatchDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => handleLibraryPatchDropToSlot(
        context,
        payload: details.data,
        slotIndex: slot.index,
        connectionController: widget.connectionController,
        editorController: widget.editorController,
      ),
      builder: (context, candidateData, _) {
        final hoverPayload =
            candidateData.isNotEmpty ? candidateData.first : null;
        final isHovering = hoverPayload != null;
        final isCrossGenHover = isHovering &&
            activeFamily != DeviceFamily.unknown &&
            hoverPayload.patch.deviceFamily != DeviceFamily.unknown &&
            !hoverPayload.patch.deviceFamily.isSameGeneration(activeFamily);
        final isMismatchHover = isHovering &&
            !isCrossGenHover &&
            activeFamily != DeviceFamily.unknown &&
            hoverPayload.patch.deviceFamily != activeFamily;

        final borderColor = isCrossGenHover
            ? Colors.redAccent
            : isMismatchHover
                ? Colors.orangeAccent
                : isHovering
                    ? StudioTheme.colorFilterEq
                    : isActive
                        ? StudioTheme.colorFilterEq
                        : StudioTheme.surfaceBorder;

        final card = Card(
          key: Key('bank_manager_slot_${slot.index}'),
          color: isHovering
              ? (isCrossGenHover
                  ? Colors.redAccent.withValues(alpha: 0.14)
                  : isMismatchHover
                      ? Colors.orangeAccent.withValues(alpha: 0.14)
                      : StudioTheme.colorFilterEq.withValues(alpha: 0.14))
              : isActive
                  ? StudioTheme.surfaceBorder
                  : StudioTheme.surfaceElevated,
          margin: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: borderColor,
              width: (isHovering || isActive) ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: StudioTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive
                              ? StudioTheme.colorFilterEq
                              : StudioTheme.surfaceBorder,
                        ),
                      ),
                      child: Text(
                        '#${slot.formattedSlotIndex}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? StudioTheme.colorFilterEq
                              : Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: slot.isEmpty ? Colors.grey : Colors.white,
                              fontStyle:
                                  slot.isEmpty ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          Text(
                            slotPatch != null
                                ? '${slotPatch.slots.length} fx • Drag to Local Presets'
                                : 'Bank ${slot.bankAndProgramNumber} • Drop preset here',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (slotPatch != null && !slot.isEmpty)
                      const Icon(Icons.drag_indicator, size: 15, color: Colors.grey),
                    IconButton(
                      icon: const Icon(
                        Icons.play_arrow,
                        size: 16,
                        color: StudioTheme.colorFilterEq,
                      ),
                      tooltip: 'Load into Editor',
                      visualDensity: VisualDensity.compact,
                      onPressed: isConnected
                          ? () => widget.editorController.loadPatchFromDeviceSlot(slot.index)
                          : null,
                    ),
                  ],
                ),
                if (isCrossGenHover || isMismatchHover)
                  Padding(
                    key: Key('slot_mismatch_warning_${slot.index}'),
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      isCrossGenHover
                          ? 'Blocked (incompatible gen): ${hoverPayload.patch.deviceFamily.displayName} → ${activeFamily.displayName}'
                          : 'Device mismatch: ${hoverPayload.patch.deviceFamily.displayName} → ${activeFamily.displayName}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isCrossGenHover ? Colors.redAccent : Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        if (slotPatch == null || slot.isEmpty) {
          return card;
        }
        return buildAdaptiveDraggable<HardwareSlotDragPayload>(
          context,
          data: HardwareSlotDragPayload(slot: slot, patch: slotPatch),
          feedback: buildPresetDragFeedback(
            slotPatch.name,
            'Hardware Slot #${slot.formattedSlotIndex}',
          ),
          childWhenDragging: Opacity(opacity: 0.45, child: card),
          child: card,
        );
      },
    );
  }
}

