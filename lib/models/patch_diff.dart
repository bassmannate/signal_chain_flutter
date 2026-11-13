import 'dart:math' as math;

import 'effect_slot.dart';
import 'patch.dart';

/// Classification of how a slot differs between a base and target [Patch].
enum SlotDiffKind {
  unchanged,
  added,
  removed,
  replaced,
  modified,
}

/// Difference for a single effect parameter between two [EffectSlot] snapshots.
class ParameterDiff {
  final int paramIndex;
  final String paramName;
  final double beforeRaw;
  final double afterRaw;
  final String beforeFormatted;
  final String afterFormatted;

  const ParameterDiff({
    required this.paramIndex,
    required this.paramName,
    required this.beforeRaw,
    required this.afterRaw,
    required this.beforeFormatted,
    required this.afterFormatted,
  });
}

/// Difference for a single signal-chain slot between two [Patch] snapshots.
class SlotDiff {
  final int? baseIndex;
  final int? targetIndex;
  final EffectSlot? baseSlot;
  final EffectSlot? targetSlot;
  final SlotDiffKind kind;
  final ({bool before, bool after})? bypassChange;
  final List<ParameterDiff> parameterDiffs;

  const SlotDiff({
    this.baseIndex,
    this.targetIndex,
    this.baseSlot,
    this.targetSlot,
    required this.kind,
    this.bypassChange,
    this.parameterDiffs = const [],
  });

  int get slotIndex => targetIndex ?? baseIndex ?? 0;

  bool get hasChanges => kind != SlotDiffKind.unchanged;

  String get displayEffectName {
    if (kind == SlotDiffKind.removed) {
      return baseSlot?.effectName ?? 'Empty';
    }
    return targetSlot?.effectName ?? baseSlot?.effectName ?? 'Empty';
  }
}

/// Structured comparison between a [base] and [target] [Patch].
///
/// Pure Dart model with zero Flutter or platform dependencies.
class PatchDiff {
  final Patch base;
  final Patch target;
  final ({String before, String after})? nameChange;
  final ({int before, int after})? tempoChange;
  final List<SlotDiff> slotDiffs;

  const PatchDiff({
    required this.base,
    required this.target,
    this.nameChange,
    this.tempoChange,
    this.slotDiffs = const [],
  });

  /// Computes a deterministic [PatchDiff] from [base] to [target].
  factory PatchDiff.compute(
    Patch base,
    Patch target, {
    bool includeHidden = false,
  }) {
    final nameDiff = base.name != target.name
        ? (before: base.name, after: target.name)
        : null;
    final tempoDiff = base.tempo != target.tempo
        ? (before: base.tempo, after: target.tempo)
        : null;

    final maxSlots = math.max(base.slots.length, target.slots.length);
    final slots = <SlotDiff>[];

    for (int i = 0; i < maxSlots; i++) {
      if (i >= base.slots.length) {
        slots.add(
          SlotDiff(
            targetIndex: i,
            targetSlot: target.slots[i],
            kind: SlotDiffKind.added,
          ),
        );
        continue;
      }
      if (i >= target.slots.length) {
        slots.add(
          SlotDiff(
            baseIndex: i,
            baseSlot: base.slots[i],
            kind: SlotDiffKind.removed,
          ),
        );
        continue;
      }

      final baseSlot = base.slots[i];
      final targetSlot = target.slots[i];

      if (baseSlot.effectId != targetSlot.effectId) {
        slots.add(
          SlotDiff(
            baseIndex: i,
            targetIndex: i,
            baseSlot: baseSlot,
            targetSlot: targetSlot,
            kind: SlotDiffKind.replaced,
          ),
        );
        continue;
      }

      final bypassDiff = baseSlot.isEnabled != targetSlot.isEnabled
          ? (before: baseSlot.isEnabled, after: targetSlot.isEnabled)
          : null;

      final paramCount = math.min(
        baseSlot.parameters.length,
        targetSlot.parameters.length,
      );
      final paramDiffs = <ParameterDiff>[];
      for (int p = 0; p < paramCount; p++) {
        final bp = baseSlot.parameters[p];
        final tp = targetSlot.parameters[p];
        final isHidden = bp.descriptor.name.toLowerCase().startsWith('hidden');
        if (isHidden && !includeHidden) {
          continue;
        }
        if ((bp.currentValue - tp.currentValue).abs() > 0.05) {
          paramDiffs.add(
            ParameterDiff(
              paramIndex: p,
              paramName: tp.descriptor.name,
              beforeRaw: bp.currentValue,
              afterRaw: tp.currentValue,
              beforeFormatted: bp.descriptor.formatValue(bp.currentValue),
              afterFormatted: tp.descriptor.formatValue(tp.currentValue),
            ),
          );
        }
      }

      final kind = (bypassDiff != null || paramDiffs.isNotEmpty)
          ? SlotDiffKind.modified
          : SlotDiffKind.unchanged;

      slots.add(
        SlotDiff(
          baseIndex: i,
          targetIndex: i,
          baseSlot: baseSlot,
          targetSlot: targetSlot,
          kind: kind,
          bypassChange: bypassDiff,
          parameterDiffs: paramDiffs,
        ),
      );
    }

    return PatchDiff(
      base: base,
      target: target,
      nameChange: nameDiff,
      tempoChange: tempoDiff,
      slotDiffs: List.unmodifiable(slots),
    );
  }

  /// True if any metadata, slot structure, bypass state, or parameter differs.
  bool get hasChanges =>
      nameChange != null ||
      tempoChange != null ||
      slotDiffs.any((s) => s.hasChanges);

  /// Number of slots with structural, bypass, or parameter changes.
  int get changedSlotCount => slotDiffs.where((s) => s.hasChanges).length;

  /// Total number of modified parameters across modified slots.
  int get totalChangedParameters =>
      slotDiffs.fold<int>(0, (sum, s) => sum + s.parameterDiffs.length);

  /// Total count of logical change items (metadata fields + changed slots).
  int get totalChangeCount =>
      (nameChange != null ? 1 : 0) +
      (tempoChange != null ? 1 : 0) +
      changedSlotCount;

  /// Concise human-readable summary for badges and buttons.
  String get summaryLabel {
    if (!hasChanges) return 'Identical';
    final count = totalChangeCount;
    return '$count change${count == 1 ? '' : 's'}';
  }
}

