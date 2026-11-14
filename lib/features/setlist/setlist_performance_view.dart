import 'package:flutter/material.dart';

import '../../models/effect_slot.dart';
import '../../models/patch.dart';
import '../../models/setlist.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../editor/patch_editor_controller.dart';
import '../theme/studio_theme.dart';
import 'setlist_controller.dart';

/// High-contrast, touch-friendly Stage Performance view for live gigs and rehearsals.
class SetlistPerformanceView extends StatefulWidget {
  final SetlistController setlistController;
  final PatchEditorController editorController;

  const SetlistPerformanceView({
    super.key,
    required this.setlistController,
    required this.editorController,
  });

  @override
  State<SetlistPerformanceView> createState() => _SetlistPerformanceViewState();
}

class _SetlistPerformanceViewState extends State<SetlistPerformanceView> {
  static const double _setlistItemExtent = 52.0;

  final ScrollController _setlistScrollController = ScrollController();
  int? _lastActiveEntryIndex;

  @override
  void initState() {
    super.initState();
    _lastActiveEntryIndex = widget.setlistController.activeEntryIndex;
    widget.setlistController.addListener(_onSetlistChanged);
  }

  @override
  void didUpdateWidget(covariant SetlistPerformanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setlistController != widget.setlistController) {
      oldWidget.setlistController.removeListener(_onSetlistChanged);
      widget.setlistController.addListener(_onSetlistChanged);
      _lastActiveEntryIndex = widget.setlistController.activeEntryIndex;
    }
  }

  @override
  void dispose() {
    widget.setlistController.removeListener(_onSetlistChanged);
    _setlistScrollController.dispose();
    super.dispose();
  }

  void _onSetlistChanged() {
    final current = widget.setlistController.activeEntryIndex;
    if (current != _lastActiveEntryIndex) {
      _lastActiveEntryIndex = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveEntry(current);
      });
    }
  }

  void _scrollToActiveEntry(int index) {
    if (!mounted || !_setlistScrollController.hasClients) return;
    final position = _setlistScrollController.position;
    final itemTop = index * _setlistItemExtent;
    final itemBottom = itemTop + _setlistItemExtent;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;

    if (itemTop < viewTop) {
      _setlistScrollController.animateTo(
        itemTop.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else if (itemBottom > viewBottom) {
      _setlistScrollController.animateTo(
        (itemBottom - position.viewportDimension).clamp(
          0.0,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  SetlistController get setlistController => widget.setlistController;
  PatchEditorController get editorController => widget.editorController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        setlistController,
        editorController,
        setlistController.connectionController,
      ]),
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
                  if (setlistController.setlists.length > 1) ...[
                    const SizedBox(height: 16),
                    _buildSetlistSelector(isCompact: false),
                  ],
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
            final isLandscapeDashboard =
                constraints.maxWidth >= constraints.maxHeight &&
                constraints.maxWidth >= 700;

            if (isLandscapeDashboard) {
              return _buildLandscapeDashboard(
                context: context,
                constraints: constraints,
                entries: setlist.entries,
                activeEntry: activeEntry,
                activePatch: activePatch,
                resolvedPatch: resolvedPatch,
                displayTitle: displayTitle,
                patchSubtitle: patchSubtitle,
                bpm: bpm,
                indexLabel: indexLabel,
              );
            }

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
                                  child: _buildSetlistSelector(isCompact: isCompact),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTunerToggleButton(compact: true),
                                const SizedBox(width: 8),
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

  Widget _buildLandscapeDashboard({
    required BuildContext context,
    required BoxConstraints constraints,
    required List<SetlistEntry> entries,
    required SetlistEntry activeEntry,
    required Patch? activePatch,
    required Patch? resolvedPatch,
    required String displayTitle,
    required String patchSubtitle,
    required int bpm,
    required String indexLabel,
  }) {
    final leftPanelWidth = (constraints.maxWidth * 0.22).clamp(220.0, 320.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column (~22% width): Selector, Compact Patch Header, Prev/Next, Tuner, Scrollable Setlist
        Container(
          key: const Key('stage_landscape_left_panel'),
          width: leftPanelWidth,
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: StudioTheme.surface,
            border: Border(
              right: BorderSide(color: StudioTheme.surfaceBorder, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterChip(
                    label: const Text('Loop'),
                    visualDensity: VisualDensity.compact,
                    selected: setlistController.wrapAroundNavigation,
                    onSelected: (v) =>
                        setlistController.setWrapAroundNavigation(v),
                  ),
                  OutlinedButton.icon(
                    key: const Key('exit_stage_mode_button'),
                    icon: const Icon(Icons.tune, size: 15),
                    label: const Text('Editor'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        setlistController.setPerformanceModeActive(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSetlistSelector(isCompact: false, expandWidth: true),
              const SizedBox(height: 8),
              // Compact Active Patch Header
              Container(
                key: const Key('stage_landscape_patch_box'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StudioTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: StudioTheme.colorModulation.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          key: const Key('stage_index_badge'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StudioTheme.colorDynamics
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: StudioTheme.colorDynamics,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            indexLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: StudioTheme.colorDynamics,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StudioTheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: StudioTheme.colorFilterEq,
                            ),
                          ),
                          child: Text(
                            '$bpm BPM',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: StudioTheme.colorFilterEq,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      displayTitle,
                      key: const Key('stage_song_title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    if (displayTitle != patchSubtitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        patchSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: StudioTheme.colorModulation,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (setlistController.warningMessage != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        key: const Key('stage_warning_banner'),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amberAccent),
                        ),
                        child: Text(
                          setlistController.warningMessage!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Prev / Next Step Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        key: const Key('setlist_prev_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StudioTheme.surfaceElevated,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(
                              color: StudioTheme.surfaceBorder,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onPressed: setlistController.canStepPrevious
                            ? () => setlistController.previousEntry()
                            : null,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chevron_left, size: 20),
                              Text(
                                'PREV',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        key: const Key('setlist_next_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StudioTheme.colorDynamics,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: setlistController.canStepNext
                            ? () => setlistController.nextEntry()
                            : null,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'NEXT',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTunerToggleButton(compact: true),
              const SizedBox(height: 8),
              // Scrollable Setlist Patch List
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: StudioTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StudioTheme.surfaceBorder),
                  ),
                  child: ListView.builder(
                    key: const Key('stage_setlist_patch_list'),
                    controller: _setlistScrollController,
                    padding: const EdgeInsets.all(4),
                    itemExtent: _setlistItemExtent,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final resolved =
                          setlistController.resolvePatchForEntry(entry);
                      final isSelected =
                          index == setlistController.activeEntryIndex;
                      final title = entry.songTitle?.trim().isNotEmpty == true
                          ? entry.songTitle!
                          : (resolved?.name ?? entry.patchId);
                      final stepNum = (index + 1).toString().padLeft(2, '0');

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          key: Key('stage_setlist_entry_tile_$index'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setlistController.selectEntry(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? StudioTheme.colorDynamics
                                      .withValues(alpha: 0.22)
                                  : StudioTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? StudioTheme.colorDynamics
                                    : StudioTheme.surfaceBorder,
                                width: isSelected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? StudioTheme.colorDynamics
                                        : StudioTheme.surface,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    stepNum,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: isSelected
                                          ? Colors.black
                                          : StudioTheme.colorDynamics,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Area (Remaining ~78% width): Giant Effect Stompboxes for ONLY the active patch
        Expanded(
          child: Container(
            key: const Key('stage_landscape_effects_panel'),
            padding: const EdgeInsets.all(16),
            child: _buildLandscapeEffectsGrid(activePatch),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeEffectsGrid(Patch? activePatch) {
    if (activePatch == null || activePatch.slots.isEmpty) {
      return const Center(
        child: Text(
          'No active effects in current patch',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final slots = activePatch.slots;
    final count = slots.length;

    return LayoutBuilder(
      builder: (context, gridConstraints) {
        const spacing = 14.0;
        final int cols;
        if (count == 1) {
          cols = 1;
        } else if (count <= 4) {
          cols = 2;
        } else {
          cols = gridConstraints.maxWidth >= 700 ? 3 : 2;
        }
        final rows = (count / cols).ceil();
        final tileW =
            (gridConstraints.maxWidth - (cols - 1) * spacing) / cols;
        final tileH =
            (gridConstraints.maxHeight - (rows - 1) * spacing) / rows;

        if (tileH >= 100.0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(rows, (r) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: r < rows - 1 ? spacing : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(cols, (c) {
                      final idx = r * cols + c;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: c < cols - 1 ? spacing : 0,
                          ),
                          child: idx < count
                              ? _buildGiantStageStompbox(
                                  activePatch,
                                  slots[idx],
                                )
                              : const SizedBox.shrink(),
                        ),
                      );
                    }),
                  ),
                ),
              );
            }),
          );
        }

        final aspectRatio = (tileW / 120.0).clamp(0.8, 3.5);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: count,
          itemBuilder: (context, index) => _buildGiantStageStompbox(
            activePatch,
            slots[index],
          ),
        );
      },
    );
  }

  Widget _buildGiantStageStompbox(Patch patch, EffectSlot slot) {
    final def = EffectCatalogRegistry.getDefinition(
      patch.deviceFamily,
      slot.effectId,
    );
    final categoryColor = StudioTheme.getCategoryColor(def.category);
    final isEnabled = slot.isEnabled;

    return InkWell(
      key: Key('stage_stomp_slot_${slot.slotIndex}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => editorController.toggleSlotEnabled(slot.slotIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isEnabled
              ? categoryColor.withValues(alpha: 0.16)
              : StudioTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled ? categoryColor : StudioTheme.surfaceBorder,
            width: isEnabled ? 3.0 : 1.5,
          ),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: categoryColor.withValues(alpha: 0.22),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isEnabled
                          ? categoryColor.withValues(alpha: 0.7)
                          : StudioTheme.surfaceBorder,
                    ),
                  ),
                  child: Text(
                    'SLOT ${slot.slotIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: isEnabled ? categoryColor : Colors.grey,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? categoryColor.withValues(alpha: 0.22)
                        : StudioTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isEnabled
                          ? categoryColor
                          : StudioTheme.surfaceBorder,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isEnabled
                              ? categoryColor
                              : Colors.grey.shade700,
                          boxShadow: isEnabled
                              ? [
                                  BoxShadow(
                                    color: categoryColor.withValues(alpha: 0.8),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEnabled ? 'ON' : 'BYPASSED',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                          color: isEnabled ? Colors.white : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  slot.effectName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: isEnabled ? Colors.white : Colors.grey.shade500,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTunerToggleButton({required bool compact}) {
    final isTunerActive = setlistController.isTunerActive;
    const activeColor = Colors.amberAccent;

    return SizedBox(
      height: compact ? 38 : 48,
      child: OutlinedButton.icon(
        key: const Key('stage_tuner_toggle_button'),
        icon: Icon(
          Icons.graphic_eq,
          size: compact ? 16 : 20,
          color: isTunerActive ? Colors.black : activeColor,
        ),
        label: Text(
          isTunerActive ? 'TUNER ON' : 'TUNER',
          style: TextStyle(
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: isTunerActive ? activeColor : StudioTheme.surfaceElevated,
          foregroundColor: isTunerActive ? Colors.black : Colors.white,
          side: BorderSide(
            color: isTunerActive ? activeColor : StudioTheme.surfaceBorder,
            width: isTunerActive ? 2.0 : 1.2,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 6 : 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () => setlistController.toggleTuner(),
      ),
    );
  }

  Widget _buildSetlistSelector({
    required bool isCompact,
    bool expandWidth = false,
  }) {
    final setlists = setlistController.setlists;
    if (setlists.isEmpty) return const SizedBox.shrink();

    final activeId = setlists.any((s) => s.id == setlistController.activeSetlistId)
        ? setlistController.activeSetlistId
        : setlists.first.id;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: expandWidth ? double.infinity : (isCompact ? 170 : 260),
      ),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: StudioTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioTheme.surfaceBorder),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('stage_setlist_selector'),
            value: activeId,
            isExpanded: true,
            dropdownColor: StudioTheme.surfaceElevated,
            icon: const Icon(
              Icons.arrow_drop_down,
              color: Colors.white70,
            ),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
            items: setlists
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s.id,
                    child: Text(
                      '${s.name} (${s.entries.length})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id == null || id == setlistController.activeSetlistId) return;
              setlistController.selectSetlist(id);
              if (setlistController.activeSetlist?.entries.isNotEmpty == true) {
                setlistController.selectEntryAt(0);
              }
            },
          ),
        ),
      ),
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

