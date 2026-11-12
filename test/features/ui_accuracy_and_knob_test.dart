import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/rotary_knob_widget.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/features/editor/slot_inspector_widget.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('UI Accuracy & Rotary Knob Tests', () {
    testWidgets('Right-to-Left signal chain rendering: IN on right, Slot 1 rightmost, OUT on left', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(transport: transport);

      const testPatch = Patch(
        id: 'rtl_test_patch',
        name: 'RTL Chain',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000010',
            effectName: 'DYN Comp',
            isEnabled: true,
            parameters: [],
          ),
          EffectSlot(
            slotIndex: 1,
            effectId: '0x02000010',
            effectName: 'Bass Preamp',
            isEnabled: true,
            parameters: [],
          ),
          EffectSlot(
            slotIndex: 2,
            effectId: '0x05000020',
            effectName: 'AMPG SVT',
            isEnabled: true,
            parameters: [],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: testPatch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalChainStripWidget(controller: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find locations of IN badge, Slot 0, Slot 1, Slot 2, and OUT badge
      final inOffset = tester.getTopLeft(find.text('IN'));
      final slot0Offset = tester.getTopLeft(find.byKey(const Key('effect_slot_0')));
      final slot1Offset = tester.getTopLeft(find.byKey(const Key('effect_slot_1')));
      final slot2Offset = tester.getTopLeft(find.byKey(const Key('effect_slot_2')));
      final outOffset = tester.getTopLeft(find.text('OUT'));

      // In Right-to-Left order:
      // OUT is leftmost < Slot 2 < Slot 1 < Slot 0 < IN is rightmost
      expect(outOffset.dx, lessThan(slot2Offset.dx));
      expect(slot2Offset.dx, lessThan(slot1Offset.dx));
      expect(slot1Offset.dx, lessThan(slot0Offset.dx));
      expect(slot0Offset.dx, lessThan(inOffset.dx));

      // Verify insertion zones are positioned correctly in RTL sequence
      final zone0Offset = tester.getTopLeft(find.byKey(const Key('insertion_zone_0')));
      final zone1Offset = tester.getTopLeft(find.byKey(const Key('insertion_zone_1')));
      final zone2Offset = tester.getTopLeft(find.byKey(const Key('insertion_zone_2')));
      final zone3Offset = tester.getTopLeft(find.byKey(const Key('insertion_zone_3')));

      // Insertion zone 0 is between Slot 0 and IN
      expect(slot0Offset.dx, lessThan(zone0Offset.dx));
      expect(zone0Offset.dx, lessThan(inOffset.dx));

      // Insertion zone 1 is between Slot 1 and Slot 0
      expect(slot1Offset.dx, lessThan(zone1Offset.dx));
      expect(zone1Offset.dx, lessThan(slot0Offset.dx));

      // Insertion zone 2 is between Slot 2 and Slot 1
      expect(slot2Offset.dx, lessThan(zone2Offset.dx));
      expect(zone2Offset.dx, lessThan(slot1Offset.dx));

      // Insertion zone 3 is to the left of Slot 2
      expect(zone3Offset.dx, lessThan(slot2Offset.dx));

      editor.dispose();
      connection.dispose();
    });

    testWidgets('SlotInspectorWidget only renders known catalog parameters (not 12 padded parameters)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(transport: transport);

      // DYN Comp has 4 defined parameters: Sense, Attack, Tone, VOL
      final dynCompDef = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x01000010');
      expect(dynCompDef.parameters.length, equals(4));

      final testPatch = Patch(
        id: 'inspector_test_patch',
        name: 'Inspector',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000010',
            effectName: 'DYN Comp',
            isEnabled: true,
            parameters: dynCompDef.parameters.map((d) => ParameterValue(descriptor: d, currentValue: d.defaultValue)).toList(),
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: testPatch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: SlotInspectorWidget(controller: editor),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly 4 RotaryKnobWidgets should be rendered for DYN Comp (NOT 12)
      final knobs = find.byType(RotaryKnobWidget);
      expect(knobs, findsNWidgets(4));
      expect(find.text('Sense'), findsOneWidget);
      expect(find.text('Attack'), findsOneWidget);
      expect(find.text('Tone'), findsOneWidget);
      expect(find.text('VOL'), findsOneWidget);
      expect(find.text('Param 5'), findsNothing);
      expect(find.text('Param 12'), findsNothing);

      editor.dispose();
      connection.dispose();
    });

    test('Sequence Filter (SeqFLTR) parameter offsets and value lookups match pedal screen', () {
      final seqDef = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x02000070');
      expect(seqDef.name, equals('SeqFLTR'));
      expect(seqDef.parameters.length, equals(4));

      // 1. Step parameter: raw 0..6 displays as "2".."8" (displayOffset = 2)
      final stepDesc = seqDef.parameters[0];
      expect(stepDesc.name, equals('Step'));
      expect(stepDesc.displayOffset, equals(2));
      expect(stepDesc.formatValue(0), equals('2'));
      expect(stepDesc.formatValue(3), equals('5'));
      expect(stepDesc.formatValue(6), equals('8'));

      // 2. Pattern parameter: raw 0..7 displays as "1".."8" (displayOffset = 1)
      final patternDesc = seqDef.parameters[1];
      expect(patternDesc.name, equals('Pattern'));
      expect(patternDesc.displayOffset, equals(1));
      expect(patternDesc.formatValue(0), equals('1'));
      expect(patternDesc.formatValue(4), equals('5'));
      expect(patternDesc.formatValue(7), equals('8'));

      // 3. Speed parameter: raw 0 displays as "1", raw 49 displays as "50", raw 57 displays note "♩"
      final speedDesc = seqDef.parameters[2];
      expect(speedDesc.name, equals('Speed'));
      expect(speedDesc.formatValue(0), equals('1'));
      expect(speedDesc.formatValue(49), equals('50'));
      expect(speedDesc.formatValue(57), equals('♩'));

      // 4. RESO parameter: raw 0 displays as "0", raw 10 displays as "10"
      final resoDesc = seqDef.parameters[3];
      expect(resoDesc.name, equals('RESO'));
      expect(resoDesc.formatValue(0), equals('0'));
      expect(resoDesc.formatValue(10), equals('10'));
    });

    test('ZoomMsPlusProtocol preserves raw trailing values losslessly across PTCF encode/decode', () {
      const protocol = ZoomMsPlusProtocol();

      // Create a slot with 4 catalog parameters and 8 trailing raw values (note: params 5..7 are 8-bit)
      final dynCompDef = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x01000010');
      final originalSlot = EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [
          ParameterValue(descriptor: dynCompDef.parameters[0], currentValue: 7.0),
          ParameterValue(descriptor: dynCompDef.parameters[1], currentValue: 1.0),
          ParameterValue(descriptor: dynCompDef.parameters[2], currentValue: 55.0),
          ParameterValue(descriptor: dynCompDef.parameters[3], currentValue: 80.0),
        ],
        rawTrailingValues: [123.0, 200.0, 210.0, 220.0, 300.0, 400.0, 500.0, 600.0],
      );

      final originalPatch = Patch(
        id: 'roundtrip_patch',
        name: 'Lossless',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [originalSlot],
      );

      final encoded = protocol.encodePatch(originalPatch);
      final decoded = protocol.decodePatch(encoded);

      expect(decoded.slots.length, equals(1));
      final decodedSlot = decoded.slots.first;
      expect(decodedSlot.parameters.length, equals(4));
      expect(decodedSlot.parameters[0].currentValue, equals(7.0));
      expect(decodedSlot.parameters[1].currentValue, equals(1.0));
      expect(decodedSlot.parameters[2].currentValue, equals(55.0));
      expect(decodedSlot.parameters[3].currentValue, equals(80.0));
      expect(decodedSlot.rawTrailingValues, isNotNull);
      expect(decodedSlot.rawTrailingValues!.length, equals(8));
      expect(decodedSlot.rawTrailingValues![0], equals(123.0));
      expect(decodedSlot.rawTrailingValues![1], equals(200.0));
    });

    testWidgets('RotaryKnobWidget adjusts value on vertical drag and mouse scroll wheel', (tester) async {
      int updatedValue = 5;

      const desc = ParameterDescriptor(
        id: 'test_param',
        name: 'Gain',
        min: 0,
        max: 10,
        defaultValue: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return RotaryKnobWidget(
                    param: ParameterValue(descriptor: desc, currentValue: updatedValue.toDouble()),
                    paramIndex: 0,
                    slotIndex: 0,
                    accentColor: Colors.amber,
                    onChanged: (val) {
                      setState(() => updatedValue = val);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gain'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      // 1. Test vertical drag upward: increases value
      await tester.drag(find.byType(RotaryKnobWidget), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(updatedValue, greaterThan(5));

      // 2. Test double tap: resets to default value (5)
      await tester.tap(find.byType(RotaryKnobWidget));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(RotaryKnobWidget));
      await tester.pumpAndSettle();
      expect(updatedValue, equals(5));

      // 3. Test mouse scroll wheel: scroll up increments value
      final knobCenter = tester.getCenter(find.byType(RotaryKnobWidget));
      await tester.sendEventToBinding(PointerScrollEvent(
        position: knobCenter,
        scrollDelta: const Offset(0, -20),
      ));
      await tester.pumpAndSettle();
      expect(updatedValue, equals(6));

      // 4. Test mouse scroll wheel: scroll down decrements value
      await tester.sendEventToBinding(PointerScrollEvent(
        position: knobCenter,
        scrollDelta: const Offset(0, 20),
      ));
      await tester.pumpAndSettle();
      expect(updatedValue, equals(5));
    });
  });
}
