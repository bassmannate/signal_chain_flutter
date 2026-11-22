import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUp(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
  });

  group('4-Tier Effect Resolution in EffectCatalogRegistry', () {
    test('Tier 1: active MS-60B+ stock effect resolves as EffectOrigin.stock', () {
      final dynComp = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x01000010',
      );
      expect(dynComp.name, equals('DYN Comp'));
      expect(dynComp.origin, equals(EffectOrigin.stock));
      expect(dynComp.sourceModelLabel, isNull);
      expect(dynComp.parameters, isNotEmpty);
    });

    test('Tier 2: MS-50G+ and MS-70CDR+ sibling effects resolve as crossModel under MS-60B+', () {
      // 0x030000E0 (TB MK1.5) is in MS-50G+, not MS-60B+
      final from50g = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x030000E0',
      );
      expect(from50g.name, equals('TB MK1.5'));
      expect(from50g.origin, equals(EffectOrigin.crossModel));
      expect(from50g.sourceModelLabel, equals('MS-50G+'));
      expect(from50g.parameters, isNotEmpty);

      // 0x01000048 (160 Comp) is in MS-70CDR+, not MS-60B+ or MS-50G+
      final from70cdr = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x01000048',
      );
      expect(from70cdr.name, equals('160 Comp'));
      expect(from70cdr.origin, equals(EffectOrigin.crossModel));
      expect(from70cdr.sourceModelLabel, equals('MS-70CDR+'));
      expect(from70cdr.parameters, isNotEmpty);

      // Zoom Four sibling: B1X FOUR Pedal effect (PDL Vol 0x0B000010) resolved under B1 FOUR
      final pedalOnB1 = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomB1Four,
        '0x0B000010',
      );
      expect(pedalOnB1.name, equals('PDL Vol'));
      expect(pedalOnB1.origin, equals(EffectOrigin.crossModel));
      expect(pedalOnB1.sourceModelLabel, equals('B1X FOUR'));
      expect(pedalOnB1.parameters, isNotEmpty);
    });

    test('Tier 3: custom .ZD2 effect resolves as custom, updates Custom category dynamically, and excludes Line 6', () {
      // Hidden when empty
      expect(
        EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus),
        isNot(contains('Custom')),
      );
      final beforeRev = EffectCatalogRegistry.catalogRevision.value;

      const customDef = EffectDefinition(
        effectId: '0x04000999',
        name: 'MY NAM',
        category: 'Custom',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        origin: EffectOrigin.custom,
        sourceModelLabel: 'Custom',
        sourceFilename: 'MY_NAM.ZD2',
        version: '1.10',
        description: 'Neural bass rig',
        parameters: [
          ParameterDescriptor(id: 'gain_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
          ParameterDescriptor(id: 'level_1', name: 'Level', min: 0, max: 100, defaultValue: 75),
        ],
      );

      EffectCatalogRegistry.registerCustomEffect(
        customDef,
        generation: DeviceGeneration.zoomMsPlus,
      );

      expect(EffectCatalogRegistry.catalogRevision.value, greaterThan(beforeRev));

      final resolved = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x04000999',
      );
      expect(resolved.origin, equals(EffectOrigin.custom));
      expect(resolved.name, equals('MY NAM'));
      expect(resolved.sourceModelLabel, equals('Custom'));
      expect(resolved.sourceFilename, equals('MY_NAM.ZD2'));
      expect(resolved.parameters.length, equals(2));

      // Appears in Custom category for MS+ families
      expect(
        EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus),
        contains('Custom'),
      );
      expect(
        EffectCatalogRegistry.getEffects(DeviceFamily.zoomMs60bPlus)
            .any((e) => e.effectId == '0x04000999'),
        isTrue,
      );
      // Never leaks into Line 6
      expect(
        EffectCatalogRegistry.getCategories(DeviceFamily.line6BassPodPro),
        isNot(contains('Custom')),
      );
      expect(
        EffectCatalogRegistry.getEffects(DeviceFamily.line6BassPodPro)
            .any((e) => e.effectId == '0x04000999'),
        isFalse,
      );

      // Disappears cleanly when removed
      final removed = EffectCatalogRegistry.unregisterCustomEffect('0x04000999');
      expect(removed, isTrue);
      expect(
        EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus),
        isNot(contains('Custom')),
      );
      expect(
        EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x04000999').origin,
        equals(EffectOrigin.unknown),
      );
    });

    test('Tier 3 beats param-less ZoomZdl7MasterCatalog (Tier 4) fallback on Zoom Four', () {
      // 0x01000010 is in ZDL7 master table (Comp, 0 params), not B1X FOUR 99-effect stock catalog
      final tier4 = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomB1xFour,
        '0x01000010',
      );
      expect(tier4.name, equals('Comp'));
      expect(tier4.origin, equals(EffectOrigin.crossModel));
      expect(tier4.sourceModelLabel, equals('Zoom Four'));
      expect(tier4.parameters, isEmpty);

      // Register custom .ZD2 for 0x01000010 with PRME parameters -> Tier 3 wins!
      EffectCatalogRegistry.registerCustomEffect(
        const EffectDefinition(
          effectId: '0x01000010',
          name: 'Comp Custom',
          category: 'Custom',
          deviceFamily: DeviceFamily.zoomB1xFour,
          origin: EffectOrigin.custom,
          parameters: [
            ParameterDescriptor(id: 'sense_0', name: 'Sense', min: 0, max: 10, defaultValue: 5),
            ParameterDescriptor(id: 'level_1', name: 'Level', min: 0, max: 100, defaultValue: 80),
          ],
        ),
        generation: DeviceGeneration.zoomFour,
      );

      final tier3 = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomB1xFour,
        '0x01000010',
      );
      expect(tier3.origin, equals(EffectOrigin.custom));
      expect(tier3.name, equals('Comp Custom'));
      expect(tier3.sourceModelLabel, equals('Custom'));
      expect(tier3.parameters.length, equals(2));
    });

    test('Unknown ID resolves to EffectOrigin.unknown with lossless 12-param PTCF round-trip and auto-resolves cross-model/custom in decodePtcf', () {
      const proto = ZoomMsPlusProtocol(defaultFamily: DeviceFamily.zoomMs60bPlus);

      // 1. Unknown ID lossless 12-parameter round-trip
      const unknownId = '0x0D000999';
      expect(
        EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, unknownId).origin,
        equals(EffectOrigin.unknown),
      );

      final rawParams = [
        for (int i = 0; i < 12; i++)
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'param_$i',
              name: 'Param ${i + 1}',
              min: 0,
              max: (i < 5 || i >= 8) ? 4095 : 255,
              defaultValue: 0,
            ),
            currentValue: (10 + i * 7).toDouble(),
          ),
      ];

      final unknownPatch = Patch(
        id: 'ptcf_unk',
        name: 'UNK TEST',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: unknownId,
            effectName: 'Unknown Effect ($unknownId)',
            isEnabled: true,
            parameters: rawParams,
          ),
          const EffectSlot(
            slotIndex: 1,
            effectId: '0x030000E0', // Cross-model MS-50G+ TB MK1.5
            effectName: 'Placeholder',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'p0', name: 'P0', min: 0, max: 100, defaultValue: 0),
                currentValue: 42,
              ),
            ],
          ),
        ],
      );

      final encoded = proto.encodePtcf(unknownPatch);
      final decoded = proto.decodePtcf(encoded);

      // Slot 0: still unknown -> all 12 values preserved losslessly
      expect(decoded.slots[0].parameters.length, equals(12));
      for (int i = 0; i < 12; i++) {
        expect(decoded.slots[0].parameters[i].currentValue, equals((10 + i * 7).toDouble()));
      }

      // Slot 1: cross-model MS-50G+ automatically decoded with real name and parameter schema!
      expect(decoded.slots[1].effectName, equals('TB MK1.5'));
      expect(decoded.slots[1].parameters.first.descriptor.name, isNot(startsWith('Param ')));
      expect(decoded.slots[1].parameters.first.currentValue, equals(42));
    });
  });

  group('PatchEditorController.refreshEffectDefinitionsFromCatalog', () {
    test('upgrades an Unknown Effect slot to custom name & parameters while preserving knob values and dirty state', () {
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
        enableHotPlugPolling: false,
        isTest: true,
      );

      final initialPatch = Patch(
        id: 'open_patch',
        name: 'Custom Rig',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x04000999',
            effectName: 'Unknown Effect (0x04000999)',
            isEnabled: true,
            parameters: [
              for (int i = 0; i < 12; i++)
                ParameterValue(
                  descriptor: ParameterDescriptor(
                    id: 'param_$i',
                    name: 'Param ${i + 1}',
                    min: 0,
                    max: 100,
                    defaultValue: 0,
                  ),
                  currentValue: (i * 5 + 10).toDouble(),
                ),
            ],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: initialPatch,
      );

      addTearDown(() async {
        editor.dispose();
        connection.dispose();
        await transport.dispose();
      });

      expect(editor.isDirty, isFalse);
      expect(editor.patch!.slots.first.effectName, equals('Unknown Effect (0x04000999)'));

      // Import custom .ZD2 into registry
      EffectCatalogRegistry.registerCustomEffect(
        const EffectDefinition(
          effectId: '0x04000999',
          name: 'MY NAM',
          category: 'Custom',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          origin: EffectOrigin.custom,
          parameters: [
            ParameterDescriptor(id: 'gain_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
            ParameterDescriptor(id: 'bass_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
            ParameterDescriptor(id: 'level_2', name: 'Level', min: 0, max: 100, defaultValue: 75),
          ],
        ),
        generation: DeviceGeneration.zoomMsPlus,
      );

      final changed = editor.refreshEffectDefinitionsFromCatalog();
      expect(changed, isTrue);
      expect(editor.isDirty, isFalse); // Must preserve clean dirty state!

      final upgradedSlot = editor.patch!.slots.first;
      expect(upgradedSlot.effectName, equals('MY NAM'));
      expect(upgradedSlot.parameters.length, equals(3));
      expect(upgradedSlot.parameters[0].descriptor.name, equals('Gain'));
      expect(upgradedSlot.parameters[0].currentValue, equals(10.0));
      expect(upgradedSlot.parameters[1].descriptor.name, equals('Bass'));
      expect(upgradedSlot.parameters[1].currentValue, equals(15.0));
      expect(upgradedSlot.parameters[2].descriptor.name, equals('Level'));
      expect(upgradedSlot.parameters[2].currentValue, equals(20.0));
      // Remaining 9 raw values preserved losslessly in rawTrailingValues
      expect(upgradedSlot.rawTrailingValues, isNotNull);
      expect(upgradedSlot.rawTrailingValues!.length, equals(9));
      expect(upgradedSlot.rawTrailingValues!.first, equals(25.0));

      // Removing the custom effect reverts cleanly while keeping all 12 values intact
      EffectCatalogRegistry.unregisterCustomEffect('0x04000999');
      expect(editor.refreshEffectDefinitionsFromCatalog(), isTrue);
      final revertedSlot = editor.patch!.slots.first;
      expect(revertedSlot.effectName, equals('Unknown Effect (0x04000999)'));
      expect(revertedSlot.parameters.length, equals(12));
      expect(revertedSlot.parameters[0].currentValue, equals(10.0));
      expect(revertedSlot.parameters[3].currentValue, equals(25.0));
    });
  });
}

