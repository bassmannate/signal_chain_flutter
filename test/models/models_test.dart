import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';

void main() {
  group('DeviceFamily', () {
    test('contains correct device metadata and family helpers', () {
      expect(DeviceFamily.zoomMs60bPlus.displayName, equals('Zoom MS-60B+'));
      expect(DeviceFamily.zoomMs60bPlus.manufacturer, equals('Zoom'));
      expect(DeviceFamily.zoomMs60bPlus.maxEffectSlots, equals(6));
      expect(DeviceFamily.zoomMs60bPlus.isZoomMsPlus, isTrue);
      expect(DeviceFamily.zoomMs60bPlus.isLine6BassPodPro, isFalse);

      expect(DeviceFamily.line6BassPodPro.displayName, equals('Line 6 Bass Pod Pro'));
      expect(DeviceFamily.line6BassPodPro.manufacturer, equals('Line 6'));
      expect(DeviceFamily.line6BassPodPro.maxEffectSlots, equals(4));
      expect(DeviceFamily.line6BassPodPro.isLine6BassPodPro, isTrue);
      expect(DeviceFamily.line6BassPodPro.isZoomMsPlus, isFalse);
    });
  });

  group('ParameterDescriptor & ParameterValue', () {
    test('computes normalized values and formatted display strings for continuous params', () {
      const gainDesc = ParameterDescriptor(
        id: 'gain',
        name: 'Gain',
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: '%',
      );

      final paramVal = const ParameterValue(descriptor: gainDesc, currentValue: 25);
      expect(paramVal.normalizedValue, closeTo(0.25, 0.001));
      expect(paramVal.displayValue, equals('25 %'));

      // Test clamping
      final clampedOver = const ParameterValue(descriptor: gainDesc, currentValue: 120);
      expect(clampedOver.normalizedValue, equals(1.0));

      final clampedUnder = const ParameterValue(descriptor: gainDesc, currentValue: -10);
      expect(clampedUnder.normalizedValue, equals(0.0));
    });

    test('resolves discrete labels for enumerated parameters', () {
      const ampModelDesc = ParameterDescriptor(
        id: 'amp_model',
        name: 'Amp Model',
        min: 0,
        max: 2,
        defaultValue: 0,
        labels: ['SVT', 'Bassman', 'FlipTop'],
      );

      expect(ampModelDesc.isDiscrete, isTrue);

      final p0 = const ParameterValue(descriptor: ampModelDesc, currentValue: 0);
      expect(p0.displayValue, equals('SVT'));

      final p2 = const ParameterValue(descriptor: ampModelDesc, currentValue: 2);
      expect(p2.displayValue, equals('FlipTop'));
    });

    test('copyWith updates value immutably', () {
      const driveDesc = ParameterDescriptor(
        id: 'drive',
        name: 'Drive',
        min: 0,
        max: 10,
        defaultValue: 5,
      );

      final original = const ParameterValue(descriptor: driveDesc, currentValue: 3);
      final updated = original.copyWith(currentValue: 8);

      expect(original.currentValue, equals(3));
      expect(updated.currentValue, equals(8));
      expect(updated.descriptor, equals(original.descriptor));
      expect(original, isNot(equals(updated)));
    });
  });

  group('EffectSlot', () {
    test('supports immutability, copyWith, and value equality', () {
      const param = ParameterValue(
        descriptor: ParameterDescriptor(
          id: 'depth',
          name: 'Depth',
          min: 0,
          max: 100,
          defaultValue: 50,
        ),
        currentValue: 70,
      );

      const slot1 = EffectSlot(
        slotIndex: 0,
        effectId: 'chorus_01',
        effectName: 'Stereo Chorus',
        isEnabled: true,
        parameters: [param],
      );

      const slot2 = EffectSlot(
        slotIndex: 0,
        effectId: 'chorus_01',
        effectName: 'Stereo Chorus',
        isEnabled: true,
        parameters: [param],
      );

      expect(slot1, equals(slot2));
      expect(slot1.hashCode, equals(slot2.hashCode));

      final toggled = slot1.copyWith(isEnabled: false);
      expect(toggled.isEnabled, isFalse);
      expect(slot1.isEnabled, isTrue);
      expect(slot1, isNot(equals(toggled)));
    });
  });

  group('Patch', () {
    test('supports immutability, copyWith, and full chain value equality', () {
      const slot = EffectSlot(
        slotIndex: 0,
        effectId: 'compressor_01',
        effectName: 'Opto Comp',
        isEnabled: true,
      );

      const patch1 = Patch(
        id: 'p_001',
        name: 'Punchy Slap',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        programNumber: 1,
        slots: [slot],
        metadata: {'tempo': 120},
      );

      const patch2 = Patch(
        id: 'p_001',
        name: 'Punchy Slap',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        programNumber: 1,
        slots: [slot],
        metadata: {'tempo': 120},
      );

      expect(patch1, equals(patch2));
      expect(patch1.hashCode, equals(patch2.hashCode));

      final renamed = patch1.copyWith(name: 'Smooth Slap');
      expect(patch1.name, equals('Punchy Slap'));
      expect(renamed.name, equals('Smooth Slap'));
      expect(patch1, isNot(equals(renamed)));
    });

    test('supports optional searchable metadata fields and copyWith', () {
      final now = DateTime.utc(2026, 11, 10, 12, 0, 0);
      final patch = Patch(
        id: 'p_meta',
        name: 'Slap & Pop',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        tags: const ['bass', 'funk', 'slap'],
        author: 'Marcus',
        notes: 'Great with active J-Bass',
        updatedAt: now,
      );

      expect(patch.tags, equals(['bass', 'funk', 'slap']));
      expect(patch.author, equals('Marcus'));
      expect(patch.notes, equals('Great with active J-Bass'));
      expect(patch.updatedAt, equals(now));

      final updated = patch.copyWith(
        author: 'Flea',
        tags: ['bass', 'rock'],
      );

      expect(updated.author, equals('Flea'));
      expect(updated.tags, equals(['bass', 'rock']));
      expect(updated.notes, equals('Great with active J-Bass'));
    });
  });

  group('JSON Serialization Round-Trip', () {
    test('DeviceFamily serializes to string key and deserializes with unknown fallback', () {
      expect(DeviceFamily.zoomMs60bPlus.toJson(), equals('zoomMs60bPlus'));
      expect(DeviceFamily.line6BassPodPro.toJson(), equals('line6BassPodPro'));

      expect(DeviceFamily.fromJson('zoomMs60bPlus'), equals(DeviceFamily.zoomMs60bPlus));
      expect(DeviceFamily.fromJson('line6BassPodPro'), equals(DeviceFamily.line6BassPodPro));
      expect(DeviceFamily.fromJson('nonExistentFamily'), equals(DeviceFamily.unknown));
      expect(DeviceFamily.fromJson(null), equals(DeviceFamily.unknown));
      expect(DeviceFamily.fromJson(123), equals(DeviceFamily.unknown));
    });

    test('ParameterDescriptor and ParameterValue round-trip through JSON cleanly', () {
      const desc = ParameterDescriptor(
        id: 'ratio',
        name: 'Ratio',
        min: 1.0,
        max: 20.0,
        defaultValue: 4.0,
        step: 0.5,
        unit: ':1',
        labels: ['2:1', '4:1', '8:1', '20:1'],
      );

      final descJson = desc.toJson();
      final restoredDesc = ParameterDescriptor.fromJson(descJson);
      expect(restoredDesc, equals(desc));

      const paramVal = ParameterValue(descriptor: desc, currentValue: 8.0);
      final paramValJson = paramVal.toJson();
      final restoredParamVal = ParameterValue.fromJson(paramValJson);
      expect(restoredParamVal, equals(paramVal));
      expect(restoredParamVal.currentValue, equals(8.0));
    });

    test('EffectSlot round-trips through JSON cleanly', () {
      const slot = EffectSlot(
        slotIndex: 2,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'sense',
              name: 'Sense',
              min: 0,
              max: 10,
              defaultValue: 6,
            ),
            currentValue: 7,
          ),
        ],
      );

      final json = slot.toJson();
      final restored = EffectSlot.fromJson(json);
      expect(restored, equals(slot));
      expect(restored.parameters.length, equals(1));
      expect(restored.parameters.first.currentValue, equals(7.0));
    });

    test('Patch round-trips through JSON including rich metadata, tags, and timestamps', () {
      final now = DateTime.utc(2026, 11, 10, 18, 30, 0);
      final patch = Patch(
        id: 'patch_vintage_svt',
        name: 'Vintage SVT Rig',
        deviceFamily: DeviceFamily.line6BassPodPro,
        programNumber: 12,
        tags: const ['vintage', 'rock', 'ampeg'],
        author: 'John Paul Jones',
        notes: 'Classic warm tube growl for fingerstyle',
        updatedAt: now,
        metadata: const {'tempo': 118, 'rating': 5},
        slots: const [
          EffectSlot(
            slotIndex: 0,
            effectId: 'line6_amp_1',
            effectName: 'Classic (SVT)',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(
                  id: 'drive',
                  name: 'Drive',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 80,
              ),
            ],
          ),
        ],
      );

      final json = patch.toJson();
      final restored = Patch.fromJson(json);

      expect(restored, equals(patch));
      expect(restored.tags, equals(['vintage', 'rock', 'ampeg']));
      expect(restored.author, equals('John Paul Jones'));
      expect(restored.notes, equals('Classic warm tube growl for fingerstyle'));
      expect(restored.updatedAt, equals(now));
      expect(restored.metadata['tempo'], equals(118));
      expect(restored.slots.first.effectName, equals('Classic (SVT)'));
    });
  });
}

