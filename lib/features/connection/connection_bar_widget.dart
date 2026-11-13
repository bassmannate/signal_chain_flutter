import 'package:flutter/material.dart';

import '../../core/midi/midi_port_descriptor.dart';
import '../../models/device_family.dart';
import '../editor/patch_editor_controller.dart';
import '../library/patch_library_controller.dart';
import '../setlist/setlist_controller.dart';
import '../theme/studio_theme.dart';
import 'device_connection_controller.dart';

/// Top studio toolbar displaying MIDI connection state, port picker,
/// device family selector, hardware sync controls, and library quick actions.
class ConnectionBarWidget extends StatelessWidget {
  final DeviceConnectionController connectionController;
  final PatchEditorController editorController;
  final PatchLibraryController libraryController;
  final SetlistController? setlistController;
  final VoidCallback? onToggleLibrary;

  const ConnectionBarWidget({
    super.key,
    required this.connectionController,
    required this.editorController,
    required this.libraryController,
    this.setlistController,
    this.onToggleLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        connectionController,
        editorController,
        ?setlistController,
      ]),
      builder: (context, _) {
        final isConnected = connectionController.isConnected;
        final selectedPort = connectionController.connectedPort;
        final availablePorts = connectionController.availablePorts;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;

            final refreshButton = IconButton(
              icon: connectionController.isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
              tooltip: 'Refresh MIDI Ports',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              onPressed: connectionController.isScanning
                  ? null
                  : () => connectionController.refreshPorts(),
            );

            final libraryButton = onToggleLibrary != null
                ? IconButton(
                    key: const Key('toggle_library_button'),
                    icon: const Icon(Icons.folder_special_outlined),
                    tooltip: 'Toggle Preset Library',
                    constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                    onPressed: onToggleLibrary,
                  )
                : null;

            final deviceSelector = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Device:',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(width: 6),
                DropdownButton<DeviceFamily>(
                  value: connectionController.activeFamily,
                  dropdownColor: StudioTheme.surfaceElevated,
                  underline: const SizedBox.shrink(),
                  isDense: isCompact,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: DeviceFamily.zoomMs60bPlus,
                      child: Text('Zoom MS-60B+'),
                    ),
                    DropdownMenuItem(
                      value: DeviceFamily.zoomMs50gPlus,
                      child: Text('Zoom MS-50G+'),
                    ),
                    DropdownMenuItem(
                      value: DeviceFamily.zoomMs70cdrPlus,
                      child: Text('Zoom MS-70CDR+'),
                    ),
                    DropdownMenuItem(
                      value: DeviceFamily.zoomMs200dPlus,
                      child: Text('Zoom MS-200D+'),
                    ),
                    DropdownMenuItem(
                      value: DeviceFamily.line6BassPodPro,
                      child: Text('Line 6 Bass Pod Pro'),
                    ),
                  ],
                  onChanged: (family) {
                    if (family != null) {
                      connectionController.selectDeviceFamily(family);
                    }
                  },
                ),
              ],
            );

            final buttonPadding = isCompact
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
            final actionItems = <Widget>[
              if (editorController.isDirty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: StudioTheme.colorDirty.withValues(alpha: 0.15),
                    border: Border.all(color: StudioTheme.colorDirty, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 12, color: StudioTheme.colorDirty),
                      SizedBox(width: 4),
                      Text(
                        'UNSAVED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: StudioTheme.colorDirty,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),

              // Pull Patch Button
              ElevatedButton.icon(
                key: const Key('pull_patch_button'),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Pull Patch'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StudioTheme.surfaceElevated,
                  foregroundColor: Colors.white,
                  padding: buttonPadding,
                  visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                ),
                onPressed: isConnected && !editorController.isLoading
                    ? () => _pullPatch(context)
                    : null,
              ),

              // Push Patch Button
              ElevatedButton.icon(
                key: const Key('push_patch_button'),
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Push Patch'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StudioTheme.surfaceElevated,
                  foregroundColor: Colors.white,
                  padding: buttonPadding,
                  visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                ),
                onPressed: isConnected &&
                        editorController.patch != null &&
                        !editorController.isLoading
                    ? () => _pushPatch(context)
                    : null,
              ),

              // Save to Library Button
              OutlinedButton.icon(
                key: const Key('save_to_library_button'),
                icon: const Icon(Icons.bookmark_add, size: 16),
                label: const Text('Save to Library'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: StudioTheme.colorModulation,
                  side: const BorderSide(color: StudioTheme.colorModulation),
                  padding: buttonPadding,
                  visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                ),
                onPressed: editorController.patch != null
                    ? () => _saveCurrentToLibrary(context)
                    : null,
              ),

              if (setlistController != null)
                OutlinedButton.icon(
                  key: const Key('toggle_performance_mode_button'),
                  icon: Icon(
                    setlistController!.isPerformanceModeActive
                        ? Icons.tune
                        : Icons.queue_music,
                    size: 16,
                  ),
                  label: Text(
                    setlistController!.isPerformanceModeActive
                        ? 'Studio Editor'
                        : 'Stage Mode',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StudioTheme.colorDynamics,
                    backgroundColor: setlistController!.isPerformanceModeActive
                        ? StudioTheme.colorDynamics.withValues(alpha: 0.16)
                        : null,
                    side: const BorderSide(color: StudioTheme.colorDynamics),
                    padding: buttonPadding,
                    visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                  ),
                  onPressed: () => setlistController!.togglePerformanceMode(),
                ),
            ];

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 10 : 16,
                vertical: 8,
              ),
              decoration: const BoxDecoration(
                color: StudioTheme.surface,
                border: Border(
                  bottom: BorderSide(color: StudioTheme.surfaceBorder, width: 1),
                ),
              ),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _buildStatusBadge(isConnected, compact: true),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildPortDropdown(
                                context,
                                selectedPort,
                                availablePorts,
                                expandDropdown: true,
                              ),
                            ),
                            refreshButton,
                            ?libraryButton,
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            deviceSelector,
                            ...actionItems,
                          ],
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildStatusBadge(isConnected),
                                  const SizedBox(width: 10),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 220),
                                    child: _buildPortDropdown(
                                      context,
                                      selectedPort,
                                      availablePorts,
                                      expandDropdown: availablePorts.isNotEmpty,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  refreshButton,
                                ],
                              ),
                              deviceSelector,
                              ...actionItems,
                            ],
                          ),
                        ),
                        if (libraryButton != null) ...[
                          const SizedBox(width: 8),
                          libraryButton,
                        ],
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(bool isConnected, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: isConnected
            ? StudioTheme.colorConnected.withValues(alpha: 0.15)
            : StudioTheme.colorDisconnected.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? StudioTheme.colorConnected
              : StudioTheme.colorDisconnected,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? StudioTheme.colorConnected
                  : StudioTheme.colorDisconnected,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'CONNECTED' : 'DISCONNECTED',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.bold,
              letterSpacing: compact ? 0.5 : 0.8,
              color: isConnected
                  ? StudioTheme.colorConnected
                  : StudioTheme.colorDisconnected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortDropdown(
    BuildContext context,
    MidiPortDescriptor? selectedPort,
    List<MidiPortDescriptor> availablePorts, {
    bool expandDropdown = false,
  }) {
    if (availablePorts.isEmpty) {
      return const Text(
        'No MIDI Ports Found',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: Colors.grey),
      );
    }

    return DropdownButton<String>(
      key: const Key('midi_port_dropdown'),
      value: selectedPort?.id,
      isExpanded: expandDropdown,
      isDense: expandDropdown,
      hint: const Text(
        'Select MIDI Port',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13),
      ),
      dropdownColor: StudioTheme.surfaceElevated,
      underline: const SizedBox.shrink(),
      items: availablePorts.map((p) {
        return DropdownMenuItem<String>(
          value: p.id,
          child: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        );
      }).toList(),
      onChanged: (portId) async {
        if (portId == null) return;
        final port = availablePorts.firstWhere((p) => p.id == portId);
        if (connectionController.isConnected &&
            connectionController.connectedPort?.id == portId) {
          await connectionController.disconnect();
        } else {
          await connectionController.connect(
            port,
            autoSyncBank: true,
            fetchCurrentPatch: true,
          );
        }
      },
    );
  }

  Future<void> _pullPatch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await editorController.pullCurrentPatch();
    if (context.mounted) {
      if (editorController.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(editorController.errorMessage!),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Loaded "${editorController.patch?.name}" from device'),
            backgroundColor: StudioTheme.colorConnected,
          ),
        );
      }
    }
  }

  Future<void> _pushPatch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await editorController.pushPatchToDevice();
    if (context.mounted) {
      if (editorController.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(editorController.errorMessage!),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Pushed "${editorController.patch?.name}" to device'),
            backgroundColor: StudioTheme.colorConnected,
          ),
        );
      }
    }
  }

  Future<void> _saveCurrentToLibrary(BuildContext context) async {
    final current = editorController.patch;
    if (current == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await libraryController.savePatch(current);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Saved "${current.name}" to library'),
            backgroundColor: StudioTheme.colorConnected,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to save to library: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
