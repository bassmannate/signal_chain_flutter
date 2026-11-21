import 'package:flutter/material.dart';

import '../connection/device_connection_controller.dart';
import '../library/patch_library_controller.dart';
import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';
import 'write_to_slot_dialog.dart';

/// Outcome of prompting the user about unsaved editor edits.
enum UnsavedChangesResolution { saved, discarded, cancelled }

enum _UnsavedDialogChoice { cancel, discard, saveLibrary, savePedal }

/// Prompts the user to save or discard unsaved edits when [editorController.isDirty]
/// is true.
///
/// Immediately returns `true` when there are no unsaved edits (or no active patch).
/// Returns `true` if the user discards or successfully saves the edits, and `false`
/// if the user cancels or if saving fails.
Future<bool> confirmDiscardOrSaveUnsavedChanges({
  required BuildContext context,
  required PatchEditorController editorController,
  required PatchLibraryController libraryController,
  required DeviceConnectionController connectionController,
  String? actionDescription,
}) async {
  final resolution = await resolveUnsavedChanges(
    context: context,
    editorController: editorController,
    libraryController: libraryController,
    connectionController: connectionController,
    actionDescription: actionDescription,
  );
  return resolution != UnsavedChangesResolution.cancelled;
}

/// Prompts the user to save, discard, or cancel when [editorController.isDirty]
/// is true and returns the resulting [UnsavedChangesResolution].
Future<UnsavedChangesResolution> resolveUnsavedChanges({
  required BuildContext context,
  required PatchEditorController editorController,
  required PatchLibraryController libraryController,
  required DeviceConnectionController connectionController,
  String? actionDescription,
}) async {
  final currentPatch = editorController.patch;
  if (!editorController.isDirty || currentPatch == null) {
    return UnsavedChangesResolution.discarded;
  }

  final isConnected = connectionController.isConnected;
  final trimmedAction = actionDescription?.trim();
  final promptSuffix = (trimmedAction != null && trimmedAction.isNotEmpty)
      ? 'before you $trimmedAction'
      : 'before continuing';

  final choice = await showDialog<_UnsavedDialogChoice>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      key: const Key('unsaved_changes_dialog'),
      backgroundColor: StudioTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      title: const Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: StudioTheme.colorDirty,
            size: 22,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Unsaved Changes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(
          '"${currentPatch.name}" has unsaved edits.\n\n'
          'Would you like to save or discard your changes $promptSuffix?',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
      ),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 8,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          key: const Key('unsaved_cancel_button'),
          onPressed: () => Navigator.of(ctx).pop(_UnsavedDialogChoice.cancel),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          key: const Key('unsaved_discard_button'),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(ctx).pop(_UnsavedDialogChoice.discard),
          child: const Text('Discard'),
        ),
        OutlinedButton.icon(
          key: const Key('unsaved_save_library_button'),
          icon: const Icon(Icons.bookmark_add, size: 16),
          label: const Text('Save to Library'),
          style: OutlinedButton.styleFrom(
            foregroundColor: StudioTheme.colorModulation,
            side: const BorderSide(color: StudioTheme.colorModulation),
          ),
          onPressed: () =>
              Navigator.of(ctx).pop(_UnsavedDialogChoice.saveLibrary),
        ),
        if (isConnected)
          ElevatedButton.icon(
            key: const Key('unsaved_save_pedal_button'),
            icon: const Icon(Icons.save_alt, size: 16),
            label: const Text('Save to Pedal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: StudioTheme.colorModulation,
              foregroundColor: Colors.black,
            ),
            onPressed: () =>
                Navigator.of(ctx).pop(_UnsavedDialogChoice.savePedal),
          ),
      ],
    ),
  );

  switch (choice) {
    case null:
    case _UnsavedDialogChoice.cancel:
      return UnsavedChangesResolution.cancelled;
    case _UnsavedDialogChoice.discard:
      return UnsavedChangesResolution.discarded;
    case _UnsavedDialogChoice.saveLibrary:
      try {
        await libraryController.savePatch(currentPatch);
        editorController.markSaved();
        return UnsavedChangesResolution.saved;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('Failed to save to library: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return UnsavedChangesResolution.cancelled;
      }
    case _UnsavedDialogChoice.savePedal:
      final targetSlot = currentPatch.programNumber;
      final totalSlots = connectionController.activeFamily.totalMemorySlots;
      final hasValidSlot =
          targetSlot != null && targetSlot >= 0 && targetSlot < totalSlots;

      if (hasValidSlot) {
        try {
          await editorController.savePatchToDeviceSlot(targetSlot);
          if (editorController.errorMessage != null || editorController.isDirty) {
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(
                    editorController.errorMessage ??
                        'Failed to save patch to hardware slot $targetSlot.',
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            return UnsavedChangesResolution.cancelled;
          }
          return UnsavedChangesResolution.saved;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text('Failed to save to pedal: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return UnsavedChangesResolution.cancelled;
        }
      }

      if (!context.mounted) {
        return UnsavedChangesResolution.cancelled;
      }
      final wrote = await showDialog<bool>(
        context: context,
        builder: (_) => WriteToSlotDialog(
          editorController: editorController,
          connectionController: connectionController,
        ),
      );
      if (wrote == true && !editorController.isDirty) {
        return UnsavedChangesResolution.saved;
      }
      return UnsavedChangesResolution.cancelled;
  }
}
