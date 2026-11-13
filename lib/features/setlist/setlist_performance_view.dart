import 'package:flutter/material.dart';

import '../../models/effect_slot.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/studio_theme.dart';
import 'setlist_controller.dart';

/// High-contrast, touch-friendly Stage Performance view for live gigs and rehearsals.
class SetlistPerformanceView extends StatelessWidget {
  final SetlistController setlistController;
  final PatchEditorController editorController;

  const SetlistPerformanceView({
    super.key,
    required this.setlistController,
    required this.editorController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([setlistController, editorController]),
      builder: (context, _) {
        final setlist = setlistController.activeSetlist;
        final activeEntry = setlistController.activeEntry;
        final activePatch = editorController.patch;
        final nextEntry = setlistController.nextPreviewEntry;

        if (setlist == null || setlist.entries.isEmpty || activeEntry == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.queue_music,
                    size: 56,
                    color: StudioTheme.colorDynamics,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Setlist Entries Ready',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Open the Setlists tab in the library panel to add presets.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => setlistController.setPerformanceModeActive(false),
                    icon: const Icon(Icons.edit),
                    label: const Text('Return to Studio Editor'),
                  ),
                ],
              ),
            ),
          );
        }

        final resolvedPatch = setlistController.resolvePatchForEntry(activeEntry);
        final displayTitle = activeEntry.songTitle?.trim().isNotEmpty == true
            ? activeEntry.songTitle!
            : (resolvedPatch?.name ?? activePatch?.name ?? 'Missing Preset');
        final patchSubtitle = resolvedPatch?.name ?? 'Missing Preset';
        final bpm = activeEntry.tempoOverride ?? activePatch?.tempo ?? 120;
        final indexLabel =
            '${(setlistController.activeEntryIndex + 1).toString().padLeft(2, '0')} / ${setlist.entries.length.toString().padLeft(2, '0')}';

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;
            final isShort = constraints.maxHeight < 480;
            final stepButtonHeight = isCompact || isShort ? 64.0 : 84.0;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isCompact ? 12 : 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (isCompact ? 24 : 40),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top Stage Bar: Setlist Name, Cue Counter, Wrap Toggle & Exit
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  key: const Key('stage_index_badge'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: StudioTheme.colorDynamics
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: StudioTheme.colorDynamics,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    indexLabel,
                                    style: TextStyle(
                                      fontSize: isCompact ? 18 : 22,
                                      fontWeight: FontWeight.w900,
                                      color: StudioTheme.colorDynamics,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    setlist.name.toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilterChip(
                                  label: const Text('Loop'),
                                  selected: setlistController.wrapAroundNavigation,
                                  onSelected: (v) =>
                                      setlistController.setWrapAroundNavigation(v),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  key: const Key('exit_stage_mode_button'),
                                  icon: const Icon(Icons.tune, size: 16),
                                  label: const Text('Editor'),
                                  onPressed: () => setlistController
                                      .setPerformanceModeActive(false),
                                ),
                              ],
                            ),
                          ],
                        ),

                        if (setlistController.warningMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            key: const Key('stage_warning_banner'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amberAccent),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amberAccent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    setlistController.warningMessage!,
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Main Song & Patch Hero Card
                        Container(
                          padding: EdgeInsets.all(isCompact ? 16 : 24),
                          decoration: BoxDecoration(
                            color: StudioTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: StudioTheme.colorModulation
                                  .withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayTitle,
                                      key: const Key('stage_song_title'),
                                      style: TextStyle(
                                        fontSize: isCompact ? 28 : 40,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: StudioTheme.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: StudioTheme.colorFilterEq,
                                      ),
                                    ),
                                    child: Text(
                                      '$bpm BPM',
                                      style: TextStyle(
                                        fontSize: isCompact ? 15 : 18,
                                        fontWeight: FontWeight.bold,
                                        color: StudioTheme.colorFilterEq,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Preset: $patchSubtitle • ${resolvedPatch?.deviceFamily.displayName ?? ''}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: StudioTheme.colorModulation,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (activeEntry.performanceNotes != null &&
                                  activeEntry.performanceNotes!.trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: StudioTheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: StudioTheme.surfaceBorder,
                                    ),
                                  ),
                                  child: Text(
                                    activeEntry.performanceNotes!,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Interactive Live Stompbox Bypass Strip
                        if (activePatch != null && activePatch.slots.isNotEmpty)
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: List.generate(activePatch.slots.length, (i) {
                              return _buildStageStompbox(
                                activePatch.slots[i],
                                () => editorController.toggleSlotEnabled(i),
                              );
                            }),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Bottom Stage Controls: Up Next + Oversized Prev/Next Stepping
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (nextEntry != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'UP NEXT: ${nextEntry.songTitle?.trim().isNotEmpty == true ? nextEntry.songTitle : (setlistController.resolvePatchForEntry(nextEntry)?.name ?? nextEntry.patchId)}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: stepButtonHeight,
                                child: ElevatedButton.icon(
                                  key: const Key('setlist_prev_button'),
                                  icon: const Icon(Icons.chevron_left, size: 32),
                                  label: Text(
                                    'PREVIOUS',
                                    style: TextStyle(
                                      fontSize: isCompact ? 16 : 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: StudioTheme.surfaceElevated,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(
                                        color: StudioTheme.surfaceBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  onPressed: setlistController.canStepPrevious
                                      ? () => setlistController.previousEntry()
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: SizedBox(
                                height: stepButtonHeight,
                                child: ElevatedButton.icon(
                                  key: const Key('setlist_next_button'),
                                  icon: const Icon(Icons.chevron_right, size: 32),
                                  label: Text(
                                    'NEXT',
                                    style: TextStyle(
                                      fontSize: isCompact ? 16 : 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: StudioTheme.colorDynamics,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: setlistController.canStepNext
                                      ? () => setlistController.nextEntry()
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStageStompbox(EffectSlot slot, VoidCallback onToggle) {
    final activeColor = StudioTheme.colorDynamics;
    return InkWell(
      key: Key('stage_stomp_${slot.slotIndex}'),
      borderRadius: BorderRadius.circular(10),
      onTap: onToggle,
      child: Container(
        constraints: const BoxConstraints(minWidth: 110, minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: slot.isEnabled
              ? activeColor.withValues(alpha: 0.16)
              : StudioTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: slot.isEnabled ? activeColor : StudioTheme.surfaceBorder,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: slot.isEnabled ? activeColor : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              slot.effectName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: slot.isEnabled ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

