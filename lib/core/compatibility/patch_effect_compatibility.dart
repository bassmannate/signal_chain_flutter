import 'package:flutter/foundation.dart';

import '../../models/device_family.dart';
import '../../models/effect_slot.dart';
import '../../models/patch.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../../protocols/catalogs/line6_bass_pod_pro_catalog.dart';

/// Describes an effect slot within a [Patch] that is not available on the
/// target hardware model / scanned pedal inventory.
@immutable
class MissingEffectSlot {
  final int slotIndex;
  final EffectSlot slot;
  final EffectDefinition? resolvedDefinition;
  final String displayName;
  final String? originLabel;

  const MissingEffectSlot({
    required this.slotIndex,
    required this.slot,
    required this.resolvedDefinition,
    required this.displayName,
    this.originLabel,
  });

  /// Normalized DSP effect identifier (uppercase `0xXXXXXXXX` for Zoom hex IDs).
  String get formattedEffectId =>
      PatchEffectCompatibility.normalizeEffectId(slot.effectId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissingEffectSlot &&
          runtimeType == other.runtimeType &&
          slotIndex == other.slotIndex &&
          slot == other.slot &&
          resolvedDefinition == other.resolvedDefinition &&
          displayName == other.displayName &&
          originLabel == other.originLabel;

  @override
  int get hashCode => Object.hash(
        slotIndex,
        slot,
        resolvedDefinition,
        displayName,
        originLabel,
      );

  @override
  String toString() =>
      'MissingEffectSlot(slotIndex: $slotIndex, displayName: "$displayName", '
      'origin: $originLabel, id: $formattedEffectId)';
}

/// Compatibility analysis report for a [Patch] evaluated against a target
/// [DeviceFamily] and optional scanned hardware onboard effect inventory.
@immutable
class PatchEffectCompatibilityReport {
  final bool isVerifiedByHardwareScan;
  final List<MissingEffectSlot> missingSlots;

  const PatchEffectCompatibilityReport({
    required this.isVerifiedByHardwareScan,
    this.missingSlots = const [],
  });

  static const PatchEffectCompatibilityReport empty =
      PatchEffectCompatibilityReport(isVerifiedByHardwareScan: false);

  bool get hasMissingEffects => missingSlots.isNotEmpty;

  Set<int> get missingSlotIndices => {
        for (final slot in missingSlots) slot.slotIndex,
      };

