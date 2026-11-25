import 'package:flutter/material.dart';

import '../../core/compatibility/patch_effect_compatibility.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';

/// User resolution for a single-patch hardware write containing missing effects.
enum MissingEffectAction { stripAndProceed, sendAnyway, cancel }

/// User resolution for a batch bank restore where one or more patches contain
/// effects not installed on the connected pedal.
enum BatchMissingEffectAction {
  stripAndRestoreAll,
  skipAffected,
  restoreAnyway,
  cancel,
}

/// Summary of a single candidate patch in a batch restore that has missing effects.
@immutable
class AffectedBatchPatch {
  final int index;
  final Patch patch;
  final PatchEffectCompatibilityReport report;

  const AffectedBatchPatch({
    required this.index,
    required this.patch,
    required this.report,
  });
}

/// Prompts the user when writing a single [patch] that references effect IDs
/// missing from [targetFamily] (verified by onboard scan or stock catalog).
Future<MissingEffectAction> resolveMissingEffectsForSingleWrite({
  required BuildContext context,
  required Patch patch,
  required DeviceFamily targetFamily,
  required PatchEffectCompatibilityReport report,
}) async {
  if (!report.hasMissingEffects) {
    return MissingEffectAction.sendAnyway;
  }

  final deviceLabel = EffectCatalogRegistry.conciseModelLabel(targetFamily);
  final strippedPreview = PatchEffectCompatibility.stripMissingSlots(
    patch,
    report.missingSlotIndices,
  );
  final rOutWillAdjust = patch.deviceFamily.isZoomMsPlus &&
      strippedPreview.effectiveRightOutputTapCode !=
          patch.effectiveRightOutputTapCode;
  final count = report.missingSlots.length;

  final result = await showDialog<MissingEffectAction>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      key: const Key('missing_effects_single_dialog'),
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
              'Missing Effects on Pedal',
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${patch.name}" contains $count effect${count == 1 ? '' : 's'} '
              'not installed on your ${targetFamily.displayName}.',
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              report.isVerifiedByHardwareScan
                  ? 'Verified by onboard pedal scan'
                  : 'Checked against stock $deviceLabel catalog',
              style: TextStyle(
                fontSize: 11,
                color: report.isVerifiedByHardwareScan
                    ? StudioTheme.colorModulation
                    : Colors.amberAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int idx = 0; idx < report.missingSlots.length; idx++) ...[
                        if (idx > 0)
                          const Divider(
                            height: 10,
                            color: StudioTheme.surfaceBorder,
                          ),
                        Builder(
                          builder: (_) {
                            final m = report.missingSlots[idx];
                            final isCustom = m.originLabel == 'Custom';
                            final badgeColor = isCustom
                                ? StudioTheme.colorCustom
                                : StudioTheme.colorPreamp;
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Slot #${m.slotIndex + 1}: ${m.displayName} (${m.formattedEffectId})',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                if (m.originLabel != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color:
                                            badgeColor.withValues(alpha: 0.75),
                                      ),
                                    ),
                                    child: Text(
                                      m.originLabel!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (rOutWillAdjust) ...[
              const SizedBox(height: 8),
              const Text(
                'Note: Stripping missing slots will automatically adjust the MS+ R-Out routing tap cleanly.',
                style: TextStyle(fontSize: 11, color: StudioTheme.colorFilterEq),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 8,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          key: const Key('missing_effects_cancel_button'),
          onPressed: () =>
              Navigator.of(ctx).pop(MissingEffectAction.cancel),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          key: const Key('missing_effects_write_anyway_button'),
          style: TextButton.styleFrom(foregroundColor: Colors.amberAccent),
          onPressed: () =>
              Navigator.of(ctx).pop(MissingEffectAction.sendAnyway),
          child: const Text('Write Anyway'),
        ),
        ElevatedButton.icon(
          key: const Key('missing_effects_strip_and_write_button'),
          icon: const Icon(Icons.cleaning_services_outlined, size: 16),
          label: const Text('Strip Missing & Write'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioTheme.colorModulation,
            foregroundColor: Colors.black,
          ),
          onPressed: () =>
              Navigator.of(ctx).pop(MissingEffectAction.stripAndProceed),
        ),
      ],
    ),
  );

  return result ?? MissingEffectAction.cancel;
}

/// Prompts the user once upfront during batch bank restore when 1+ candidate
/// patches reference effects not installed on the connected [targetFamily].
Future<BatchMissingEffectAction> resolveMissingEffectsForBatchRestore({
  required BuildContext context,
  required int totalPatchCount,
  required List<AffectedBatchPatch> affectedPatches,
  required DeviceFamily targetFamily,
  required bool isVerifiedByHardwareScan,
}) async {
  if (affectedPatches.isEmpty) {
    return BatchMissingEffectAction.restoreAnyway;
  }

  final deviceLabel = EffectCatalogRegistry.conciseModelLabel(targetFamily);
  final affectedCount = affectedPatches.length;

  final result = await showDialog<BatchMissingEffectAction>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      key: const Key('missing_effects_batch_dialog'),
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
              'Missing Effects in Batch Restore',
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$affectedCount of $totalPatchCount patches contain effects '
              'not installed on your $deviceLabel.',
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              isVerifiedByHardwareScan
                  ? 'Verified by onboard pedal scan'
                  : 'Checked against stock $deviceLabel catalog',
              style: TextStyle(
                fontSize: 11,
                color: isVerifiedByHardwareScan
                    ? StudioTheme.colorModulation
                    : Colors.amberAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int idx = 0; idx < affectedPatches.length; idx++) ...[
                        if (idx > 0)
                          const Divider(
                            height: 10,
                            color: StudioTheme.surfaceBorder,
                          ),
                        Builder(
                          builder: (_) {
                            final item = affectedPatches[idx];
                            final missingNames = item.report.missingSlots
                                .map((m) => m.displayName)
                                .join(', ');
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.patch.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Missing: $missingNames',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 8,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          key: const Key('batch_missing_cancel_button'),
          onPressed: () =>
              Navigator.of(ctx).pop(BatchMissingEffectAction.cancel),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          key: const Key('batch_missing_restore_anyway_button'),
          style: TextButton.styleFrom(foregroundColor: Colors.amberAccent),
          onPressed: () =>
              Navigator.of(ctx).pop(BatchMissingEffectAction.restoreAnyway),
          child: const Text('Restore Anyway'),
        ),
        OutlinedButton(
          key: const Key('batch_missing_skip_affected_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: StudioTheme.surfaceBorderFocused),
          ),
          onPressed: () =>
              Navigator.of(ctx).pop(BatchMissingEffectAction.skipAffected),
          child: const Text('Skip Affected'),
        ),
        ElevatedButton.icon(
          key: const Key('batch_missing_strip_all_button'),
          icon: const Icon(Icons.cleaning_services_outlined, size: 16),
          label: const Text('Strip Missing & Restore All'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioTheme.colorModulation,
            foregroundColor: Colors.black,
          ),
          onPressed: () =>
              Navigator.of(ctx).pop(BatchMissingEffectAction.stripAndRestoreAll),
        ),
      ],
    ),
  );

  return result ?? BatchMissingEffectAction.cancel;
}

