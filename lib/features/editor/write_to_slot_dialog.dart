import 'package:flutter/material.dart';

import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../models/patch_diff.dart';
import '../connection/device_connection_controller.dart';
import '../theme/studio_theme.dart';
import 'patch_diff_dialog.dart';
import 'patch_editor_controller.dart';

/// Modal dialog allowing the user to select a hardware persistent memory slot (0–99)
/// and save the active editor patch (or [patchOverride]) into that slot.
class WriteToSlotDialog extends StatefulWidget {
  final PatchEditorController editorController;
  final DeviceConnectionController connectionController;
  final Patch? patchOverride;

  const WriteToSlotDialog({
    super.key,
    required this.editorController,
    required this.connectionController,
    this.patchOverride,
  });

  @override
  State<WriteToSlotDialog> createState() => _WriteToSlotDialogState();
}

class _WriteToSlotDialogState extends State<WriteToSlotDialog> {
  late int _selectedSlot;
  bool _isSaving = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final totalSlots = widget.connectionController.activeFamily.totalMemorySlots;
    final targetPatch = widget.patchOverride ?? widget.editorController.patch;
    final currentProg = targetPatch?.programNumber ??
        widget.connectionController.activeHardwareSlotIndex;
    _selectedSlot = currentProg != null && currentProg >= 0 && currentProg < totalSlots
        ? currentProg
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final patch = widget.patchOverride ?? widget.editorController.patch;
    final targetFamily = widget.connectionController.activeFamily;
    final totalSlots = targetFamily.totalMemorySlots;
    final bankSlots = widget.connectionController.bankSlots;

    final isCrossGeneration = patch != null &&
        targetFamily != DeviceFamily.unknown &&
        patch.deviceFamily != DeviceFamily.unknown &&
        !patch.deviceFamily.isSameGeneration(targetFamily);
    final isSameGenCrossModel = patch != null &&
        !isCrossGeneration &&
        targetFamily != DeviceFamily.unknown &&
        patch.deviceFamily != targetFamily;

    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return AlertDialog(
      backgroundColor: StudioTheme.surfaceElevated,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: 16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      title: Row(
        children: [
          const Icon(Icons.save_alt, color: StudioTheme.colorModulation, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Write to Hardware Slot',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (patch != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StudioTheme.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note, color: Colors.grey, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TARGET PRESET',
                              style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              patch.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: StudioTheme.colorModulation,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${patch.slots.length} effects',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isCrossGeneration) ...[
                Container(
                  key: const Key('write_slot_generation_error_banner'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.block, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Incompatible hardware generation: "${patch.deviceFamily.displayName}" (${patch.deviceFamily.generation.displayName}) cannot be written to ${targetFamily.displayName} (${targetFamily.generation.displayName}).',
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (isSameGenCrossModel) ...[
                Container(
                  key: const Key('write_slot_model_warning_banner'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orangeAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Same-generation model mismatch: "${patch.deviceFamily.displayName}" will be written to ${targetFamily.displayName}. Unsupported DSP blocks may be mapped differently.',
                          style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Select Destination Slot (0–${totalSlots - 1}):',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    key: const Key('write_slot_dropdown'),
                    value: _selectedSlot,
                    isExpanded: true,
                    dropdownColor: StudioTheme.surfaceElevated,
                    icon: const Icon(Icons.arrow_drop_down, color: StudioTheme.colorModulation),
                    items: List.generate(totalSlots, (index) {
                      final bank = (index ~/ 10) + 1;
                      final prog = (index % 10) + 1;
                      String slotDesc = '';
                      if (index < bankSlots.length && bankSlots[index].isLoaded) {
                        slotDesc = ' - ${bankSlots[index].name}';
                      }
                      return DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          'Slot ${index.toString().padLeft(2, '0')} ($bank-$prog)$slotDesc',
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSlot = val);
                      }
                    },
                  ),
                ),
              ),
              if (patch != null &&
                  _selectedSlot >= 0 &&
                  _selectedSlot < bankSlots.length &&
                  bankSlots[_selectedSlot].patch != null) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final destPatch = bankSlots[_selectedSlot].patch!;
                    final diff = PatchDiff.compute(destPatch, patch);
                    return Container(
                      key: const Key('write_slot_diff_banner'),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: StudioTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: diff.hasChanges
                              ? StudioTheme.colorFilterEq.withValues(alpha: 0.5)
                              : StudioTheme.surfaceBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.compare_arrows,
                            size: 16,
                            color: diff.hasChanges
                                ? StudioTheme.colorFilterEq
                                : StudioTheme.colorDynamics,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vs. Slot ${_selectedSlot.toString().padLeft(2, '0')}: ${diff.summaryLabel}',
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                          ),
                          TextButton(
                            key: const Key('write_slot_view_diff_button'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => PatchDiffDialog.show(
                              context,
                              baseLabel: 'Slot #${_selectedSlot.toString().padLeft(2, '0')}',
                              targetLabel: 'Editor',
                              diff: diff,
                            ),
                            child: const Text('View Diff', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _statusMessage!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel_write_slot_button'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          key: const Key('confirm_write_slot_button'),
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.save, size: 16),
          label: Text(_isSaving ? 'Writing...' : 'Write to Slot $_selectedSlot'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioTheme.colorModulation,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: (_isSaving || isCrossGeneration || patch == null) ? null : _handleWrite,
        ),
      ],
    );
  }

  Future<void> _handleWrite() async {
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      await widget.editorController.savePatchToDeviceSlot(
        _selectedSlot,
        widget.patchOverride,
      );
      if (mounted) {
        if (widget.editorController.errorMessage != null) {
          setState(() {
            _isSaving = false;
            _statusMessage = widget.editorController.errorMessage;
          });
          return;
        }
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Patch successfully saved to Hardware Slot $_selectedSlot!'),
            backgroundColor: StudioTheme.colorFilterEq,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _statusMessage = 'Failed to save to slot: $e';
        });
      }
    }
  }
}
