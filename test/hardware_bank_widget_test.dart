import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_metadata_header_widget.dart';
import 'package:signal_chain_flutter/features/editor/write_to_slot_dialog.dart';
import 'package:signal_chain_flutter/features/library/hardware_bank_browser_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('PatchMetadataHeaderWidget Tests', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;

    const testPatch = Patch(
      id: 'test_1',
      name: 'SlapFunk',
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
      metadata: {'tempo': 120},
    );

    setUp(() {
      transport = MockMidiTransport();
      connectionController = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
        initialPatch: testPatch,
      );
    });

    testWidgets('renders patch name TextField and updates name in real-time', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: PatchMetadataHeaderWidget(controller: editorController),
          ),
        ),
      );

      final textFieldFinder = find.byKey(const Key('patch_name_textfield'));
      expect(textFieldFinder, findsOneWidget);
      expect(find.text('SlapFunk'), findsOneWidget);

      // Edit name
      await tester.enterText(textFieldFinder, 'Punchy');
      await tester.pump();

      expect(editorController.patch?.name, equals('Punchy'));
      expect(editorController.isDirty, isTrue);
      expect(find.byKey(const Key('patch_dirty_indicator')), findsOneWidget);
    });

    testWidgets('renders tempo display, increment/decrement buttons, and slider', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: PatchMetadataHeaderWidget(controller: editorController),
          ),
        ),
      );

      expect(find.text('120 BPM'), findsOneWidget);

      // Increment tempo
      await tester.tap(find.byKey(const Key('tempo_increment_button')));
      await tester.pump();
      expect(editorController.patch?.tempo, equals(121));
      expect(find.text('121 BPM'), findsOneWidget);

      // Decrement tempo
      await tester.tap(find.byKey(const Key('tempo_decrement_button')));
      await tester.pump();
      expect(editorController.patch?.tempo, equals(120));
      expect(find.text('120 BPM'), findsOneWidget);

      // Slide tempo
      await tester.drag(find.byKey(const Key('patch_tempo_slider')), const Offset(50, 0));
      await tester.pump();
      expect(editorController.patch?.tempo, greaterThan(120));
    });

    testWidgets('Write to Slot button opens WriteToSlotDialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: PatchMetadataHeaderWidget(controller: editorController),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('write_to_hardware_slot_button')));
      await tester.pumpAndSettle();

      expect(find.byType(WriteToSlotDialog), findsOneWidget);
      expect(find.text('Write to Hardware Slot'), findsOneWidget);
      expect(find.byKey(const Key('write_slot_dropdown')), findsOneWidget);

      // Close dialog
      await tester.tap(find.byKey(const Key('cancel_write_slot_button')));
      await tester.pumpAndSettle();
      expect(find.byType(WriteToSlotDialog), findsNothing);
    });
  });

  group('HardwareBankBrowserWidget Tests', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;

    const testPatch = Patch(
      id: 'test_patch',
      name: 'ModernFunk',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      slots: [],
      metadata: {'tempo': 120},
    );

    setUp(() async {
      transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'port_1',
            name: 'Zoom MS-60B+',
            manufacturer: 'Zoom',
            isInput: true,
            isOutput: true,
          ),
        ],
      );

      // Register auto-responder for memory slot requests
      transport.registerResponder(
        (req) =>
            req.isSysEx &&
            req.data.length >= 11 &&
            req.data[1] == 0x52 &&
            req.data[4] == 0x46,
        (req) {
          final bank = req.data[7] | (req.data[8] << 7);
          final prog = req.data[9] | (req.data[10] << 7);
          final slot = (bank * 10) + prog;
          return const ZoomMsPlusProtocol().buildSavePatchToSlotMessage(
            testPatch.copyWith(name: 'Preset $slot', programNumber: slot),
            slot,
          );
        },
      );

      connectionController = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      await connectionController.connect(transport.mockPorts.first);

      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
        initialPatch: testPatch,
      );
    });

    testWidgets('renders slots list, search filter, and sync button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 700,
              child: HardwareBankBrowserWidget(
                connectionController: connectionController,
                editorController: editorController,
              ),
            ),
          ),
        ),
      );

      expect(find.text('HARDWARE BANK'), findsOneWidget);
      expect(find.text('100 SLOTS'), findsOneWidget);
      expect(find.byKey(const Key('sync_device_bank_button')), findsOneWidget);
      expect(find.byKey(const Key('hardware_bank_slots_list')), findsOneWidget);

      // Filter slots
      final searchInput = find.byKey(const Key('hardware_bank_search_input'));
      await tester.enterText(searchInput, '42');
      await tester.pump();

      expect(find.byKey(const Key('bank_slot_42')), findsOneWidget);
      expect(find.byKey(const Key('bank_slot_0')), findsNothing);
    });

    testWidgets('Sync Device Bank fetches slots and populates names without cycling the editor buffer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 700,
              child: HardwareBankBrowserWidget(
                connectionController: connectionController,
                editorController: editorController,
              ),
            ),
          ),
        ),
      );

      expect(editorController.patch?.name, equals('ModernFunk'));

      // Trigger sync for first 3 slots
      await connectionController.syncDeviceBank(slotCount: 3);
      await tester.pumpAndSettle();

      expect(connectionController.bankSlots[0].name, equals('Preset 0'));
      expect(connectionController.bankSlots[1].name, equals('Preset 1'));
      expect(connectionController.bankSlots[2].name, equals('Preset 2'));

      // Editor buffer MUST NOT be altered or cycled by background bank sync!
      expect(editorController.patch?.name, equals('ModernFunk'));
    });

    testWidgets('Single-click on a slot card loads it into editor controller without overwriting slot', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 700,
              child: HardwareBankBrowserWidget(
                connectionController: connectionController,
                editorController: editorController,
              ),
            ),
          ),
        ),
      );

      // Pre-populate slot 1 in bank slots
      connectionController.updateBankSlot(
        1,
        patchName: 'Preset 1',
        patch: testPatch.copyWith(name: 'Preset 1', programNumber: 1),
      );
      await tester.pump();

      // Single click on slot 1 card
      final slot1Card = find.byKey(const Key('bank_slot_1'));
      expect(slot1Card, findsOneWidget);
      await tester.tap(slot1Card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Loaded into editor on single click!
      expect(editorController.patch?.programNumber, equals(1));
      expect(editorController.patch?.name, equals('Preset 1'));

      // Verify slot was not overwritten with old patch
      expect(connectionController.bankSlots[1].name, equals('Preset 1'));
    });

    test('Hot-plug check discovers newly plugged hardware and cleanly handles unplugging', () async {
      final hotPlugTransport = MockMidiTransport();
      final hotPlugConnection = DeviceConnectionController(
        transport: hotPlugTransport,
        enableHotPlugPolling: false,
      );

      expect(hotPlugConnection.isConnected, isFalse);

      // 1. Pedal is plugged in
      hotPlugTransport.addPort(const MidiPortDescriptor(
        id: 'hw:3,0,0',
        name: 'ZOOM MS-60B+ MIDI 1',
        isInput: true,
        isOutput: true,
      ));

      // Check hot plug auto-connects
      await hotPlugConnection.checkHotPlug();
      expect(hotPlugConnection.isConnected, isTrue);
      expect(hotPlugConnection.connectedPort?.id, equals('hw:3,0,0'));

      // 2. Pedal is unplugged
      hotPlugTransport.removePort('hw:3,0,0');
      await hotPlugConnection.checkHotPlug();

      // Verify cleanly disconnected
      expect(hotPlugConnection.isConnected, isFalse);
      expect(hotPlugConnection.connectedPort, isNull);

      hotPlugConnection.dispose();
      await hotPlugTransport.dispose();
    });

    testWidgets('Tapping load button on a slot loads it into editor controller', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 700,
              child: HardwareBankBrowserWidget(
                connectionController: connectionController,
                editorController: editorController,
              ),
            ),
          ),
        ),
      );

      // Click load on slot 0
      final loadSlot0Button = find.byKey(const Key('load_slot_0_button'));
      expect(loadSlot0Button, findsOneWidget);
      await tester.tap(loadSlot0Button);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(editorController.patch?.programNumber, equals(0));
      expect(editorController.patch?.name, equals('Preset 0'));
    });
  });

  group('PatchLibraryDrawerOrPanel Tab Toggle', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;
    late PatchLibraryController libraryController;

    setUp(() {
      transport = MockMidiTransport();
      connectionController = DeviceConnectionController(transport: transport);
      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
      );
      libraryController = PatchLibraryController(
        repository: InMemoryPatchLibraryRepository(),
      );
    });

    testWidgets('switches between Local Presets and Hardware Bank tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 700,
              child: PatchLibraryDrawerOrPanel(
                libraryController: libraryController,
                editorController: editorController,
              ),
            ),
          ),
        ),
      );

      // Starts on Local Presets tab
      expect(find.text('PRESET LIBRARY'), findsOneWidget);
      expect(find.byType(HardwareBankBrowserWidget), findsNothing);

      // Switch to Hardware Bank tab
      await tester.tap(find.byKey(const Key('library_tab_hardware')));
      await tester.pumpAndSettle();

      expect(find.text('HARDWARE BANK'), findsOneWidget);
      expect(find.byType(HardwareBankBrowserWidget), findsOneWidget);

      // Switch back to Local Presets tab
      await tester.tap(find.byKey(const Key('library_tab_local')));
      await tester.pumpAndSettle();

      expect(find.text('PRESET LIBRARY'), findsOneWidget);
      expect(find.byType(HardwareBankBrowserWidget), findsNothing);
    });
  });
}
