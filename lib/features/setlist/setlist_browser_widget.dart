import 'package:flutter/material.dart';

import '../../models/patch.dart';
import '../../models/setlist.dart';
import '../theme/studio_theme.dart';
import 'setlist_controller.dart';

/// Responsive Setlist manager tab rendered inside `PatchLibraryDrawerOrPanel`.
class SetlistBrowserWidget extends StatelessWidget {
  final SetlistController setlistController;

  const SetlistBrowserWidget({
    super.key,
    required this.setlistController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        setlistController,
        setlistController.libraryController,
      ]),
      builder: (context, _) {
        final setlists = setlistController.setlists;
        final active = setlistController.activeSetlist;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, top: 14, bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.queue_music,
                    size: 18,
                    color: StudioTheme.colorDynamics,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'SETLISTS',
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
                    key: const Key('create_setlist_button'),
                    icon: const Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: StudioTheme.colorDynamics,
                    ),
                    tooltip: 'Create Setlist',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _showCreateSetlistDialog(context),
                  ),
                ],
              ),
            ),

            // Active Setlist Selector + Actions
            if (setlists.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('setlist_selector_dropdown'),
                        initialValue: active?.id,
                        isDense: true,
                        dropdownColor: StudioTheme.surfaceElevated,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: setlists.map((s) {
                          return DropdownMenuItem<String>(
                            value: s.id,
                            child: Text(
                              '${s.name} (${s.entries.length})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: Colors.white),
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id != null) setlistController.selectSetlist(id);
                        },
                      ),
                    ),
                    if (active != null) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        key: const Key('setlist_actions_menu'),
                        tooltip: 'Setlist Actions',
                        color: StudioTheme.surfaceElevated,
                        icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                        onSelected: (action) {
                          if (action == 'rename') {
                            _showRenameSetlistDialog(context, active);
                          } else if (action == 'midi') {
                            _showMidiFootConfigDialog(context);
                          } else if (action == 'delete') {
                            _confirmDeleteSetlist(context, active);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename Setlist')),
                          PopupMenuItem(value: 'midi', child: Text('MIDI Foot-Controller...')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete Setlist', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

            if (active != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ElevatedButton.icon(
                      key: const Key('add_preset_to_setlist_button'),
                      icon: const Icon(Icons.playlist_add, size: 16),
                      label: const Text('Add Preset', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StudioTheme.surfaceElevated,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: () => _showAddPresetDialog(context, active),
                    ),
                    ElevatedButton.icon(
                      key: const Key('launch_stage_mode_button'),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Perform Live', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StudioTheme.colorDynamics,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: active.entries.isEmpty
                          ? null
                          : () {
                              setlistController.setPerformanceModeActive(true);
                              if (Scaffold.maybeOf(context)?.isEndDrawerOpen ?? false) {
                                Navigator.of(context).pop();
                              }
                            },
                    ),
                  ],
                ),
              ),

            const Divider(color: StudioTheme.surfaceBorder, height: 1),

            // Entries List
            Expanded(
              child: active == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'No setlists yet',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Create Setlist'),
                              onPressed: () => _showCreateSetlistDialog(context),
                            ),
                          ],
                        ),
                      ),
                    )
                  : active.entries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Add presets from the library to build your gig setlist.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ),
                        )
                      : ListView.separated(
                          key: const Key('setlist_entries_list'),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          itemCount: active.entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final entry = active.entries[index];
                            final patch = setlistController.resolvePatchForEntry(entry);
                            final isCurrent = index == setlistController.activeEntryIndex;
                            return _buildEntryCard(
                              context,
                              active,
                              index,
                              entry,
                              patch,
                              isCurrent,
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    Setlist setlist,
    int index,
    SetlistEntry entry,
    Patch? patch,
    bool isCurrent,
  ) {
    final title = entry.songTitle?.trim().isNotEmpty == true
        ? entry.songTitle!
        : (patch?.name ?? 'Missing Preset');
    final isMissing = patch == null;

    return InkWell(
      key: Key('setlist_entry_${entry.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => setlistController.selectEntryAt(index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: StudioTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent
                ? StudioTheme.colorDynamics
                : (isMissing ? Colors.amber : StudioTheme.surfaceBorder),
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCurrent
                    ? StudioTheme.colorDynamics.withValues(alpha: 0.2)
                    : StudioTheme.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? StudioTheme.colorDynamics : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isMissing ? Colors.amberAccent : Colors.white,
                    ),
                  ),
                  Text(
                    isMissing
                        ? '[Missing Preset: ${entry.patchId}]'
                        : '${patch.name}${entry.tempoOverride != null ? ' • ${entry.tempoOverride} BPM' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 15),
              tooltip: 'Move Up',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: index > 0
                  ? () => setlistController.reorderEntries(setlist.id, index, index - 1)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 15),
              tooltip: 'Move Down',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: index < setlist.entries.length - 1
                  ? () => setlistController.reorderEntries(setlist.id, index, index + 1)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 15, color: Colors.grey),
              tooltip: 'Edit Cue',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: () => _showEditEntryDialog(context, setlist, entry),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 15, color: Colors.redAccent),
              tooltip: 'Remove Entry',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: () => setlistController.removeEntry(setlist.id, index),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateSetlistDialog(BuildContext context) async {
    final controller = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioTheme.surfaceElevated,
        title: const Text('New Setlist'),
        content: TextField(
          key: const Key('new_setlist_name_input'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Friday Night Gig'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('confirm_create_setlist_button'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (created != null && created.trim().isNotEmpty) {
      await setlistController.createSetlist(created);
    }
  }

  Future<void> _showRenameSetlistDialog(
    BuildContext context,
    Setlist setlist,
  ) async {
    final controller = TextEditingController(text: setlist.name);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioTheme.surfaceElevated,
        title: const Text('Rename Setlist'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated != null && updated.trim().isNotEmpty) {
      await setlistController.renameSetlist(setlist.id, updated);
    }
  }

  Future<void> _confirmDeleteSetlist(
    BuildContext context,
    Setlist setlist,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioTheme.surfaceElevated,
        title: const Text('Delete Setlist?'),
        content: Text('Delete "${setlist.name}"? Library presets are not deleted.'),
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
      ),
    );
    if (confirm == true) {
      await setlistController.deleteSetlist(setlist.id);
    }
  }

  Future<void> _showAddPresetDialog(
    BuildContext context,
    Setlist setlist,
  ) async {
    final patches = setlistController.libraryController.patches;
    final selected = await showDialog<Patch>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioTheme.surfaceElevated,
        title: const Text('Add Preset to Setlist'),
        content: SizedBox(
          width: 340,
          height: 320,
          child: patches.isEmpty
              ? const Center(child: Text('No presets in library'))
              : ListView.builder(
                  itemCount: patches.length,
                  itemBuilder: (_, idx) {
                    final p = patches[idx];
                    return ListTile(
                      title: Text(p.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        p.deviceFamily.displayName,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      onTap: () => Navigator.of(ctx).pop(p),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected != null) {
      await setlistController.addPatchToSetlist(setlist.id, selected);
    }
  }

  Future<void> _showEditEntryDialog(
    BuildContext context,
    Setlist setlist,
    SetlistEntry entry,
  ) async {
    final titleCtrl = TextEditingController(text: entry.songTitle ?? '');
    final notesCtrl = TextEditingController(text: entry.performanceNotes ?? '');
    final tempoCtrl = TextEditingController(
      text: entry.tempoOverride?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioTheme.surfaceElevated,
        title: const Text('Edit Setlist Cue'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Song Title (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Performance Notes'),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tempoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'BPM Override (40–250, optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final parsedTempo = int.tryParse(tempoCtrl.text.trim());
      await setlistController.updateEntry(
        setlist.id,
        entry.copyWith(
          songTitle: titleCtrl.text.trim(),
          clearSongTitle: titleCtrl.text.trim().isEmpty,
          performanceNotes: notesCtrl.text.trim(),
          clearPerformanceNotes: notesCtrl.text.trim().isEmpty,
          tempoOverride: parsedTempo?.clamp(40, 250),
          clearTempoOverride: parsedTempo == null,
        ),
      );
    }

    titleCtrl.dispose();
    notesCtrl.dispose();
    tempoCtrl.dispose();
  }

  Future<void> _showMidiFootConfigDialog(BuildContext context) async {
    var config = setlistController.midiConfig;
    final nextCtrl = TextEditingController(
      text: config.nextStepCcNumber?.toString() ?? '',
    );
    final prevCtrl = TextEditingController(
      text: config.prevStepCcNumber?.toString() ?? '',
    );
    bool pcEnabled = config.enableProgramChangeSelect;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: StudioTheme.surfaceElevated,
          title: const Text('MIDI Foot-Controller Triggers'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Program Change selects cue'),
                  subtitle: const Text('PC 0..N selects setlist entry in Stage Mode'),
                  value: pcEnabled,
                  onChanged: (v) => setLocal(() => pcEnabled = v),
                ),
                TextField(
                  controller: nextCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Next Cue CC # (e.g. 80, optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: prevCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prev Cue CC # (e.g. 81, optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final nextCc = int.tryParse(nextCtrl.text.trim());
      final prevCc = int.tryParse(prevCtrl.text.trim());
      setlistController.updateMidiConfig(
        MidiFootControllerConfig(
          enableProgramChangeSelect: pcEnabled,
          nextStepCcNumber: nextCc?.clamp(0, 127),
          prevStepCcNumber: prevCc?.clamp(0, 127),
        ),
      );
    }

    nextCtrl.dispose();
    prevCtrl.dispose();
  }
}