  /// Returns the [MissingEffectSlot] matching 0-based [slotIndex], or `null`.
  MissingEffectSlot? missingSlotAt(int slotIndex) {
    for (final slot in missingSlots) {
      if (slot.slotIndex == slotIndex) return slot;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatchEffectCompatibilityReport &&
          runtimeType == other.runtimeType &&
          isVerifiedByHardwareScan == other.isVerifiedByHardwareScan &&
          listEquals(missingSlots, other.missingSlots);

  @override
  int get hashCode => Object.hash(
        isVerifiedByHardwareScan,
        Object.hashAll(missingSlots),
      );

  @override
  String toString() =>
      'PatchEffectCompatibilityReport(verified: $isVerifiedByHardwareScan, '
      'missingCount: ${missingSlots.length})';
}

/// Pure, centralized analyzer and safe slot-stripping helper for detecting
/// missing/uninstalled effects relative to a target pedal.
abstract final class PatchEffectCompatibility {
  static final RegExp _hexPattern = RegExp(r'^[0-9a-f]+$');
  static final Set<String> _line6BuiltInIds = {
    for (final def in Line6BassPodProCatalog.builtInEffects)
      def.effectId.trim().toLowerCase(),
  };

  /// Normalizes Zoom hex DSP IDs to uppercase `0xXXXXXXXX` form; preserves
  /// non-hex IDs trimmed.
  static String normalizeEffectId(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    final lower = clean.toLowerCase();
    final hexPart = lower.startsWith('0x') ? lower.substring(2) : lower;
    if (hexPart.isNotEmpty && _hexPattern.hasMatch(hexPart)) {
      final parsed = int.tryParse(hexPart, radix: 16);
      if (parsed != null) {
        return '0x${parsed.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      }
    }
    return clean;
  }

  /// Returns true if [rawEffectId] represents an empty/bypass Zoom slot
  /// (`0x00000000`, `0x00000001`, empty string, or `'bypass'`).
  static bool isBypassOrEmptyEffectId(String rawEffectId) {
    final lower = rawEffectId.trim().toLowerCase();
    if (lower.isEmpty || lower == 'bypass') return true;
    final hexPart = lower.startsWith('0x') ? lower.substring(2) : lower;
    if (hexPart.isNotEmpty && _hexPattern.hasMatch(hexPart)) {
      final parsed = int.tryParse(hexPart, radix: 16);
      if (parsed == 0 || parsed == 1) {
        return true;
      }
    }
    return false;
  }

  /// Analyzes [patch] against [targetFamily] and optional [installedEffectIds]
  /// (from `DeviceConnectionController.installedEffectIds`).
  static PatchEffectCompatibilityReport analyze(
    Patch patch,
    DeviceFamily targetFamily, [
    Set<String>? installedEffectIds,
  ]) {
    if (targetFamily == DeviceFamily.unknown) {
      return PatchEffectCompatibilityReport.empty;
    }

    if (targetFamily.isZoom6E) {
      final missing = <MissingEffectSlot>[];
      if (installedEffectIds != null) {
        final normalizedInstalled = <String>{
          for (final id in installedEffectIds) normalizeEffectId(id),
        };
        for (int i = 0; i < patch.slots.length; i++) {
          final slot = patch.slots[i];
          if (isBypassOrEmptyEffectId(slot.effectId)) continue;
          final normId = normalizeEffectId(slot.effectId);
          if (!normalizedInstalled.contains(normId)) {
            missing.add(_buildMissingSlot(i, slot, targetFamily));
          }
        }
        return PatchEffectCompatibilityReport(
          isVerifiedByHardwareScan: true,
          missingSlots: List.unmodifiable(missing),
        );
      }

      for (int i = 0; i < patch.slots.length; i++) {
        final slot = patch.slots[i];
        if (isBypassOrEmptyEffectId(slot.effectId)) continue;
        if (!EffectCatalogRegistry.isStockEffect(targetFamily, slot.effectId)) {
          missing.add(_buildMissingSlot(i, slot, targetFamily));
        }
      }
      return PatchEffectCompatibilityReport(
        isVerifiedByHardwareScan: false,
        missingSlots: List.unmodifiable(missing),
      );
    }

    if (targetFamily.isLine6BassPodPro) {
      final missing = <MissingEffectSlot>[];
      for (int i = 0; i < patch.slots.length; i++) {
        final slot = patch.slots[i];
        if (isBypassOrEmptyEffectId(slot.effectId)) continue;
        final key = slot.effectId.trim().toLowerCase();
        if (!_line6BuiltInIds.contains(key)) {
          missing.add(_buildMissingSlot(i, slot, targetFamily));
        }
      }
      return PatchEffectCompatibilityReport(
        isVerifiedByHardwareScan: false,
        missingSlots: List.unmodifiable(missing),
      );
    }

    return PatchEffectCompatibilityReport.empty;
  }

  static MissingEffectSlot _buildMissingSlot(
    int slotIndex,
    EffectSlot slot,
    DeviceFamily targetFamily,
  ) {
    final def = EffectCatalogRegistry.getDefinition(targetFamily, slot.effectId);
    final isKnown = def.origin != EffectOrigin.unknown;
    final normalizedId = normalizeEffectId(slot.effectId);

    final String displayName;
    if (isKnown && def.name.trim().isNotEmpty) {
      displayName = def.name.trim();
    } else {
      final idLabel = normalizedId.isNotEmpty ? normalizedId : slot.effectId.trim();
      displayName = 'Unknown ($idLabel)';
    }

    final String? originLabel;
    switch (def.origin) {
      case EffectOrigin.crossModel:
        originLabel = (def.sourceModelLabel?.trim().isNotEmpty == true)
            ? def.sourceModelLabel!.trim()
            : 'Cross-Model';
      case EffectOrigin.custom:
        originLabel = 'Custom';
      case EffectOrigin.stock:
      case EffectOrigin.unknown:
        originLabel = null;
    }

    return MissingEffectSlot(
      slotIndex: slotIndex,
      slot: slot,
      resolvedDefinition: isKnown ? def : null,
      displayName: displayName,
      originLabel: originLabel,
    );
  }

  /// Returns a new [Patch] with slots at [missingIndices] removed and MS+
  /// `rightOutputTapCode` shifted accurately using the same invariant as
  /// `PatchEditorController.removeEffectSlot`.
  ///
  /// Never mutates [patch] or its collections.
  static Patch stripMissingSlots(Patch patch, Set<int> missingIndices) {
    final validSortedDesc = missingIndices
        .where((idx) => idx >= 0 && idx < patch.slots.length)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (validSortedDesc.isEmpty) {
      return patch;
    }

    final remainingSlots = List<EffectSlot>.from(patch.slots);
    int tapCode = patch.deviceFamily.isZoomMsPlus
        ? patch.rightOutputTapCode
        : RightOutputTap.endOfChain;

    for (final idx in validSortedDesc) {
      remainingSlots.removeAt(idx);
      if (patch.deviceFamily.isZoomMsPlus) {
        tapCode = RightOutputTap.adjustForRemovedSlot(
          tapCode,
          removedIndex: idx,
          newSlotCount: remainingSlots.length,
        );
      }
    }

    if (!patch.deviceFamily.isLine6BassPodPro) {
      for (int i = 0; i < remainingSlots.length; i++) {
        remainingSlots[i] = remainingSlots[i].copyWith(slotIndex: i);
      }
    }

    Map<String, dynamic> updatedMetadata = patch.metadata;
    if (patch.metadata.containsKey('activeEffectSlot')) {
      final rawActive = patch.metadata['activeEffectSlot'];
      final nextActive = remainingSlots.isEmpty
          ? 0
          : ((rawActive is num ? rawActive.toInt() : 0)
              .clamp(0, remainingSlots.length - 1));
      updatedMetadata = Map<String, dynamic>.from(patch.metadata);
      updatedMetadata['activeEffectSlot'] = nextActive;
    }

    return patch.copyWith(
      slots: remainingSlots,
      rightOutputTapCode: patch.deviceFamily.isZoomMsPlus
          ? tapCode
          : RightOutputTap.endOfChain,
      metadata: updatedMetadata,
    );
  }
}

