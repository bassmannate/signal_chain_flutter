import 'package:flutter/material.dart';

import '../connection/device_connection_controller.dart';
import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';

/// Modal dialog allowing the user to select a hardware persistent memory slot (0–99)
/// and save the current active editor patch into that slot.
class WriteToSlotDialog extends StatefulWidget {
  final PatchEditorController editorController;
  final DeviceConnectionController connectionController;

  const WriteToSlotDialog({
    super.key,
    required this.editorController,
    required this.connectionController,
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
    final currentProg = widget.editorController.patch?.programNumber ??
        widget.connectionController.activeHardwareSlotIndex;
    _selectedSlot = currentProg != null && currentProg >= 0 && currentProg < totalSlots
        ? currentProg
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final patch = widget.editorController.patch;
    final totalSlots = widget.connectionController.activeFamily.totalMemorySlots;
    final bankSlots = widget.connectionController.bankSlots;

    return AlertDialog(
      backgroundColor: StudioTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      title: Row(
        children: [
          const Icon(Icons.save_alt, color: StudioTheme.colorModulation, size: 22),
          const SizedBox(width: 8),
          const Text(
            'Write to Hardware Slot',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: StudioTheme.colorModulation,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${patch.slots.length} effects',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Select Destination Slot (0–99):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
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
          onPressed: _isSaving ? null : _handleWrite,
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
      await widget.editorController.savePatchToDeviceSlot(_selectedSlot);
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
