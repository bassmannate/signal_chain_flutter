import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/patch_diff.dart';
import '../theme/studio_theme.dart';

/// Responsive, viewport-clamped dialog displaying a structured [PatchDiff]
/// between two patches (e.g., A vs. B compare, pre-write hardware slot diff,
/// library preset comparison, or import preview).
class PatchDiffDialog extends StatefulWidget {
  final String baseLabel;
  final String targetLabel;
  final PatchDiff diff;

  const PatchDiffDialog({
    super.key,
    required this.baseLabel,
    required this.targetLabel,
    required this.diff,
  });

  static Future<void> show(
    BuildContext context, {
    required String baseLabel,
    required String targetLabel,
    required PatchDiff diff,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PatchDiffDialog(
        baseLabel: baseLabel,
        targetLabel: targetLabel,
        diff: diff,
      ),
    );
  }

  @override
  State<PatchDiffDialog> createState() => _PatchDiffDialogState();
}

class _PatchDiffDialogState extends State<PatchDiffDialog> {
  bool _showUnchanged = false;

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final isCompact = mediaSize.width < 600;
    final isShort = mediaSize.height < 520;
    final dialogWidth = math.min(540.0, math.max(260.0, mediaSize.width - 32));
    final diff = widget.diff;
    final visibleSlots = _showUnchanged
        ? diff.slotDiffs
        : diff.slotDiffs.where((s) => s.hasChanges).toList();

    return AlertDialog(
      key: const Key('patch_diff_dialog'),
      backgroundColor: StudioTheme.surfaceElevated,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 36,
        vertical: isShort ? 10 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.compare_arrows,
            size: 20,
            color: StudioTheme.colorModulation,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Patch Diff Preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (diff.hasChanges
                      ? StudioTheme.colorFilterEq
                      : StudioTheme.colorDynamics)
                  .withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: diff.hasChanges
                    ? StudioTheme.colorFilterEq
                    : StudioTheme.colorDynamics,
              ),
            ),
            child: Text(
              diff.summaryLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: diff.hasChanges
                    ? StudioTheme.colorFilterEq
                    : StudioTheme.colorDynamics,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Comparison Header: Base -> Target
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _EndpointPill(
                      label: widget.baseLabel,
                      patchName: diff.base.name,
                      color: Colors.grey,
                    ),
                    const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                    _EndpointPill(
                      label: widget.targetLabel,
                      patchName: diff.target.name,
                      color: StudioTheme.colorModulation,
                    ),
                  ],
                ),
              ),

              if (!diff.hasChanges) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: StudioTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StudioTheme.surfaceBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: StudioTheme.colorDynamics, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Patches are identical.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                if (diff.nameChange != null || diff.tempoChange != null) ...[
                  const SizedBox(height: 10),
                  _buildMetadataCard(diff),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SIGNAL CHAIN (${visibleSlots.length} shown)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (diff.slotDiffs.any((s) => !s.hasChanges))
                      TextButton(
                        key: const Key('diff_toggle_unchanged_button'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            setState(() => _showUnchanged = !_showUnchanged),
                        child: Text(
                          _showUnchanged ? 'Hide unchanged' : 'Show unchanged',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final slotDiff in visibleSlots) ...[
                  _SlotDiffCard(slotDiff: slotDiff),
                  const SizedBox(height: 6),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('close_diff_dialog_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildMetadataCard(PatchDiff diff) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'METADATA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          if (diff.nameChange != null)
            _DeltaRow(
              label: 'Name',
              before: diff.nameChange!.before,
              after: diff.nameChange!.after,
            ),
          if (diff.tempoChange != null)
            _DeltaRow(
              label: 'Tempo',
              before: '${diff.tempoChange!.before} BPM',
              after: '${diff.tempoChange!.after} BPM',
            ),
        ],
      ),
    );
  }
}

class _EndpointPill extends StatelessWidget {
  final String label;
  final String patchName;
  final Color color;

  const _EndpointPill({
    required this.label,
    required this.patchName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            patchName.trim().isEmpty ? '(Untitled)' : patchName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotDiffCard extends StatelessWidget {
  final SlotDiff slotDiff;

  const _SlotDiffCard({required this.slotDiff});

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeColor) = switch (slotDiff.kind) {
      SlotDiffKind.added => ('ADDED', StudioTheme.colorDynamics),
      SlotDiffKind.removed => ('REMOVED', Colors.redAccent),
      SlotDiffKind.replaced => ('SWAPPED', StudioTheme.colorFilterEq),
      SlotDiffKind.modified => ('MODIFIED', StudioTheme.colorModulation),
      SlotDiffKind.unchanged => ('UNCHANGED', Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: slotDiff.hasChanges
              ? badgeColor.withValues(alpha: 0.45)
              : StudioTheme.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SLOT #${slotDiff.slotIndex + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slotDiff.kind == SlotDiffKind.replaced
                      ? '${slotDiff.baseSlot?.effectName ?? ''} → ${slotDiff.targetSlot?.effectName ?? ''}'
                      : slotDiff.displayEffectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (slotDiff.bypassChange != null) ...[
            const SizedBox(height: 6),
            _DeltaRow(
              label: 'Bypass',
              before: slotDiff.bypassChange!.before ? 'ON' : 'OFF',
              after: slotDiff.bypassChange!.after ? 'ON' : 'OFF',
            ),
          ],
          if (slotDiff.parameterDiffs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in slotDiff.parameterDiffs)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: StudioTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: StudioTheme.surfaceBorder),
                    ),
                    child: Text(
                      '${p.paramName}: ${p.beforeFormatted} → ${p.afterFormatted}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeltaRow extends StatelessWidget {
  final String label;
  final String before;
  final String after;

  const _DeltaRow({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            before,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.white54,
            ),
          ),
          const Icon(Icons.arrow_forward, size: 11, color: Colors.grey),
          Text(
            after,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: StudioTheme.colorModulation,
            ),
          ),
        ],
      ),
    );
  }
}

