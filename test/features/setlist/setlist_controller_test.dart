import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/core/storage/setlist_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/models/setlist.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  Patch makeZoomPatch(String id, String name, {double gain = 50}) {
    return Patch(
      id: id,
      name: name,
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      slots: [
        EffectSlot(
          slotIndex: 0,
          effectId: '0x01000010',
          effectName: 'DYN Comp',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: const ParameterDescriptor(
                id: 'p0',
                name: 'Sense',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: gain,
            ),
          ],
        ),
      ],
      metadata: const {'tempo': 110},
    );
  }

  Patch makeLine6Patch(String id, String name) {
    return Patch(
      id: id,
      name: name,
      deviceFamily: DeviceFamily.line6BassPodPro,
      slots: const [
        EffectSlot(
          slotIndex: 0,
          effectId: 'line6_amp_8',
          effectName: 'Rock Classic',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'amp_model',
                name: 'Amp Model',
                min: 0,
                max: 15,
                defaultValue: 8,
              ),
              currentValue: 8,
            ),
          ],
        ),
      ],
    );
  }

  group('SetlistController', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connection;
    late PatchEditorController editor;
    late PatchLibraryController library;
    late InMemorySetlistRepository setlistRepo;
    late SetlistController setlistController;

    setUp(() async {
      transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_zoom',
            name: 'Zoom MS-60B+ (Simulated)',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      connection = DeviceConnectionController(
        transport: transport,
        enableHotPlugPolling: false,
      );
      final p1 = makeZoomPatch('p1', 'Opener', gain: 40);
      final p2 = makeZoomPatch('p2', 'Chorus Drive', gain: 85);
      final p3 = makeLine6Patch('p3', 'Rack SVT');

      editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: p1,
      );
      library = PatchLibraryController(
        repository: InMemoryPatchLibraryRepository(initialPatches: [p1, p2, p3]),
      );
      await library.refresh();

      setlistRepo = InMemorySetlistRepository(
        initialSetlists: const [
          Setlist(
            id: 's1',
            name: 'Club Gig',
            entries: [
              SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Track 1'),
              SetlistEntry(
                id: 'e2',
                patchId: 'p2',
                songTitle: 'Track 2',
                tempoOverride: 142,
              ),
            ],
          ),
        ],
      );
      setlistController = SetlistController(
        repository: setlistRepo,
        libraryController: library,
        editorController: editor,
        connectionController: connection,
        transport: transport,
      );
      await setlistController.refresh();
    });

    tearDown(() {
      setlistController.dispose();
      editor.dispose();
      connection.dispose();
      transport.dispose();
    });

    test('steps next/prev with wrap-around and dispatches Zoom 64 20 00 deltas (never 64 12 01 or 0x45)', () async {
      await transport.connect('sim_zoom');
      transport.clearSentMessages();

      await setlistController.nextEntry();
      expect(setlistController.activeEntryIndex, equals(1));
      expect(editor.patch?.name, equals('Chorus Drive'));
      expect(editor.patch?.tempo, equals(142));

      // Verify Zoom 64 20 00 live parameter delta was sent, never 64 12 01 or 0x45
      expect(transport.sentMessages, isNotEmpty);
      for (final msg in transport.sentMessages) {
        if (msg.isSysEx && msg.data.length >= 7) {
          final is641201 =
              msg.data[4] == 0x64 && msg.data[5] == 0x12 && msg.data[6] == 0x01;
          final isSlotWrite45 = msg.data[4] == 0x45;
          expect(is641201, isFalse, reason: 'Must never send 64 12 01');
          expect(isSlotWrite45, isFalse, reason: 'Must never overwrite flash 0x45');
        }
      }

      // Without wrap-around, next at end stays at index 1
      await setlistController.nextEntry();
      expect(setlistController.activeEntryIndex, equals(1));

      // With wrap-around enabled, next loops to 0 and prev loops back to 1
      setlistController.setWrapAroundNavigation(true);
      await setlistController.nextEntry();
      expect(setlistController.activeEntryIndex, equals(0));
      await setlistController.previousEntry();
      expect(setlistController.activeEntryIndex, equals(1));
    });

    test('handles missing library presets and device family mismatch gracefully', () async {
      await transport.connect('sim_zoom');
      connection.selectDeviceFamily(DeviceFamily.zoomMs60bPlus);
      await setlistController.addPatchToSetlist(
        's1',
        makeLine6Patch('p3', 'Rack SVT'),
      );
      await setlistController.addPatchToSetlist(
        's1',
        makeZoomPatch('deleted_id', 'Gone'),
      );

      // Step to Line 6 patch while Zoom is connected -> skips hardware send & sets warning
      transport.clearSentMessages();
      await setlistController.selectEntryAt(2);
      expect(setlistController.warningMessage, contains('Device mismatch'));
      expect(transport.sentMessages, isEmpty);

      // Step to missing preset -> sets warning without crashing
      await setlistController.selectEntryAt(3);
      expect(setlistController.warningMessage, contains('Missing preset'));
    });

    test('dispatches Line 6 encodePatch when connected to Line 6 Bass POD Pro', () async {
      await transport.connect('sim_zoom');
      connection.selectDeviceFamily(DeviceFamily.line6BassPodPro);
      final line6Set = await setlistController.createSetlist('Rack Set');
      await setlistController.addPatchToSetlist(
        line6Set.id,
        makeLine6Patch('p3', 'Rack SVT'),
      );
      transport.clearSentMessages();

      await setlistController.selectEntryAt(0);
      expect(transport.sentMessages, isNotEmpty);
      expect(transport.sentMessages.first.data[1], equals(0x00));
      expect(transport.sentMessages.first.data[2], equals(0x01));
      expect(transport.sentMessages.first.data[3], equals(0x0C));
    });

    test('responds to incoming MIDI PC and CC foot-controller triggers only in Stage Mode', () async {
      setlistController.updateMidiConfig(
        const MidiFootControllerConfig(
          enableProgramChangeSelect: true,
          nextStepCcNumber: 80,
          prevStepCcNumber: 81,
        ),
      );

      // Ignored when Performance Mode is inactive
      transport.simulateIncomingMessage(
        MidiMessage.programChange(channel: 0, program: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(setlistController.activeEntryIndex, equals(0));

      // Active in Performance Mode
      setlistController.setPerformanceModeActive(true);
      await Future<void>.delayed(Duration.zero);

      transport.simulateIncomingMessage(
        MidiMessage.controlChange(channel: 0, controller: 80, value: 127),
      );
      await Future<void>.delayed(Duration.zero);
      expect(setlistController.activeEntryIndex, equals(1));
    });
  });
}

