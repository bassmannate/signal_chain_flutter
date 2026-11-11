import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/catalogs/zoom_ms_plus_catalog.dart';

void main() {
  setUp(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('EffectCatalogRegistry - Zoom MS Plus', () {
    test('resolves known Zoom MS-60B+ dynamics effect with discrete labels and ranges', () {
      final dynComp = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x01000010',
      );

      expect(dynComp.name, equals('DYN Comp'));
      expect(dynComp.category, equals('Dynamics'));
      expect(dynComp.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));
      expect(dynComp.parameters, isNotEmpty);

      // Verify parameter descriptors
      final sense = dynComp.parameters.firstWhere((p) => p.name == 'Sense');
      expect(sense.min, equals(0));
      expect(sense.max, equals(10));
      expect(sense.defaultValue, equals(6));

      final attack = dynComp.parameters.firstWhere((p) => p.name == 'Attack');
      expect(attack.isDiscrete, isTrue);
      expect(attack.labels, equals(['SLOW', 'FAST']));
    });

    test('resolves known Zoom amp model (AMPG SVT)', () {
      final svt = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x05000020',
      );

      expect(svt.name, equals('AMPG SVT'));
      expect(svt.category, equals('Amp Model'));
      expect(svt.parameters, isNotEmpty);
      expect(svt.parameters.any((p) => p.name == 'Gain'), isTrue);
    });

    test('resolves effect without 0x prefix identically', () {
      final withPrefix = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x0A000010',
      );
      final withoutPrefix = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0a000010',
      );

      expect(withPrefix.name, equals('Delay'));
      expect(withoutPrefix.name, equals('Delay'));
      expect(withPrefix, equals(withoutPrefix));
    });

    test('returns clean fallback definition for unknown effect ID', () {
      final unknown = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x99999999',
      );

      expect(unknown.name, equals('Unknown Effect (0x99999999)'));
      expect(unknown.category, equals('Unknown'));
      expect(unknown.parameters, isEmpty);
    });

    test('returns clean Bypass definition for zero IDs', () {
      final bypassHex = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x00000000',
      );
      final bypassZero = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0',
      );

      expect(bypassHex.name, equals('Bypass'));
      expect(bypassHex.category, equals('Bypass'));
      expect(bypassZero.name, equals('Bypass'));
      expect(bypassZero.category, equals('Bypass'));
    });
  });

  group('EffectCatalogRegistry - Line 6 Bass Pod Pro', () {
    test('resolves Amp models and standard parameters', () {
      final tubePre = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_amp_0',
      );
      final svt = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_amp_1',
      );

      expect(tubePre.name, equals('Tube Preamp'));
      expect(tubePre.category, equals('Amp Model'));
      expect(svt.name, equals('Classic (SVT)'));

      // Check Amp parameters: Drive, Bass, Mid, Treble, Channel Volume
      expect(svt.parameters.length, equals(5));
      expect(svt.parameters[0].name, equals('Drive'));
      expect(svt.parameters[1].name, equals('Bass'));
      expect(svt.parameters[2].name, equals('Mid'));
      expect(svt.parameters[3].name, equals('Treble'));
      expect(svt.parameters[4].name, equals('Channel Volume'));
    });

    test('resolves Cabinet models and discrete selection parameters', () {
      final cab = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_cab_6',
      );

      expect(cab.name, equals('8x10 1974 Classic'));
      expect(cab.category, equals('Cabinet'));
      expect(cab.parameters.length, equals(1));
      expect(cab.parameters.first.isDiscrete, isTrue);
      expect(cab.parameters.first.labels, contains('8x10 1974 Classic'));
    });

    test('resolves Compressor block and parameters', () {
      final comp = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_comp',
      );

      expect(comp.name, equals('Compressor'));
      expect(comp.category, equals('Dynamics'));
      expect(comp.parameters.length, equals(2));
      expect(comp.parameters[0].name, equals('Threshold / Ratio'));
      expect(comp.parameters[1].name, equals('Compressor State'));
    });

    test('resolves Modulation / Delay FX blocks', () {
      final chorus = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_fx_1',
      );
      final delay = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_fx_6',
      );

      expect(chorus.name, equals('Chorus'));
      expect(chorus.category, equals('Modulation'));
      expect(delay.name, equals('Delay'));
      expect(delay.category, equals('Delay'));
    });

    test('returns clean fallback for unmapped Line 6 ID', () {
      final unmapped = EffectCatalogRegistry.getDefinition(
        DeviceFamily.line6BassPodPro,
        'line6_unknown_slot',
      );

      expect(unmapped.name, equals('Unknown Effect (line6_unknown_slot)'));
      expect(unmapped.category, equals('Unknown'));
      expect(unmapped.parameters, isEmpty);
    });
  });

  group('Catalog Utilities & Categories', () {
    test('extracts sorted unique categories for device family', () {
      final zoomCategories = EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus);
      expect(zoomCategories, contains('Dynamics'));
      expect(zoomCategories, contains('Amp Model'));
      expect(zoomCategories, contains('Modulation'));
      expect(zoomCategories, contains('Delay'));
      expect(zoomCategories, contains('Reverb'));

      final line6Categories = EffectCatalogRegistry.getCategories(DeviceFamily.line6BassPodPro);
      expect(line6Categories, contains('Amp Model'));
      expect(line6Categories, contains('Cabinet'));
      expect(line6Categories, contains('Dynamics'));
    });

    test('EffectDefinition copyWith preserves attributes immutably', () {
      final original = ZoomMsPlusCatalog.builtInEffects.first;
      final modified = original.copyWith(name: 'Custom Name');

      expect(original.name, isNot(equals('Custom Name')));
      expect(modified.name, equals('Custom Name'));
      expect(modified.effectId, equals(original.effectId));
      expect(modified.category, equals(original.category));
    });
  });
}
