import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/line6_bass_pod_pro_protocol.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  const sampleZoomPatch = Patch(
    id: 'test_zoom_patch',
    name: 'Funk Master',
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
              id: 'p0',
              name: 'Sense',
              min: 0,
              max: 10,
              defaultValue: 5,
            ),
            currentValue: 6.0,
          ),
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'p1',
              name: 'Attack',
              min: 0,
              max: 10,
              defaultValue: 5,
            ),
            currentValue: 3.0,
          ),
        ],
      ),
      EffectSlot(
        slotIndex: 1,
        effectId: '0x02000010',
        effectName: 'Bass Preamp',
        isEnabled: false,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'p0',
              name: 'Bass',
              min: 0,
              max: 100,
              defaultValue: 50,
            ),
            currentValue: 55.0,
          ),
        ],
      ),
    ],
  );

  const sampleLine6Patch = Patch(
    id: 'test_line6_patch',
    name: 'Rock SVT',
    deviceFamily: DeviceFamily.line6BassPodPro,
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: 'line6_amp_1',
        effectName: 'Classic (SVT)',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'amp_model',
              name: 'Amp Model',
              min: 0,
              max: 15,
              defaultValue: 1,
            ),
            currentValue: 1.0,
          ),
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'drive',
              name: 'Drive',
              min: 0,
              max: 127,
              defaultValue: 64,
            ),
            currentValue: 70.0,
          ),
        ],
      ),
    ],
  );

  group('PatchEditorController Unit Tests', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;

    setUp(() async {
      transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'p1',
            name: 'Zoom MS-60B+ Port',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      connectionController = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
        initialPatch: sampleZoomPatch,
      );
      await transport.connect('p1');
    });

    tearDown(() {
      editorController.dispose();
      connectionController.dispose();
      transport.dispose();
    });

    test('pullCurrentPatch requests and decodes patch from MockMidiTransport', () async {
      const zoomProtocol = ZoomMsPlusProtocol();
      final cannedDump = zoomProtocol.encodePatch(sampleZoomPatch);

      transport.registerResponder(
        (req) => zoomProtocol.isPatchDump(req) || (req.isSysEx && req.data.length >= 7 && req.data[5] == 0x13),
        (req) => cannedDump,
      );

      await editorController.pullCurrentPatch();

      expect(editorController.patch, isNotNull);
      expect(editorController.patch!.name, equals('Funk Master'));
      expect(editorController.isDirty, isFalse);
      expect(editorController.selectedSlotIndex, equals(0));
    });

    test('toggleSlotEnabled toggles bypass flag, marks patch dirty, and transmits bypass SysEx', () {
      transport.clearSentMessages();
      expect(editorController.patch!.slots[0].isEnabled, isTrue);
      expect(editorController.isDirty, isFalse);

      editorController.toggleSlotEnabled(0);
      expect(editorController.patch!.slots[0].isEnabled, isFalse);
      expect(editorController.isDirty, isTrue);

      // Verify bypass message sent over transport: paramNumber = 0, value = 0 (Bypassed)
      expect(transport.sentMessages.length, equals(1));
      final sent1 = transport.sentMessages.first;
      expect(sent1.isSysEx, isTrue);
      expect(sent1.data[7], equals(0)); // Slot 0
      expect(sent1.data[8], equals(0)); // paramNumber 0 = Bypass
      expect(sent1.data[9], equals(0)); // 0 = Bypassed

      transport.clearSentMessages();
      editorController.toggleSlotEnabled(0);
      expect(editorController.patch!.slots[0].isEnabled, isTrue);
      expect(editorController.isDirty, isTrue);

      // Verify enable message sent: paramNumber = 0, value = 1 (Enabled)
      expect(transport.sentMessages.length, equals(1));
      final sent2 = transport.sentMessages.first;
      expect(sent2.isSysEx, isTrue);
      expect(sent2.data[7], equals(0)); // Slot 0
      expect(sent2.data[8], equals(0)); // paramNumber 0 = Bypass
      expect(sent2.data[9], equals(1)); // 1 = Enabled
    });

    test('updateParameter updates local parameter and dispatches SysEx edit message with paramIndex + 2', () async {
      transport.clearSentMessages();

      await editorController.updateParameter(0, 1, 8);

      expect(editorController.patch!.slots[0].parameters[1].currentValue, equals(8.0));
      expect(editorController.isDirty, isTrue);

      // Verify exact SysEx message sent over transport
      // On Zoom MS Plus: paramNumber = paramIndex + 2 = 1 + 2 = 3
      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isSysEx, isTrue);
      expect(sent.data[1], equals(ZoomMsPlusProtocol.manufacturerId)); // 0x52
      expect(sent.data[3], equals(ZoomMsPlusProtocol.familyIdByte)); // 0x6E
      expect(sent.data[4], equals(0x64));
      expect(sent.data[5], equals(ZoomMsPlusProtocol.cmdParameterEdit)); // 0x20
      expect(sent.data[6], equals(0x00));
      expect(sent.data[7], equals(0)); // Slot 0
      expect(sent.data[8], equals(3)); // paramNumber = 1 + 2 = 3
      expect(sent.data[9], equals(8)); // Value 8
    });

    test('updateParameter on Line 6 device dispatches exact MIDI CC message', () async {
      connectionController.selectDeviceFamily(DeviceFamily.line6BassPodPro);
      editorController.loadPatch(sampleLine6Patch);
      transport.clearSentMessages();

      // Update Drive (slot 0, param 1) to 85
      await editorController.updateParameter(0, 1, 85);

      expect(editorController.patch!.slots[0].parameters[1].currentValue, equals(85.0));
      expect(editorController.isDirty, isTrue);

      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isControlChange, isTrue);
      expect(sent.data[1], equals(Line6BassPodProProtocol.ccDrive)); // CC#13
      expect(sent.data[2], equals(85)); // Value 85
    });

    test('changeSlotEffect swaps algorithm from EffectCatalogRegistry', () {
      expect(editorController.patch!.slots[0].effectId, equals('0x01000010'));

      // Swap to M Comp ('0x01000020')
      editorController.changeSlotEffect(0, '0x01000020');

      final updatedSlot = editorController.patch!.slots[0];
      expect(updatedSlot.effectId, equals('0x01000020'));
      expect(updatedSlot.effectName, equals('BlackOpt'));
      expect(updatedSlot.parameters.isNotEmpty, isTrue);
      expect(editorController.isDirty, isTrue);
    });

    test('handles incoming hardware parameter edit without feedback loop', () async {
      transport.clearSentMessages();
      const zoomProtocol = ZoomMsPlusProtocol();

      // Simulate incoming parameter edit from pedal hardware (slot 0, param 0 = 9)
      final hardwareEditMsg = zoomProtocol.buildParameterEditMessage(
        slotIndex: 0,
        paramIndex: 0,
        value: 9,
      );

      transport.simulateIncomingMessage(hardwareEditMsg);

      // Wait a tick for stream processing
      await pumpEventQueue();

      expect(editorController.patch!.slots[0].parameters[0].currentValue, equals(9.0));

      // Assert no echo message was dispatched back to transport
      expect(transport.sentMessages.isEmpty, isTrue);
    });

    test('selectSlot transmits buildSlotFocusMessage to sync physical pedal screen', () {
      transport.clearSentMessages();
      expect(editorController.selectedSlotIndex, equals(0));

      editorController.selectSlot(1);

      expect(editorController.selectedSlotIndex, equals(1));
      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isSysEx, isTrue);
      // 64 20 00 64 01 01 00 00 00 00
      expect(sent.data[4], equals(0x64));
      expect(sent.data[5], equals(0x20));
      expect(sent.data[6], equals(0x00));
      expect(sent.data[7], equals(0x64));
      expect(sent.data[8], equals(0x01));
      expect(sent.data[9], equals(1)); // Selected slot 1
    });

    test('handles incoming hardware slot focus navigation without feedback loop', () async {
      transport.clearSentMessages();
      expect(editorController.selectedSlotIndex, equals(0));

      const zoomProtocol = ZoomMsPlusProtocol();
      // Hardware cursor Left/Right button press on pedal focused slot 1
      final focusMsg = zoomProtocol.buildSlotFocusMessage(1)!;

      transport.simulateIncomingMessage(focusMsg);
      await pumpEventQueue();

      expect(editorController.selectedSlotIndex, equals(1));
      // No echo message sent back to pedal
      expect(transport.sentMessages.isEmpty, isTrue);
    });

    test('handles incoming hardware footswitch bypass and updates selectedSlotIndex without echo', () async {
      transport.clearSentMessages();
      expect(editorController.patch!.slots[1].isEnabled, isFalse);
      expect(editorController.selectedSlotIndex, equals(0));

      const zoomProtocol = ZoomMsPlusProtocol();
      // Physical footswitch enabled slot 1
      final bypassMsg = zoomProtocol.buildSlotBypassMessage(slotIndex: 1, isEnabled: true);

      transport.simulateIncomingMessage(bypassMsg);
      await pumpEventQueue();

      expect(editorController.patch!.slots[1].isEnabled, isTrue);
      expect(editorController.selectedSlotIndex, equals(1)); // Follows active slot
      // No echo message sent back to pedal
      expect(transport.sentMessages.isEmpty, isTrue);
    });

    test('pushPatchToDevice sends encoded patch dump over transport', () async {
      transport.clearSentMessages();

      await editorController.pushPatchToDevice();

      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isSysEx, isTrue);
      expect(const ZoomMsPlusProtocol().isPatchDump(sent), isTrue);
      expect(editorController.isDirty, isFalse);
    });

    test('savePatchToDeviceSlot transmits encoded slot dump SysEx and updates local bank', () async {
      transport.clearSentMessages();

      await editorController.savePatchToDeviceSlot(42);

      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isSysEx, isTrue);
      expect(const ZoomMsPlusProtocol().isSlotPatchDump(sent), isTrue);
      expect(const ZoomMsPlusProtocol().extractSlotIndex(sent), equals(42));
      expect(editorController.patch?.programNumber, equals(42));
      expect(editorController.isDirty, isFalse);
      expect(connectionController.bankSlots[42].name, equals('Funk Master'));
    });

    test('savePatchToDeviceSlot fails gracefully when transport is disconnected', () async {
      await transport.disconnect();
      transport.clearSentMessages();

      await editorController.savePatchToDeviceSlot(10);

      expect(transport.sentMessages.isEmpty, isTrue);
      expect(editorController.errorMessage, contains('Cannot save to hardware'));
    });

    test('setHardwareSlotIndex updates patch programNumber and synchronizes without marking dirty', () {
      expect(editorController.patch?.programNumber, isNull);
      expect(editorController.isDirty, isFalse);

      editorController.setHardwareSlotIndex(15);

      expect(editorController.patch?.programNumber, equals(15));
      expect(editorController.isDirty, isFalse);
    });

    test('applyExternalHardwareUpdate with programNumber assigns slot to unassigned initial patch without reload when offline', () async {
      await transport.disconnect();
      transport.clearSentMessages();
      expect(editorController.patch?.programNumber, isNull);

      editorController.applyExternalHardwareUpdate(programNumber: 7);

      expect(editorController.patch?.programNumber, equals(7));
      expect(connectionController.activeHardwareSlotIndex, equals(7));
      expect(editorController.isDirty, isFalse);
      // No outbound requests triggered when disconnected
      expect(transport.sentMessages.isEmpty, isTrue);
    });

    test('applyExternalHardwareUpdate with patch preserves known activeHardwareSlotIndex', () {
      connectionController.setActiveHardwareSlotIndex(5);
      editorController.setHardwareSlotIndex(5);

      // Incoming patch dump with null programNumber (e.g. from 64 12 01)
      final incomingDumpPatch = sampleZoomPatch.copyWith(name: 'Updated Edit Buffer', programNumber: null);
      editorController.applyExternalHardwareUpdate(patch: incomingDumpPatch);

      expect(editorController.patch?.name, equals('Updated Edit Buffer'));
      expect(editorController.patch?.programNumber, equals(5));
      expect(connectionController.activeHardwareSlotIndex, equals(5));
    });

    test('undo and redo restore state, dirty flag, and dispatch Zoom 64 20 00 deltas (never 64 12 01)', () async {
      // Transport is already connected to 'p1' (Zoom MS-60B+ Port) in setUp().
      transport.clearSentMessages();

      // Gesture-coalesced parameter sweep
      editorController.beginEditGesture(label: 'Adjust Sense');
      await editorController.updateParameter(0, 0, 7);
      await editorController.updateParameter(0, 0, 9);
      editorController.endEditGesture();

      expect(editorController.patch!.slots[0].parameters[0].currentValue, equals(9.0));
      expect(editorController.canUndo, isTrue);
      expect(editorController.isDirty, isTrue);

      // Add a 3rd slot (sampleZoomPatch starts with 2 slots)
      editorController.addEffectSlot(effectId: '0x02000010');
      expect(editorController.patch!.slots.length, equals(3));

      transport.clearSentMessages();
      // Undo adding slot -> must clear slot 2 via 64 20 00 (effectId=0), never 64 12 01
      expect(editorController.undo(), isTrue);
      expect(editorController.patch!.slots.length, equals(2));
      expect(
        transport.sentMessages.any(
          (m) => m.data.length >= 9 && m.data[4] == 0x64 && m.data[5] == 0x20 && m.data[7] == 2 && m.data[8] == 1,
        ),
        isTrue,
      );
      expect(
        transport.sentMessages.any(
          (m) => m.data.length >= 7 && m.data[4] == 0x64 && m.data[5] == 0x12 && m.data[6] == 0x01,
        ),
        isFalse,
      );

      // Undo parameter sweep -> restores original value (6.0) and clean dirty flag!
      transport.clearSentMessages();
      expect(editorController.undo(), isTrue);
      expect(editorController.patch!.slots[0].parameters[0].currentValue, equals(6.0));
      expect(editorController.isDirty, isFalse);
      expect(editorController.canRedo, isTrue);

      // Redo parameter sweep -> restores 9.0 and sends 64 20 00 param edit
      transport.clearSentMessages();
      expect(editorController.redo(), isTrue);
      expect(editorController.patch!.slots[0].parameters[0].currentValue, equals(9.0));
      expect(editorController.isDirty, isTrue);
      expect(
        transport.sentMessages.any(
          (m) => m.data.length >= 9 && m.data[4] == 0x64 && m.data[5] == 0x20 && m.data[7] == 0 && m.data[8] == 2,
        ),
        isTrue,
      );
    });

    test('A/B compare toggles between baseline A and edited B with hardware sync', () async {
      // Edit parameter -> automatically forks into B while A keeps baseline (6.0)
      await editorController.updateParameter(0, 0, 10);
      expect(editorController.comparePatchA?.slots[0].parameters[0].currentValue, equals(6.0));
      expect(editorController.comparePatchB?.slots[0].parameters[0].currentValue, equals(10.0));
      expect(editorController.hasABDifference, isTrue);

      transport.clearSentMessages();
      editorController.toggleCompareSlot();
      expect(editorController.patch?.slots[0].parameters[0].currentValue, equals(6.0));
      expect(
        transport.sentMessages.any(
          (m) => m.data.length >= 9 && m.data[4] == 0x64 && m.data[5] == 0x20 && m.data[7] == 0 && m.data[8] == 2,
        ),
        isTrue,
      );

      editorController.toggleCompareSlot();
      expect(editorController.patch?.slots[0].parameters[0].currentValue, equals(10.0));
    });

    test('applyExternalHardwareUpdate does not push onto app Undo stack', () async {
      expect(editorController.canUndo, isFalse);

      editorController.applyExternalHardwareUpdate(
        slotIndex: 0,
        paramIndex: 0,
        value: 8,
      );

      expect(editorController.patch!.slots[0].parameters[0].currentValue, equals(8.0));
      expect(editorController.canUndo, isFalse);
    });

    test('physical pedal 64 26 00 00 switches active patch from cached bank with zero MIDI echo even when dirty', () async {
      // Simulate loading slot 3 via Bank Manager and making a dirty edit
      final slot3Patch = sampleZoomPatch.copyWith(name: 'Bank Loaded 3', programNumber: 3);
      editorController.loadPatch(slot3Patch);
      await editorController.updateParameter(0, 0, 9);
      expect(editorController.isDirty, isTrue);

      final slot14Patch = sampleZoomPatch.copyWith(name: 'Chorus Clean', programNumber: 14);
      connectionController.updateBankSlot(
        14,
        patchName: 'Chorus Clean',
        patch: slot14Patch,
      );

      transport.clearSentMessages();
      // Zoom 64 26 00 00: bank=1, prog=4 -> slot 14
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x64, 0x26, 0x00, 0x00, 0x01, 0x00, 0x04, 0x00]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(connectionController.activeHardwareSlotIndex, equals(14));
      expect(editorController.patch?.name, equals('Chorus Clean'));
      expect(editorController.patch?.programNumber, equals(14));
      expect(editorController.isDirty, isFalse);
      expect(transport.sentMessages, isEmpty);
    });

    test('physical pedal 64 26 00 00 fetches uncached slot from hardware without echoing slot select messages', () async {
      const zoomProtocol = ZoomMsPlusProtocol();
      final uncachedPatch = sampleZoomPatch.copyWith(name: 'Uncached Slap', programNumber: 14);

      transport.registerResponder(
        (req) => req.isSysEx && req.data.length >= 6 && req.data[4] == 0x46,
        (req) => zoomProtocol.buildSavePatchToSlotMessage(uncachedPatch, 14),
      );

      transport.clearSentMessages();
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x64, 0x26, 0x00, 0x00, 0x01, 0x00, 0x04, 0x00]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(connectionController.activeHardwareSlotIndex, equals(14));
      expect(editorController.patch?.name, equals('Uncached Slap'));
      expect(editorController.patch?.programNumber, equals(14));
      // Only outgoing SysEx slot read request (0x46) should be sent; zero CC/PC echo
      expect(transport.sentMessages.any((m) => m.isProgramChange || m.isControlChange), isFalse);
      expect(transport.sentMessages.where((m) => m.data.length >= 5 && m.data[4] == 0x46).length, equals(1));
    });

    test('physical pedal Bank Select CC 32 + Program Change switches active patch in editor', () async {
      final slot23Patch = sampleZoomPatch.copyWith(name: 'Bank2 Slot3', programNumber: 23);
      connectionController.updateBankSlot(
        23,
        patchName: 'Bank2 Slot3',
        patch: slot23Patch,
      );

      transport.clearSentMessages();
      transport.simulateIncomingMessage(
        MidiMessage.controlChange(channel: 0, controller: 32, value: 2),
      );
      transport.simulateIncomingMessage(
        MidiMessage.programChange(channel: 0, program: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(connectionController.activeHardwareSlotIndex, equals(23));
      expect(editorController.patch?.name, equals('Bank2 Slot3'));
      expect(editorController.patch?.programNumber, equals(23));
      expect(transport.sentMessages, isEmpty);
    });

    test('savePatchToDeviceSlot hard-blocks cross-generation patch writes with zero MIDI output', () async {
      connectionController.updateBankSlot(
        2,
        patchName: 'Old Slot 2',
        patch: sampleZoomPatch.copyWith(programNumber: 2),
      );
      transport.clearSentMessages();

      await editorController.savePatchToDeviceSlot(2, sampleLine6Patch);

      expect(editorController.errorMessage, contains('incompatible hardware generation'));
      expect(transport.sentMessages, isEmpty);
      expect(connectionController.bankSlots[2].name, equals('Old Slot 2'));
      expect(connectionController.bankSlots[2].patch?.name, equals('Funk Master'));
    });
  });
}
