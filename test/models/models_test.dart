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
  });
}

