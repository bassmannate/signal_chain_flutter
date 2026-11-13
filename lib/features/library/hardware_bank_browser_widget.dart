import 'package:flutter/material.dart';

import '../../models/bank_slot_descriptor.dart';
import '../connection/device_connection_controller.dart';
import '../editor/patch_editor_controller.dart';
import '../editor/write_to_slot_dialog.dart';
import '../theme/studio_theme.dart';
import 'patch_export_dialog.dart';
import 'patch_library_controller.dart';

/// Responsive browser for the connected hardware's persistent memory bank slots (0–99).
///
/// Features bank synchronization, scrollable 100-slot listing, quick-load into editor buffer,
/// and slot write/overwrite actions.
class HardwareBankBrowserWidget extends StatefulWidget {
  final DeviceConnectionController connectionController;
  final PatchEditorController editorController;
  final PatchLibraryController? libraryController;
  final bool isPanel;

  const HardwareBankBrowserWidget({
    super.key,
    required this.connectionController,
    required this.editorController,
    this.libraryController,
    this.isPanel = true,
  });

  @override
  State<HardwareBankBrowserWidget> createState() => _HardwareBankBrowserWidgetState();
}

class _HardwareBankBrowserWidgetState extends State<HardwareBankBrowserWidget> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _loadingSlotIndex;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.connectionController,
        widget.editorController,
      ]),
      builder: (context, _) {
        final isConnected = widget.connectionController.isConnected;
        final isSyncing = widget.connectionController.isSyncingBank;
        final syncProgress = widget.connectionController.bankSyncProgress;
        final syncStatus = widget.connectionController.bankSyncStatus;
        final totalSlots = widget.connectionController.activeFamily.totalMemorySlots;

        final bankSlots = widget.connectionController.bankSlots.isNotEmpty
            ? widget.connectionController.bankSlots
            : List.generate(
                totalSlots,
                (i) => BankSlotDescriptor(
                  index: i,
                  name: 'Slot ${i.toString().padLeft(2, '0')}',
                  deviceFamily: widget.connectionController.activeFamily,
                  isLoaded: false,
                ),
              );

        final filteredSlots = bankSlots.where((slot) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return slot.name.toLowerCase().contains(q) ||
              slot.formattedSlotIndex.contains(q) ||
              slot.bankAndProgramNumber.contains(q);
        }).toList();

        final activeProg = widget.editorController.patch?.programNumber ??
            widget.connectionController.activeHardwareSlotIndex;

        return Container(
          width: widget.isPanel ? 340 : double.infinity,
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
              // Header
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.memory, size: 18, color: StudioTheme.colorFilterEq),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'HARDWARE BANK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.libraryController != null) ...[
                      IconButton(
                        key: const Key('export_hardware_bank_button'),
                        icon: const Icon(Icons.ios_share, size: 18, color: StudioTheme.colorFilterEq),
                        tooltip: 'Backup Loaded Bank',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: bankSlots.any((s) => s.patch != null)
                            ? () {
                                final loadedPatches = bankSlots
                                    .where((s) => s.patch != null)
                                    .map((s) => s.patch!)
                                    .toList();
                                showDialog<bool>(
                                  context: context,
                                  builder: (_) => PatchExportDialog.library(
                                    libraryController: widget.libraryController!,
                                    patches: loadedPatches,
                                    title: 'Backup Hardware Bank (${loadedPatches.length})',
                                    defaultLibraryName: 'hardware_bank_backup',
                                  ),
                                );
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (isSyncing)
                      IconButton(
                        key: const Key('cancel_bank_sync_button'),
                        icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                        tooltip: 'Cancel Sync',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => widget.connectionController.cancelBankSync(),
                      )
                    else
                      IconButton(
                        key: const Key('sync_device_bank_button'),
                        icon: const Icon(Icons.sync, size: 20, color: StudioTheme.colorFilterEq),
                        tooltip: isConnected
                            ? 'Sync Device Bank (0–99)'
                            : 'Connect device to sync bank',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: isConnected
                            ? () => widget.connectionController.syncDeviceBank()
                            : null,
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
                        '$totalSlots SLOTS',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: StudioTheme.colorFilterEq,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Sync Progress Indicator
              if (isSyncing) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        key: const Key('bank_sync_progress_bar'),
                        value: syncProgress > 0 ? syncProgress : null,
                        backgroundColor: StudioTheme.surfaceBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(StudioTheme.colorFilterEq),
                        minHeight: 4,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        syncStatus ?? 'Syncing hardware bank...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],

              // Search Filter Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: TextField(
                  key: const Key('hardware_bank_search_input'),
                  controller: _searchController,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Filter by name or slot #...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: StudioTheme.surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              const Divider(color: StudioTheme.surfaceBorder, height: 1),

              // Slots List
              Expanded(
                child: ListView.builder(
                  key: const Key('hardware_bank_slots_list'),
                  padding: const EdgeInsets.all(8),
                  itemCount: filteredSlots.length,
                  itemBuilder: (context, index) {
                    final slot = filteredSlots[index];
                    final isActive = activeProg != null && activeProg == slot.index;
                    final isLoadingThis = _loadingSlotIndex == slot.index;

                    return _buildSlotCard(
                      context,
                      slot: slot,
                      isActive: isActive,
                      isLoading: isLoadingThis,
                      isConnected: isConnected,
                    );
                  },
                ),
              ),

              // Bottom Write to Hardware Slot Action
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('write_active_to_hardware_button'),
                    icon: const Icon(Icons.save_alt, size: 16),
                    label: const Text('Write Active Patch to Slot...'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioTheme.colorModulation,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        builder: (_) => WriteToSlotDialog(
                          editorController: widget.editorController,
                          connectionController: widget.connectionController,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlotCard(
    BuildContext context, {
    required BankSlotDescriptor slot,
    required bool isActive,
    required bool isLoading,
    required bool isConnected,
  }) {
    return Card(
      key: Key('bank_slot_${slot.index}'),
      color: isActive ? StudioTheme.surfaceBorder : StudioTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: isActive ? StudioTheme.colorFilterEq : StudioTheme.surfaceBorder,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isConnected && !isLoading ? () => _loadSlot(slot.index) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Slot Index Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? StudioTheme.colorFilterEq.withValues(alpha: 0.2)
                      : StudioTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive ? StudioTheme.colorFilterEq : StudioTheme.surfaceBorder,
                  ),
                ),
                child: Text(
                  slot.formattedSlotIndex,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: isActive ? StudioTheme.colorFilterEq : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Bank-Program info (e.g. 1-1)
              Text(
                '(${slot.bankAndProgramNumber})',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),

              // Slot Name & Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: slot.isEmpty ? Colors.grey : Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isActive)
                      const Text(
                        'ACTIVE IN EDITOR',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: StudioTheme.colorFilterEq,
                        ),
                      ),
                  ],
                ),
              ),

              // Loading or Actions
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: StudioTheme.colorFilterEq),
                )
              else ...[
                // Load button
                IconButton(
                  key: Key('load_slot_${slot.index}_button'),
                  icon: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  tooltip: 'Load into Editor',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: isConnected ? () => _loadSlot(slot.index) : null,
                ),
                // Quick Write button
                IconButton(
                  key: Key('write_slot_${slot.index}_button'),
                  icon: const Icon(Icons.save, size: 16, color: StudioTheme.colorModulation),
                  tooltip: 'Write current patch to Slot ${slot.formattedSlotIndex}',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: isConnected ? () => _quickWriteToSlot(slot.index) : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadSlot(int slotIndex) async {
    setState(() => _loadingSlotIndex = slotIndex);
    try {
      await widget.editorController.loadPatchFromDeviceSlot(slotIndex);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded Hardware Slot $slotIndex into editor'),
            duration: const Duration(seconds: 1),
            backgroundColor: StudioTheme.surfaceElevated,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingSlotIndex = null);
      }
    }
  }

  Future<void> _quickWriteToSlot(int slotIndex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioTheme.surfaceElevated,
        title: const Text('Confirm Overwrite Slot', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          'Overwrite hardware slot ${slotIndex.toString().padLeft(2, '0')} with "${widget.editorController.patch?.name}"?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StudioTheme.colorModulation,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.editorController.savePatchToDeviceSlot(slotIndex);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully wrote patch to Slot $slotIndex!'),
            backgroundColor: StudioTheme.colorFilterEq,
          ),
        );
      }
    }
  }
}
