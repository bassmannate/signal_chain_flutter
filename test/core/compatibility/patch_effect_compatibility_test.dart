import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/compatibility/patch_effect_compatibility.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
  });

  EffectSlot makeSlot(int index, String effectId, {String name = 'Slot'}) {
    return EffectSlot(
      slotIndex: index,
      effectId: effectId,
      effectName: name,
      isEnabled: true,
      parameters: const [
        ParameterValue(
          descriptor: ParameterDescriptor(
            id: 'p0',
            name: 'Level',
            min: 0,
            max: 100,
            defaultValue: 50,
          ),
          currentValue: 50,
        ),
      ],
    );
  }

  group('PatchEffectCompatibility.analyze', () {
    test('verified hardware scan accepts stock, installed cross-model, installed custom .ZD2, and bypass/empty slots while flagging uninstalled effects', () {
      // Register custom .ZD2 effect in Tier 3 registry (0x04000999 installed, 0x04000888 uninstalled)
      EffectCatalogRegistry.registerCustomEffect(
        const EffectDefinition(
          effectId: '0x04000999',
          name: 'Installed NAM',
          category: 'Custom',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          origin: EffectOrigin.custom,
          sourceModelLabel: 'Custom',
        ),
        generation: DeviceGeneration.zoomMsPlus,
      );
      EffectCatalogRegistry.registerCustomEffect(
        const EffectDefinition(
          effectId: '0x04000888',
          name: 'Missing NAM',
          category: 'Custom',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          origin: EffectOrigin.custom,
          sourceModelLabel: 'Custom',
        ),
        generation: DeviceGeneration.zoomMsPlus,
      );

      // 0x01000010 = DYN Comp (stock MS-60B+, installed)
      // 0x01000020 = BlackOpt (stock MS-60B+, NOT in scanned installedEffectIds)
      // 0x030000E0 = TB MK1.5 (MS-50G+ cross-model, installed)
      // 0x030000F0 = GoldDrive (MS-50G+ cross-model, NOT installed)
      // 0x04000999 = Installed NAM (custom, installed)
      // 0x04000888 = Missing NAM (custom, NOT installed)
      // 0x09999999 = Unknown DSP ID (NOT installed)
      final patch = Patch(
        id: 'scan_test',
        name: 'Scan Test',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          makeSlot(0, '0x01000010', name: 'DYN Comp'),
          makeSlot(1, '0x00000000', name: 'Bypass 0'),
          makeSlot(2, '0x00000001', name: 'Bypass 1'),
          makeSlot(3, '', name: 'Empty'),
          makeSlot(4, 'bypass', name: 'Bypass Str'),
          makeSlot(5, '0x030000e0', name: 'TB MK1.5'), // lowercase hex normalized
          makeSlot(6, '0x04000999', name: 'Installed NAM'),
          makeSlot(7, '0x01000020', name: 'BlackOpt'),
          makeSlot(8, '0x030000f0', name: 'GoldDrive'),
          makeSlot(9, '0x04000888', name: 'Missing NAM'),
          makeSlot(10, '0x09999999', name: 'Mystery'),
        ],
      );

      final installedIds = <String>{
        '0x01000010',
        '0x030000E0',
        '0x04000999',
      };

      final report = PatchEffectCompatibility.analyze(
        patch,
        DeviceFamily.zoomMs60bPlus,
        installedIds,
      );

      expect(report.isVerifiedByHardwareScan, isTrue);
      expect(report.hasMissingEffects, isTrue);
      expect(report.missingSlotIndices, equals({7, 8, 9, 10}));

      final uninstalledStock = report.missingSlotAt(7)!;
      expect(uninstalledStock.displayName, equals('BlackOpt'));
      expect(uninstalledStock.originLabel, isNull);
      expect(uninstalledStock.resolvedDefinition, isNotNull);

      final uninstalledCross = report.missingSlotAt(8)!;
      expect(uninstalledCross.originLabel, equals('MS-50G+'));
      expect(uninstalledCross.resolvedDefinition, isNotNull);
      expect(uninstalledCross.displayName, equals(uninstalledCross.resolvedDefinition!.name));

      final uninstalledCustom = report.missingSlotAt(9)!;
      expect(uninstalledCustom.displayName, equals('Missing NAM'));
      expect(uninstalledCustom.originLabel, equals('Custom'));
      expect(uninstalledCustom.resolvedDefinition, isNotNull);

      final unknown = report.missingSlotAt(10)!;
      expect(unknown.displayName, equals('Unknown (0x09999999)'));
      expect(unknown.originLabel, isNull);
      expect(unknown.resolvedDefinition, isNull);
      expect(unknown.formattedEffectId, equals('0x09999999'));
    });

    test('Zoom Four hardware scan mode allows installed stock/ZDL7 and flags uninstalled effects', () {
      final patch = Patch(
        id: 'four_scan',
        name: 'Four Scan',
        deviceFamily: DeviceFamily.zoomB1xFour,
        slots: [
          makeSlot(0, '0x01000010', name: 'Comp'),
          makeSlot(1, '0x04890070', name: 'Pre1073'),
        ],
      );

      final report = PatchEffectCompatibility.analyze(
        patch,
        DeviceFamily.zoomB1xFour,
        const {'0x01000010'},
      );
      expect(report.isVerifiedByHardwareScan, isTrue);
      expect(report.missingSlotIndices, equals({1}));
      expect(report.missingSlotAt(1)!.displayName, equals('Pre1073'));
      expect(report.missingSlotAt(1)!.originLabel, isNotNull);
    });

    test('fallback mode (installedEffectIds == null) accepts stock, ignores bypass, and flags non-stock with isVerifiedByHardwareScan == false', () {
      EffectCatalogRegistry.registerCustomEffect(
        const EffectDefinition(
          effectId: '0x04000999',
          name: 'Custom Amp',
          category: 'Custom',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          origin: EffectOrigin.custom,
          sourceModelLabel: 'Custom',
        ),
        generation: DeviceGeneration.zoomMsPlus,
      );

      final patch = Patch(
        id: 'fallback_test',
        name: 'Fallback Test',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          makeSlot(0, '0x01000010', name: 'DYN Comp'),
          makeSlot(1, '0x00000000', name: 'Bypass'),
          makeSlot(2, '0x00000001', name: 'Empty'),
          makeSlot(3, '0x030000E0', name: 'TB MK1.5'),
          makeSlot(4, '0x04000999', name: 'Custom Amp'),
          makeSlot(5, '0x09999999', name: 'Unknown'),
        ],
      );

      final report = PatchEffectCompatibility.analyze(
        patch,
        DeviceFamily.zoomMs60bPlus,
      );

      expect(report.isVerifiedByHardwareScan, isFalse);
      expect(report.hasMissingEffects, isTrue);
      expect(report.missingSlotIndices, equals({3, 4, 5}));
      expect(report.missingSlotAt(3)!.originLabel, equals('MS-50G+'));
      expect(report.missingSlotAt(4)!.originLabel, equals('Custom'));
      expect(report.missingSlotAt(5)!.displayName, equals('Unknown (0x09999999)'));
    });

    test('Line 6 Bass POD Pro checks built-in effect IDs and ignores bypass/empty', () {
      final patch = Patch(
        id: 'l6_test',
        name: 'Line 6 Test',
        deviceFamily: DeviceFamily.line6BassPodPro,
        slots: [
          makeSlot(0, 'line6_amp_8', name: 'Rock Classic'),
          makeSlot(1, 'line6_cab_10', name: 'Bypass'),
          makeSlot(2, 'line6_comp', name: 'Compressor'),
          makeSlot(3, 'line6_fx_5', name: 'S/H + Driver'),
          makeSlot(4, '0x01000010', name: 'Zoom Comp'),
          makeSlot(5, '0x00000000', name: 'Bypass Slot'),
        ],
      );

      final report = PatchEffectCompatibility.analyze(
        patch,
        DeviceFamily.line6BassPodPro,
      );

      expect(report.isVerifiedByHardwareScan, isFalse);
      expect(report.missingSlotIndices, equals({4}));
    });

    test('DeviceFamily.unknown returns empty report', () {
      final patch = Patch(
        id: 'u',
        name: 'Unknown',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [makeSlot(0, '0x09999999')],
      );
      final report = PatchEffectCompatibility.analyze(patch, DeviceFamily.unknown);
      expect(report.hasMissingEffects, isFalse);
      expect(report.missingSlots, isEmpty);
    });
  });

  group('PatchEffectCompatibility.stripMissingSlots & R-Out Invariants', () {
    Patch makeChainPatch({
      DeviceFamily family = DeviceFamily.zoomMs60bPlus,
      int slotCount = 5,
      int rightOutputTapCode = RightOutputTap.endOfChain,
      Map<String, dynamic> metadata = const {'tempo': 120},
    }) {
      return Patch(
        id: 'strip_patch',
        name: 'Strip Test',
        deviceFamily: family,
        rightOutputTapCode: rightOutputTapCode,
        metadata: metadata,
        slots: [
          for (int i = 0; i < slotCount; i++)
            makeSlot(i, '0x010000${i + 1}0', name: 'FX $i'),
        ],
      );
    }

    test('never mutates original Patch and preserves metadata / re-indexes surviving slots', () {
      final original = makeChainPatch(
        slotCount: 4,
        rightOutputTapCode: RightOutputTap.afterSlot(2), // code 4
        metadata: {'tempo': 128, 'activeEffectSlot': 3},
      );

      final stripped = PatchEffectCompatibility.stripMissingSlots(original, {1});

      expect(original.slots.length, equals(4));
      expect(original.rightOutputTapCode, equals(4));
      expect(original.metadata['activeEffectSlot'], equals(3));

      expect(stripped.slots.length, equals(3));
      expect(stripped.slots.map((s) => s.effectName), equals(['FX 0', 'FX 2', 'FX 3']));
      expect(stripped.slots.map((s) => s.slotIndex), equals([0, 1, 2]));
      expect(stripped.rightOutputTapCode, equals(3));
      expect(stripped.metadata['activeEffectSlot'], equals(2));
    });

    test('R-Out End of Chain (0) and IN (1) invariants across partial and complete removal', () {
      final endPatch = makeChainPatch(
        slotCount: 4,
        rightOutputTapCode: RightOutputTap.endOfChain,
      );
      expect(
        PatchEffectCompatibility.stripMissingSlots(endPatch, {1, 2}).rightOutputTapCode,
        equals(RightOutputTap.endOfChain),
      );

      final inPatch = makeChainPatch(
        slotCount: 4,
        rightOutputTapCode: RightOutputTap.input,
      );
      final partialIn = PatchEffectCompatibility.stripMissingSlots(inPatch, {0, 3});
      expect(partialIn.slots.length, equals(2));
      expect(partialIn.rightOutputTapCode, equals(RightOutputTap.input));

      final emptyIn = PatchEffectCompatibility.stripMissingSlots(inPatch, {0, 1, 2, 3});
      expect(emptyIn.slots, isEmpty);
      expect(emptyIn.rightOutputTapCode, equals(RightOutputTap.endOfChain));
    });

    test('R-Out tap BEFORE removed slot stays put unless tapped slot becomes final slot (then normalizes to 0)', () {
      // 4 slots (0..3), tap after slot 1 (code = 3)
      final patch = makeChainPatch(
        slotCount: 4,
        rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3
      );

      // Remove slot 3 -> surviving slots [0,1,2]; slot 1 is still non-final -> tap stays 3
      final rmLast = PatchEffectCompatibility.stripMissingSlots(patch, {3});
      expect(rmLast.slots.length, equals(3));
      expect(rmLast.rightOutputTapCode, equals(3));

      // Remove slots 2 and 3 -> surviving slots [0,1]; slot 1 is now final -> normalizes to 0
      final rmTail = PatchEffectCompatibility.stripMissingSlots(patch, {2, 3});
      expect(rmTail.slots.length, equals(2));
      expect(rmTail.rightOutputTapCode, equals(RightOutputTap.endOfChain));
    });

    test('R-Out tap ON removed slot resets cleanly to End of Chain (0)', () {
      // 4 slots (0..3), tap after slot 1 (code = 3)
      final patch = makeChainPatch(
        slotCount: 4,
        rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3
      );

      // Remove slot 1 itself -> resets to 0
      final rmTapped = PatchEffectCompatibility.stripMissingSlots(patch, {1});
      expect(rmTapped.slots.length, equals(3));
      expect(rmTapped.rightOutputTapCode, equals(RightOutputTap.endOfChain));

      // Remove slots 0 and 1 -> resets to 0
      final rmMultipleIncludingTapped = PatchEffectCompatibility.stripMissingSlots(patch, {0, 1});
      expect(rmMultipleIncludingTapped.slots.length, equals(2));
      expect(rmMultipleIncludingTapped.rightOutputTapCode, equals(RightOutputTap.endOfChain));
    });

    test('R-Out tap AFTER removed slot(s) decrements by exact removed count before tap', () {
      // 5 slots (0..4), tap after slot 3 (code = 5)
      final patch = makeChainPatch(
        slotCount: 5,
        rightOutputTapCode: RightOutputTap.afterSlot(3), // code 5
      );

      // Remove slot 0 and slot 2 (both < slot 3) -> surviving [1, 3, 4], old slot 3 is now index 1 -> code 3
      final stripped = PatchEffectCompatibility.stripMissingSlots(patch, {0, 2});
      expect(stripped.slots.map((s) => s.effectName), equals(['FX 1', 'FX 3', 'FX 4']));
      expect(stripped.rightOutputTapCode, equals(RightOutputTap.afterSlot(1)));
      expect(stripped.rightOutputTapCode, equals(3));
    });

    test('removing all slots yields empty chain and R-Out == 0', () {
      final patch = makeChainPatch(
        slotCount: 3,
        rightOutputTapCode: RightOutputTap.afterSlot(0), // code 2
      );
      final stripped = PatchEffectCompatibility.stripMissingSlots(patch, {0, 1, 2});
      expect(stripped.slots, isEmpty);
      expect(stripped.rightOutputTapCode, equals(RightOutputTap.endOfChain));
    });

    test('Line 6 preserves surviving slotIndex values for Amp/Cab/Comp/FX mapping', () {
      final l6Patch = Patch(
        id: 'l6',
        name: 'Line6',
        deviceFamily: DeviceFamily.line6BassPodPro,
        slots: [
          makeSlot(0, 'line6_amp_0', name: 'Amp'),
          makeSlot(1, 'invalid_cab', name: 'Bad Cab'),
          makeSlot(3, 'line6_fx_0', name: 'Phase'),
        ],
      );
      final stripped = PatchEffectCompatibility.stripMissingSlots(l6Patch, {1});
      expect(stripped.slots.length, equals(2));
      expect(stripped.slots[0].slotIndex, equals(0));
      expect(stripped.slots[1].slotIndex, equals(3));
      expect(stripped.rightOutputTapCode, equals(RightOutputTap.endOfChain));
    });
  });
}

