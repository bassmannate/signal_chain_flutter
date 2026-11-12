import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/catalogs/zoom_ms_plus_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('Zoom MS-60B+ Full Effect Catalog Tests', () {
    test('contains full count of 98 effects', () {
      expect(ZoomMsPlusCatalog.builtInEffects.length, equals(98));
      final registered = EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs60bPlus);
      expect(registered.length, equals(98));
    });

    test('covers all 11 MS-60B+ sound categories', () {
      final categories = ZoomMsPlusCatalog.categories;
      expect(categories, containsAll([
        'Amp Model',
        'Bass Synth',
        'Delay',
        'Drive / Distortion',
        'Dynamics',
        'Filter / EQ',
        'Modulation',
        'Pitch / Octave',
        'Preamp',
        'Reverb',
        'Special / SFX',
      ]));
    });

    test('verifies category filtering', () {
      final dynamics = ZoomMsPlusCatalog.getByCategory('Dynamics');
      expect(dynamics.length, equals(10));
      for (final e in dynamics) {
        expect(e.category, equals('Dynamics'));
        expect(e.effectId.startsWith('0x01'), isTrue);
      }

      final amps = ZoomMsPlusCatalog.getByCategory('Amp Model');
      expect(amps.length, equals(11));
      for (final e in amps) {
        expect(e.category, equals('Amp Model'));
        expect(e.effectId.startsWith('0x05'), isTrue);
      }

      final reverbs = ZoomMsPlusCatalog.getByCategory('Reverb');
      expect(reverbs.length, equals(6));
    });

    test('looks up effects by int ID and hex string ID', () {
      // DYN Comp: 0x01000010 = 16777232
      final byInt = ZoomMsPlusCatalog.getByIntId(0x01000010);
      expect(byInt, isNotNull);
      expect(byInt!.name, equals('DYN Comp'));
      expect(byInt.intEffectId, equals(0x01000010));

      final byHex = ZoomMsPlusCatalog.getById('0x01000010');
      expect(byHex, equals(byInt));

      final byBareHex = ZoomMsPlusCatalog.getById('01000010');
      expect(byBareHex, equals(byInt));
    });

    test('verifies AMPG SVT parameters and discrete multi-band labels', () {
      final svt = ZoomMsPlusCatalog.getById('0x05000020');
      expect(svt, isNotNull);
      expect(svt!.name, equals('AMPG SVT'));
      expect(svt.parameters.length, greaterThanOrEqualTo(8));

      final ultra = svt.parameters.firstWhere((p) => p.name == 'Ultra');
      expect(ultra.isDiscrete, isTrue);
      expect(ultra.labels, equals(['OFF', 'LOW', 'HI', 'BOTH', 'CUT']));

      final midFreq = svt.parameters.firstWhere((p) => p.name == 'MID-FREQ');
      expect(midFreq.isDiscrete, isTrue);
      expect(midFreq.labels!.length, equals(32));
      expect(midFreq.labels!.first, equals('32Hz'));
      expect(midFreq.labels!.last, equals('6.3kHz'));
    });

    test('searches effect catalog with query and optional category filter', () {
      final svtResults = ZoomMsPlusCatalog.search('svt');
      expect(svtResults.any((e) => e.name == 'AMPG SVT'), isTrue);

      final delayInReverb = ZoomMsPlusCatalog.search('Delay', category: 'Reverb');
      expect(delayInReverb, isEmpty);

      final delayInDelay = ZoomMsPlusCatalog.search('Delay', category: 'Delay');
      expect(delayInDelay.isNotEmpty, isTrue);
    });

    test('populates catalog for all Zoom MS Plus family models', () {
      final ms50gEffects = EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs50gPlus);
      expect(ms50gEffects.length, equals(98));

      final ms70cdrEffects = EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs70cdrPlus);
      expect(ms70cdrEffects.length, equals(98));

      final ms200dEffects = EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs200dPlus);
      expect(ms200dEffects.length, equals(98));
    });
  });
}

