import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/catalogs/zoom_ms_plus_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  group('Zoom MS-60B+ Full Effect Catalog Tests', () {
    test('contains full count of 98 effects and preserves backward compatibility', () {
      expect(ZoomMsPlusCatalog.builtInEffects.length, equals(98));
      expect(ZoomMsPlusCatalog.allEffects.length, equals(98));
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
  });

  group('Multi-Pedal Zoom MS Plus Catalogs (MS-60B+, MS-50G+, MS-70CDR+, MS-200D+)', () {
    test('populates exact effect counts across all four MS Plus pedals', () {
      expect(EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs60bPlus).length, equals(98));
      expect(EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs50gPlus).length, equals(106));
      expect(EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs70cdrPlus).length, equals(150));
      expect(EffectCatalogRegistry.getEffectsForFamily(DeviceFamily.zoomMs200dPlus).length, equals(224));

      expect(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs60bPlus).length, equals(98));
      expect(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs50gPlus).length, equals(106));
      expect(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs70cdrPlus).length, equals(150));
      expect(ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs200dPlus).length, equals(224));
    });

    test('resolves MS-50G+ effects, categories, displayOffset, and discrete labels', () {
      final comp = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs50gPlus, '0x01000010');
      expect(comp.name, equals('Comp'));
      expect(comp.category, equals('Dynamics'));
      expect(comp.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
      final attack = comp.parameters.firstWhere((p) => p.name == 'ATTCK');
      expect(attack.isDiscrete, isTrue);
      expect(attack.labels, equals(['SLOW', 'FAST']));

      final rackComp = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs50gPlus, '0x01000020');
      expect(rackComp.name, equals('RackComp'));
      final ratio = rackComp.parameters.firstWhere((p) => p.name == 'Ratio');
      expect(ratio.displayOffset, equals(1));
      expect(ratio.formatValue(0), equals('1'));
      expect(ratio.formatValue(5), equals('6'));

      final ms800 = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs50gPlus, '0x04000031');
      expect(ms800.name, equals('MS 800'));
      expect(ms800.category, equals('Amp Model'));

      final delay = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs50gPlus, '0x08000010');
      expect(delay.name, equals('Delay'));
      expect(delay.category, equals('Delay'));
    });

    test('resolves MS-70CDR+ effects and categories cleanly', () {
      final rackComp = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs70cdrPlus, '0x01000020');
      expect(rackComp.name, equals('RackComp'));
      expect(rackComp.deviceFamily, equals(DeviceFamily.zoomMs70cdrPlus));
      final ratio = rackComp.parameters.firstWhere((p) => p.name == 'Ratio');
      expect(ratio.displayOffset, equals(1));

      final coronaCho = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs70cdrPlus, '0x06000038');
      expect(coronaCho.name, equals('CoronaCho'));
      expect(coronaCho.category, equals('Modulation'));

      final fdSpring = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs70cdrPlus, '0x09000040');
      expect(fdSpring.name, equals('FD Spring'));
      expect(fdSpring.category, equals('Reverb'));
    });

    test('resolves MS-200D+ overlaid full names and categories cleanly', () {
      final fatBoost = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x01000010');
      expect(fatBoost.name, equals('FAT BOOST'));
      expect(fatBoost.category, equals('Boost / Drive'));
      expect(fatBoost.deviceFamily, equals(DeviceFamily.zoomMs200dPlus));

      final desertDrive = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x02000010');
      expect(desertDrive.name, equals('DESERT DRIVE'));
      expect(desertDrive.category, equals('Overdrive'));

      final shakerFuzz = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x04000010');
      expect(shakerFuzz.name, equals('SHAKER FUZZ'));
      expect(shakerFuzz.category, equals('Fuzz'));

      final gtGeq = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x06000030');
      expect(gtGeq.name, equals('GUITAR GRAPHIC EQ'));
      expect(gtGeq.category, equals('Filter / EQ'));

      final noiseGate = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x06000010');
      expect(noiseGate.name, equals('NOISE GATE'));
      expect(noiseGate.category, equals('Dynamics'));

      final bpm = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x07000ff0');
      expect(bpm.name, equals('BPM'));
      expect(bpm.category, equals('Special / SFX'));

      final plusDist = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs200dPlus, '0x1d000e00');
      expect(plusDist.name, equals('PLUS DIST'));
      expect(plusDist.category, equals('Drive / Distortion'));

      // Verify zero unreplaced "CMN 0" placeholders remain
      final all200d = ZoomMsPlusCatalog.effectsForFamily(DeviceFamily.zoomMs200dPlus);
      expect(all200d.any((e) => e.name.startsWith('CMN ')), isFalse);
    });
  });
}
