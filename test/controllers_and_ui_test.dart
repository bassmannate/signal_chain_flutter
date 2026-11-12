import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/effect_picker_dialog.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  const samplePatch = Patch(
    id: 'test_patch_m6',
    name: 'Milestone 6 Patch',
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
              id: 'sense_0',
              name: 'Sense',
              min: 0,
              max: 10,
              defaultValue: 6,
            ),
            currentValue: 6.0,
          ),
        ],
      ),
      EffectSlot(
        slotIndex: 1,
        effectId: '0x05000020',
        effectName: 'AMPG SVT',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'gain_0',
              name: 'Gain',
              min: 0,
              max: 100,
              defaultValue: 30,
            ),
            currentValue: 30.0,
          ),
        ],
      ),
      EffectSlot(
        slotIndex: 2,
        effectId: '0x0A000010',
        effectName: 'Delay',
        isEnabled: false,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'time_0',
              name: 'Time',
              min: 0,
              max: 100,
              defaultValue: 50,
            ),
            currentValue: 50.0,
          ),
        ],
      ),
    ],
  );

  group('PatchEditorController - Slot Reordering and Structure Edits', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;

    setUp(() {
      transport = MockMidiTransport();
      connectionController = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
        initialPatch: samplePatch,
      );
    });

    tearDown(() {
      editorController.dispose();
      connectionController.dispose();
      transport.dispose();
    });

    test('reorders slots with moveEffectSlot', () {
      expect(editorController.patch!.slots[0].effectName, equals('DYN Comp'));
      expect(editorController.patch!.slots[1].effectName, equals('AMPG SVT'));

      // Move slot 0 to index 1
      final moved = editorController.moveEffectSlot(0, 1);
      expect(moved, isTrue);
      expect(editorController.isDirty, isTrue);

      final slots = editorController.patch!.slots;
      expect(slots[0].effectName, equals('AMPG SVT'));
      expect(slots[0].slotIndex, equals(0));
      expect(slots[1].effectName, equals('DYN Comp'));
      expect(slots[1].slotIndex, equals(1));
      expect(slots[2].effectName, equals('Delay'));
      expect(slots[2].slotIndex, equals(2));
    });

    test('adds an effect slot respecting device max slot limits', () {
      expect(editorController.patch!.slots.length, equals(3));

      // Add a 4th slot with int effect ID for Dark Pre (0x04000030)
      final added1 = editorController.addEffectSlot(effectId: 0x04000030);
      expect(added1, isTrue);
      expect(editorController.patch!.slots.length, equals(4));
      expect(editorController.patch!.slots[3].effectId, equals('0x04000030'));
      expect(editorController.patch!.slots[3].effectName, equals('Dark Pre'));
      expect(editorController.patch!.slots[3].parameters.isNotEmpty, isTrue);
      expect(editorController.isDirty, isTrue);

      // Add 5th slot
      final added2 = editorController.addEffectSlot(effectId: '0x06000010');
      expect(added2, isTrue);
      expect(editorController.patch!.slots.length, equals(5));

      // Add 6th slot (Zoom max limit)
      final added3 = editorController.addEffectSlot(effectId: '0x0B000010');
      expect(added3, isTrue);
      expect(editorController.patch!.slots.length, equals(6));
      expect(editorController.canAddEffectSlot, isFalse);

      // Attempt 7th slot -> rejected by device max slot limit
      final added4 = editorController.addEffectSlot(effectId: '0x07000010');
      expect(added4, isFalse);
      expect(editorController.patch!.slots.length, equals(6));
    });

    test('removes an effect slot safely and adjusts selectedSlotIndex', () {
      editorController.selectSlot(2);
      expect(editorController.selectedSlotIndex, equals(2));

      // Remove slot 1 (AMPG SVT)
      final removed = editorController.removeEffectSlot(1);
      expect(removed, isTrue);
      expect(editorController.isDirty, isTrue);

      final slots = editorController.patch!.slots;
      expect(slots.length, equals(2));
      expect(slots[0].effectName, equals('DYN Comp'));
      expect(slots[1].effectName, equals('Delay'));
      expect(slots[1].slotIndex, equals(1));

      // selectedSlotIndex should adjust cleanly from 2 to 1
      expect(editorController.selectedSlotIndex, equals(1));
    });

    test('swaps effect using changeSlotEffect with int ID', () {
      expect(editorController.patch!.slots[0].effectName, equals('DYN Comp'));

      // Swap slot 0 to Ba AnaOct (0x07000020)
      editorController.changeSlotEffect(0, 0x07000020);

      final updatedSlot = editorController.patch!.slots[0];
      expect(updatedSlot.effectId, equals('0x07000020'));
      expect(updatedSlot.effectName, equals('Ba AnaOct'));
      expect(updatedSlot.parameters.isNotEmpty, isTrue);
      expect(editorController.isDirty, isTrue);
    });
  });

  group('UI & EffectPickerDialog Widget Tests', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;

    setUp(() {
      transport = MockMidiTransport();
      connectionController = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
        initialPatch: samplePatch,
      );
    });

    tearDown(() {
      editorController.dispose();
      connectionController.dispose();
      transport.dispose();
    });

    testWidgets('renders reorder, swap, and delete controls on signal chain strip', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalChainStripWidget(controller: editorController),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify slot cards
      expect(find.byKey(const Key('effect_slot_0')), findsOneWidget);
      expect(find.byKey(const Key('effect_slot_1')), findsOneWidget);
      expect(find.byKey(const Key('effect_slot_2')), findsOneWidget);

      // Verify reorder controls
      expect(find.byKey(const Key('move_slot_left_0')), findsOneWidget);
      expect(find.byKey(const Key('move_slot_right_0')), findsOneWidget);
      expect(find.byKey(const Key('change_effect_slot_0')), findsOneWidget);
      expect(find.byKey(const Key('delete_slot_0')), findsOneWidget);
      expect(find.byKey(const Key('add_effect_slot_button')), findsOneWidget);

      // Tap move left on slot 0 (moves towards output/slot 1 in RTL)
      await tester.tap(find.byKey(const Key('move_slot_left_0')));
      await tester.pumpAndSettle();

      // Now slot 0 is AMPG SVT and slot 1 is DYN Comp
      expect(editorController.patch!.slots[0].effectName, equals('AMPG SVT'));
      expect(editorController.patch!.slots[1].effectName, equals('DYN Comp'));
    });

    testWidgets('opens EffectPickerDialog, searches, filters, and selects new effect', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalChainStripWidget(controller: editorController),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap + Add Effect card
      final addEffectButton = find.byKey(const Key('add_effect_slot_button'));
      expect(addEffectButton, findsOneWidget);
      await tester.tap(addEffectButton);
      await tester.pumpAndSettle();

      // Verify EffectPickerDialog is displayed
      expect(find.byType(EffectPickerDialog), findsOneWidget);
      expect(find.byKey(const Key('effect_picker_search_input')), findsOneWidget);

      // Search for 'ZNR'
      await tester.enterText(find.byKey(const Key('effect_picker_search_input')), 'ZNR');
      await tester.pumpAndSettle();

      // Should display ZNR item
      final znrItem = find.byKey(const Key('effect_picker_item_0x01000090'));
      expect(znrItem, findsOneWidget);

      // Tap select button on ZNR
      await tester.tap(find.byKey(const Key('select_effect_btn_0x01000090')));
      await tester.pumpAndSettle();

      // Dialog should close and patch now has 4 slots with ZNR added
      expect(find.byType(EffectPickerDialog), findsNothing);
      expect(editorController.patch!.slots.length, equals(4));
      expect(editorController.patch!.slots.last.effectName, equals('ZNR'));
    });
  });
}
