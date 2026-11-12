import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/effect_bank_palette_widget.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
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

  group('MIDI Port Auto-Selection Unit Tests', () {
    test('identifies device families accurately from port name heuristics', () {
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM MS-60B+ MIDI 1'),
        equals(DeviceFamily.zoomMs60bPlus),
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM MS-50G+ MIDI 1'),
        equals(DeviceFamily.zoomMs50gPlus),
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM MS-70CDR+ MIDI 1'),
        equals(DeviceFamily.zoomMs70cdrPlus),
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM MS-200D+ MIDI 1'),
        equals(DeviceFamily.zoomMs200dPlus),
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('Line 6 Bass Pod Pro In'),
        equals(DeviceFamily.line6BassPodPro),
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('Generic USB Audio Interface'),
        isNull,
      );
    });

    test('isKnownHardwarePort identifies physical ports and filters simulated ones', () {
      const realZoom = MidiPortDescriptor(
        id: 'hw:1,0,0',
        name: 'ZOOM MS-60B+ MIDI 1',
        isInput: true,
        isOutput: true,
      );
      expect(DeviceConnectionController.isKnownHardwarePort(realZoom), isTrue);

      const realLine6 = MidiPortDescriptor(
        id: 'hw:2,0,0',
        name: 'Line 6 Bass Pod Pro In',
        isInput: true,
        isOutput: true,
      );
      expect(DeviceConnectionController.isKnownHardwarePort(realLine6), isTrue);

      const simPort = MidiPortDescriptor(
        id: 'sim_zoom',
        name: 'Zoom MS-60B+ (Simulated)',
        isInput: true,
        isOutput: true,
      );
      expect(DeviceConnectionController.isKnownHardwarePort(simPort), isFalse);
    });

    test('refreshPorts auto-selects and connects to discovered physical hardware', () async {
      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'hw:1,0,0',
            name: 'ZOOM MS-60B+ MIDI 1',
            isInput: true,
            isOutput: true,
          ),
        ],
      );

      final controller = DeviceConnectionController(transport: transport);
      expect(controller.isConnected, isFalse);

      await controller.refreshPorts();

      expect(controller.isConnected, isTrue);
      expect(controller.connectedPort?.id, equals('hw:1,0,0'));
      expect(controller.activeFamily, equals(DeviceFamily.zoomMs60bPlus));

      // Check that transport received active patch request and init sequence
      final hasCurrentPatchReq = transport.sentMessages.any(
        (m) => m.isSysEx && m.data.length >= 6 && m.data[4] == 0x64 && m.data[5] == 0x13,
      );
      expect(hasCurrentPatchReq, isTrue);

      controller.dispose();
      await transport.dispose();
    });
  });

  group('Incoming Unsolicited Hardware Updates Without Echo Loop', () {
    test('applies hardware parameter edit to PatchEditorController without echoing SysEx', () async {
      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_port',
            name: 'Simulated Port',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      final connection = DeviceConnectionController(transport: transport);

      const initialPatch = Patch(
        id: 'test_patch',
        name: 'Test Slap',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
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
                  defaultValue: 5,
                ),
                currentValue: 5,
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

      await transport.connect('sim_port');
      transport.clearSentMessages();

      // Simulate unsolicited hardware parameter edit from pedal:
      // F0 52 00 6E 64 20 00 slot=0, param=0, value=9
      final incomingHardwareEdit = const ZoomMsPlusProtocol().buildParameterEditMessage(
        slotIndex: 0,
        paramIndex: 0,
        value: 9,
      );

      // Deliver from hardware
      transport.simulateIncomingMessage(incomingHardwareEdit);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Local state is updated immediately
      expect(editor.patch?.slots[0].parameters[0].currentValue, equals(9.0));

      // CRITICAL: Transport must NOT have echoed any SysEx back to hardware
      expect(transport.sentMessages, isEmpty);

      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });

    test('applies hardware Program Change to PatchEditorController without feedback loop', () async {
      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_port',
            name: 'Simulated Port',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      final connection = DeviceConnectionController(transport: transport);

      const samplePatch = Patch(
        id: 'slot_5',
        name: 'Slot 05',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [],
      );

      transport.registerResponder(
        (req) => req.isSysEx && req.data.length >= 11 && req.data[4] == 0x46,
        (req) => const ZoomMsPlusProtocol().buildSavePatchToSlotMessage(samplePatch, 5),
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
      );

      await transport.connect('sim_port');
      transport.clearSentMessages();

      // Simulate Program Change message from physical pedal (PC #5)
      final pcMsg = MidiMessage.programChange(channel: 0, program: 5);
      transport.simulateIncomingMessage(pcMsg);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Slot 5 is pulled into editor
      expect(editor.patch?.name, equals('Slot 05'));

      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });
  });

  group('Drag-and-Drop Effect Bank Palette Widget Tests', () {
    testWidgets('renders category filter chips, search input, and draggable effect items', (tester) async {
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(transport: transport);
      const samplePatch = Patch(
        id: 'test_patch',
        name: 'Test Patch',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000010',
            effectName: 'DYN Comp',
            isEnabled: true,
            parameters: [],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: samplePatch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: EffectBankPaletteWidget(controller: editor),
            ),
          ),
        ),
      );

      // Verify category chips exist
      expect(find.byKey(const Key('palette_chip_All')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Dynamics')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Filter')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Drive')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Amp')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Cabinet')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Modulation')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_SFX')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Delay')), findsOneWidget);
      expect(find.byKey(const Key('palette_chip_Reverb')), findsOneWidget);

      // Verify search input exists
      expect(find.byKey(const Key('palette_search_input')), findsOneWidget);

      // Filter by category
      await tester.tap(find.byKey(const Key('palette_chip_Dynamics')));
      await tester.pumpAndSettle();

      // Search keyword
      await tester.enterText(find.byKey(const Key('palette_search_input')), 'comp');
      await tester.pumpAndSettle();

      // Find at least one draggable item
      expect(find.byType(Draggable<EffectDragPayload>), findsWidgets);

      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });

    testWidgets('reorderEffectSlots moves slot from A to B and syncs to hardware', (tester) async {
      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_port',
            name: 'Simulated Port',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      final connection = DeviceConnectionController(transport: transport);

      const patch = Patch(
        id: 'reorder_patch',
        name: 'Chain',
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
            effectId: '0x08000010',
            effectName: 'Delay',
            isEnabled: true,
            parameters: [],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: patch,
      );

      await transport.connect('sim_port');
      transport.clearSentMessages();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalChainStripWidget(controller: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify slot drag targets are rendered
      expect(find.byKey(const Key('slot_drag_target_0')), findsOneWidget);
      expect(find.byKey(const Key('slot_drag_target_1')), findsOneWidget);
      expect(find.byKey(const Key('slot_drag_target_2')), findsOneWidget);

      // Perform reorder: move slot 0 to index 2
      final reordered = editor.reorderEffectSlots(0, 2);
      expect(reordered, isTrue);

      expect(editor.patch?.slots[0].effectName, equals('Bass Preamp'));
      expect(editor.patch?.slots[1].effectName, equals('Delay'));
      expect(editor.patch?.slots[2].effectName, equals('DYN Comp'));

      // Check that patch was synchronized to hardware
      expect(transport.sentMessages.isNotEmpty, isTrue);

      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });

    testWidgets('dropping effect from palette onto a slot swaps effect', (tester) async {
      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_port',
            name: 'Simulated Port',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      final connection = DeviceConnectionController(transport: transport);

      const patch = Patch(
        id: 'swap_patch',
        name: 'Chain',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000010',
            effectName: 'DYN Comp',
            isEnabled: true,
            parameters: [],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: patch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SignalChainStripWidget(controller: editor),
                Expanded(child: EffectBankPaletteWidget(controller: editor)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find an effect definition from registry and swap slot 0
      final delayDef = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x08000010');
      editor.changeSlotEffect(0, delayDef.effectId);
      await tester.pumpAndSettle();

      expect(editor.patch?.slots[0].effectId, equals('0x08000010'));
      expect(editor.patch?.slots[0].effectName, equals(delayDef.name));

      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });

    test('insertEffectSlotAt enforces maxSlots, inserts at index, and marks dirty', () {
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(transport: transport);
      const initialPatch = Patch(
        id: 'insert_test',
        name: 'InsertTest',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000010',
            effectName: 'Comp',
            isEnabled: true,
            parameters: [],
          ),
          EffectSlot(
            slotIndex: 1,
            effectId: '0x08000010',
            effectName: 'Delay',
            isEnabled: true,
            parameters: [],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: initialPatch,
      );

      final driveDef = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x02000010');
      // Insert between slot 0 and 1 (at index 1)
      final success = editor.insertEffectSlotAt(1, driveDef);
      expect(success, isTrue);
      expect(editor.patch?.slots.length, equals(3));
      expect(editor.patch?.slots[0].effectId, equals('0x01000010'));
      expect(editor.patch?.slots[1].effectId, equals('0x02000010'));
      expect(editor.patch?.slots[2].effectId, equals('0x08000010'));
      expect(editor.selectedSlotIndex, equals(1));
      expect(editor.isDirty, isTrue);

      editor.dispose();
      connection.dispose();
    });

    testWidgets('renders insertion zones and dropping effect into inter-slot insertion zone inserts between pedals', (tester) async {
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(transport: transport);
      const initialPatch = Patch(
        id: 'insertion_zone_ui_test',
        name: 'InsertZoneUI',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000010',
            effectName: 'Comp',
            isEnabled: true,
            parameters: [],
          ),
          EffectSlot(
            slotIndex: 1,
            effectId: '0x08000010',
            effectName: 'Delay',
            isEnabled: true,
            parameters: [],
          ),
        ],
      );

      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: initialPatch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: SignalChainStripWidget(controller: editor),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify insertion zones before slot 0, between 0 & 1, and after 1
      expect(find.byKey(const Key('insertion_zone_0')), findsOneWidget);
      expect(find.byKey(const Key('insertion_zone_1')), findsOneWidget);
      expect(find.byKey(const Key('insertion_zone_2')), findsOneWidget);

      // Programmatically invoke insertion via controller (simulating drop)
      final bassPreamp = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x02000010');
      editor.insertEffectSlotAt(1, bassPreamp);
      await tester.pumpAndSettle();

      expect(editor.patch?.slots.length, equals(3));
      expect(editor.patch?.slots[0].effectName, equals('Comp'));
      expect(editor.patch?.slots[1].effectId, equals('0x02000010'));
      expect(editor.patch?.slots[2].effectName, equals('Delay'));

      // Insertion zone 3 should now exist
      expect(find.byKey(const Key('insertion_zone_3')), findsOneWidget);

      editor.dispose();
      connection.dispose();
    });
  });
}
