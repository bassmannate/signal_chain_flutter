import 'package:flutter_test/flutter_test.dart';
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

    test('toggleSlotEnabled toggles bypass flag and marks patch dirty', () {
      expect(editorController.patch!.slots[0].isEnabled, isTrue);
      expect(editorController.isDirty, isFalse);

      editorController.toggleSlotEnabled(0);
      expect(editorController.patch!.slots[0].isEnabled, isFalse);
      expect(editorController.isDirty, isTrue);

      editorController.toggleSlotEnabled(0);
      expect(editorController.patch!.slots[0].isEnabled, isTrue);
      expect(editorController.isDirty, isTrue);
    });

    test('updateParameter updates local parameter and dispatches SysEx edit message', () async {
      transport.clearSentMessages();

      await editorController.updateParameter(0, 1, 8);

      expect(editorController.patch!.slots[0].parameters[1].currentValue, equals(8.0));
      expect(editorController.isDirty, isTrue);

      // Verify exact SysEx message sent over transport
      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isSysEx, isTrue);
      expect(sent.data[1], equals(ZoomMsPlusProtocol.manufacturerId)); // 0x52
      expect(sent.data[3], equals(ZoomMsPlusProtocol.familyIdByte)); // 0x6E
      expect(sent.data[4], equals(0x64));
      expect(sent.data[5], equals(ZoomMsPlusProtocol.cmdParameterEdit)); // 0x20
      expect(sent.data[6], equals(0x00));
      expect(sent.data[7], equals(0)); // Slot 0
      expect(sent.data[8], equals(1)); // Param 1
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
      expect(sent.data[1], equals(Line6BassPodProProtocol.ccDrive)); // CC#4
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

    test('pushPatchToDevice sends encoded patch dump over transport', () async {
      transport.clearSentMessages();

      await editorController.pushPatchToDevice();

      expect(transport.sentMessages.length, equals(1));
      final sent = transport.sentMessages.first;
      expect(sent.isSysEx, isTrue);
      expect(const ZoomMsPlusProtocol().isPatchDump(sent), isTrue);
      expect(editorController.isDirty, isFalse);
    });
  });
}
