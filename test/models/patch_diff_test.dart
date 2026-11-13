import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/models/patch_diff.dart';

void main() {
  Patch buildBasePatch() {
    return const Patch(
      id: 'base',
      name: 'Base Tone',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      metadata: {'tempo': 120},
      slots: [
        EffectSlot(
          slotIndex: 0,
          effectId: '0x01000010',
          effectName: 'DYN Comp',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p0',
                name: 'Sense',
                min: 0,
                max: 10,
                defaultValue: 5,
              ),
              currentValue: 5.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p1',
                name: 'Hidden-1',
                min: 0,
                max: 100,
                defaultValue: 0,
              ),
              currentValue: 0.0,
            ),
          ],
        ),
        EffectSlot(
          slotIndex: 1,
          effectId: '0x02000010',
          effectName: 'Bass Drive',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p0',
                name: 'Gain',
                min: 0,
                max: 100,
                defaultValue: 40,
                displayOffset: 1,
              ),
              currentValue: 40.0,
            ),
          ],
        ),
      ],
    );
  }

  group('PatchDiff', () {
    test('reports identical patches with hasChanges = false', () {
      final base = buildBasePatch();
      final diff = PatchDiff.compute(base, base.copyWith());

      expect(diff.hasChanges, isFalse);
      expect(diff.summaryLabel, equals('Identical'));
      expect(diff.changedSlotCount, equals(0));
      expect(diff.totalChangedParameters, equals(0));
    });

    test('detects metadata, bypass, parameter formatting, and hidden param filtering', () {
      final base = buildBasePatch();
      final modifiedSlots = [
        base.slots[0].copyWith(
          isEnabled: false,
          parameters: [
            base.slots[0].parameters[0].copyWith(currentValue: 8.0),
            base.slots[0].parameters[1].copyWith(currentValue: 99.0),
          ],
        ),
        base.slots[1].copyWith(
          parameters: [
            base.slots[1].parameters[0].copyWith(currentValue: 60.0),
          ],
        ),
      ];
      final target = base.copyWith(
        name: 'Lead Tone',
        metadata: const {'tempo': 135},
        slots: modifiedSlots,
      );

      final diffDefault = PatchDiff.compute(base, target);
      expect(diffDefault.hasChanges, isTrue);
      expect(diffDefault.nameChange, equals((before: 'Base Tone', after: 'Lead Tone')));
      expect(diffDefault.tempoChange, equals((before: 120, after: 135)));
      expect(diffDefault.changedSlotCount, equals(2));
      expect(diffDefault.totalChangedParameters, equals(2));
      expect(diffDefault.slotDiffs[0].kind, equals(SlotDiffKind.modified));
      expect(diffDefault.slotDiffs[0].bypassChange, equals((before: true, after: false)));
      expect(diffDefault.slotDiffs[1].parameterDiffs.first.beforeFormatted, equals('41'));
      expect(diffDefault.slotDiffs[1].parameterDiffs.first.afterFormatted, equals('61'));

      final diffWithHidden = PatchDiff.compute(base, target, includeHidden: true);
      expect(diffWithHidden.totalChangedParameters, equals(3));
    });

    test('detects added, removed, and replaced slots across varying chain lengths', () {
      final base = buildBasePatch();
      final extraSlot = const EffectSlot(
        slotIndex: 2,
        effectId: '0x09000010',
        effectName: 'Hall Reverb',
        isEnabled: true,
      );

      final targetAdded = base.copyWith(
        slots: [
          base.slots[0].copyWith(effectId: '0x03000010', effectName: 'OptoComp'),
          base.slots[1],
          extraSlot,
        ],
      );

      final diffAdded = PatchDiff.compute(base, targetAdded);
      expect(diffAdded.slotDiffs[0].kind, equals(SlotDiffKind.replaced));
      expect(diffAdded.slotDiffs[1].kind, equals(SlotDiffKind.unchanged));
      expect(diffAdded.slotDiffs[2].kind, equals(SlotDiffKind.added));

      final targetRemoved = base.copyWith(slots: [base.slots[0]]);
      final diffRemoved = PatchDiff.compute(base, targetRemoved);
      expect(diffRemoved.slotDiffs[1].kind, equals(SlotDiffKind.removed));
    });
  });
}

