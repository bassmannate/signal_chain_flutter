import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  const protocol = ZoomMsPlusProtocol();

  group('ZoomMsPlusProtocol Identity Matching', () {
    test('matches and identifies Zoom MS-60B+', () {
      final reply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x27, 0x00, 0x31, 0x2E, 0x30, 0x30,
      ]);
      expect(protocol.matchesIdentityResponse(reply), isTrue);
      expect(protocol.parseDeviceFamily(reply), equals(DeviceFamily.zoomMs60bPlus));
    });

    test('matches and identifies Zoom MS-50G+', () {
      final reply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x23, 0x00, 0x31, 0x2E, 0x30, 0x30,
      ]);
      expect(protocol.matchesIdentityResponse(reply), isTrue);
      expect(protocol.parseDeviceFamily(reply), equals(DeviceFamily.zoomMs50gPlus));
    });

    test('matches and identifies Zoom MS-70CDR+', () {
      final reply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x26, 0x00, 0x31, 0x2E, 0x30, 0x30,
      ]);
      expect(protocol.matchesIdentityResponse(reply), isTrue);
      expect(protocol.parseDeviceFamily(reply), equals(DeviceFamily.zoomMs70cdrPlus));
    });

    test('matches and identifies Zoom MS-200D+', () {
      final reply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x25, 0x00, 0x31, 0x2E, 0x30, 0x30,
      ]);
      expect(protocol.matchesIdentityResponse(reply), isTrue);
      expect(protocol.parseDeviceFamily(reply), equals(DeviceFamily.zoomMs200dPlus));
    });

    test('rejects non-Zoom identity replies', () {
      final line6Reply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x0C, 0x01, 0x00,
      ]);
      expect(protocol.matchesIdentityResponse(line6Reply), isFalse);
      expect(protocol.parseDeviceFamily(line6Reply), equals(DeviceFamily.unknown));
    });
  });

  group('ZoomMsPlusProtocol Command Framing', () {
    test('buildInitSequence generates editor mode and pc mode commands', () {
      final seq = protocol.buildInitSequence();
      expect(seq.length, equals(2));

      // Editor mode enable: F0 52 00 6E 50 F7
      expect(seq[0].data, equals([0xF0, 0x52, 0x00, 0x6E, 0x50, 0xF7]));
      // PC mode enable: F0 52 00 6E 52 F7
      expect(seq[1].data, equals([0xF0, 0x52, 0x00, 0x6E, 0x52, 0xF7]));
    });

    test('buildEditorModeMessage handles enable and disable', () {
      final enableMsg = protocol.buildEditorModeMessage(enable: true);
      expect(enableMsg!.data, equals([0xF0, 0x52, 0x00, 0x6E, 0x50, 0xF7]));

      final disableMsg = protocol.buildEditorModeMessage(enable: false);
      expect(disableMsg!.data, equals([0xF0, 0x52, 0x00, 0x6E, 0x51, 0xF7]));
    });

    test('buildCurrentPatchRequest formats 64 13 SysEx', () {
      final msg = protocol.buildCurrentPatchRequest();
      expect(msg.data, equals([0xF0, 0x52, 0x00, 0x6E, 0x64, 0x13, 0xF7]));
    });

    test('buildPatchSlotRequest formats bank and program offsets', () {
      // Memory slot 25 with default 10 patches/bank: bank 2, prog 5
      final msg = protocol.buildPatchSlotRequest(25);
      expect(msg.data, equals([
        0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x02, 0x00, 0x05, 0x00, 0xF7,
      ]));
    });

    test('buildParameterEditMessage encodes slot, param, and 7-bit words', () {
      // slot 2, param 1, value 1500 (0x05DC) -> 1500 & 0x7F = 92 (0x5C), (1500 >> 7) & 0x7F = 11 (0x0B)
      final msg = protocol.buildParameterEditMessage(slotIndex: 2, paramIndex: 1, value: 1500);
      expect(msg.data, equals([
        0xF0, 0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x02, 0x01, 0x5C, 0x0B, 0x00, 0x00, 0x00, 0xF7,
      ]));
    });

    test('parseParameterEdit extracts parameters from hardware feedback', () {
      final feedbackMsg = MidiMessage.sysEx([
        0x52, 0x00, 0x6E, 0x64, 0x20, 0x01, 0x03, 0x02, 0x40, 0x01,
      ]);
      expect(protocol.isParameterEdit(feedbackMsg), isTrue);

      final parsed = protocol.parseParameterEdit(feedbackMsg);
      expect(parsed, isNotNull);
      expect(parsed!.slotIndex, equals(3));
      expect(parsed.paramIndex, equals(2));
      // value: 0x40 | (0x01 << 7) = 64 + 128 = 192
      expect(parsed.value, equals(192));
    });
  });

  group('ZoomMsPlusProtocol Patch Encoding & Decoding Round-Trip', () {
    test('encodes and decodes complete multi-slot patch losslessly', () {
      final originalPatch = Patch(
        id: 'zoom_test_patch',
        name: 'Funk Bass',
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
                  id: 'param_0',
                  name: 'Sense',
                  min: 0,
                  max: 10,
                  defaultValue: 6,
                ),
                currentValue: 7.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'param_1',
                  name: 'Attack',
                  min: 0,
                  max: 1,
                  defaultValue: 0,
                ),
                currentValue: 1.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 1,
            effectId: '0x02000010',
            effectName: 'Bass Preamp',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'param_0',
                  name: 'Bass',
                  min: 0,
                  max: 4095,
                  defaultValue: 2048,
                ),
                currentValue: 3000.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 2,
            effectId: '0x06000010',
            effectName: 'Bass Chorus',
            isEnabled: false,
            parameters: [
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'param_0',
                  name: 'Depth',
                  min: 0,
                  max: 100,
                  defaultValue: 50,
                ),
                currentValue: 80.0,
              ),
            ],
          ),
        ],
        metadata: {
          'tempo': 128.0,
          'activeEffectSlot': 1,
        },
      );

      final encodedMsg = protocol.encodePatch(originalPatch);
      expect(encodedMsg.isSysEx, isTrue);
      expect(protocol.isPatchDump(encodedMsg), isTrue);

      final decodedPatch = protocol.decodePatch(encodedMsg);

      expect(decodedPatch.name, equals('Funk Bass'));
      expect(decodedPatch.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));
      expect(decodedPatch.metadata['tempo'], equals(128.0));
      expect(decodedPatch.metadata['activeEffectSlot'], equals(1));

      expect(decodedPatch.slots.length, equals(3));

      // Slot 0 check
      expect(decodedPatch.slots[0].effectId, equals('0x01000010'));
      expect(decodedPatch.slots[0].isEnabled, isTrue);
      expect(decodedPatch.slots[0].parameters[0].currentValue, equals(7.0));
      expect(decodedPatch.slots[0].parameters[1].currentValue, equals(1.0));

      // Slot 1 check
      expect(decodedPatch.slots[1].effectId, equals('0x02000010'));
      expect(decodedPatch.slots[1].isEnabled, isTrue);
      expect(decodedPatch.slots[1].parameters[0].currentValue, equals(3000.0));

      // Slot 2 check (disabled)
      expect(decodedPatch.slots[2].effectId, equals('0x06000010'));
      expect(decodedPatch.slots[2].isEnabled, isFalse);
      expect(decodedPatch.slots[2].parameters[0].currentValue, equals(80.0));
    });
  });

  group('ZoomMsPlusProtocol Simulation over MockMidiTransport', () {
    test('performs full handshake and patch download over MockMidiTransport', () async {
      final mock = MockMidiTransport(initialPorts: [
        const MidiPortDescriptor(
          id: 'zoom_ms60b_port',
          name: 'ZOOM MS-60B+ MIDI',
          isInput: true,
          isOutput: true,
        ),
      ]);
      await mock.connect('zoom_ms60b_port');

      // Test Patch for mock responder
      final testPatch = Patch(
        id: 'zoom_active',
        name: 'Slap Solo',
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
                  id: 'param_0',
                  name: 'Sense',
                  min: 0,
                  max: 10,
                  defaultValue: 5,
                ),
                currentValue: 8.0,
              ),
            ],
          ),
        ],
        metadata: {'tempo': 115.0},
      );
      final testDumpMessage = protocol.encodePatch(testPatch);

      // Register responders
      // 1. Identity Request Responder
      mock.registerResponder(
        (req) => req.isSysEx && req.data.length >= 5 && req.data[1] == 0x7E && req.data[3] == 0x06 && req.data[4] == 0x01,
        (req) => MidiMessage.sysEx([
          0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x27, 0x00, 0x31, 0x2E, 0x30, 0x30,
        ]),
      );

      // 2. Current Patch Request Responder
      mock.registerResponder(
        (req) => req.isSysEx && req.data.length >= 7 && req.data[1] == 0x52 && req.data[4] == 0x64 && req.data[5] == 0x13,
        (req) => testDumpMessage,
      );

      // Step 1: Send Identity Request
      final identityReq = protocol.buildIdentityRequest();
      final identityReply = await mock.sendSysExAndWait(
        identityReq,
        responseMatcher: protocol.matchesIdentityResponse,
        timeout: const Duration(milliseconds: 500),
      );
      expect(identityReply, isNotNull);
      final detectedFamily = protocol.parseDeviceFamily(identityReply);
      expect(detectedFamily, equals(DeviceFamily.zoomMs60bPlus));

      // Step 2: Send Init Sequence
      for (final initMsg in protocol.buildInitSequence()) {
        await mock.send(initMsg);
      }
      expect(mock.sentMessages.length, equals(3)); // 1 id req + 2 init msgs

      // Step 3: Request Current Patch
      final patchReq = protocol.buildCurrentPatchRequest();
      final patchReply = await mock.sendSysExAndWait(
        patchReq,
        responseMatcher: protocol.isPatchDump,
        timeout: const Duration(milliseconds: 500),
      );
      expect(patchReply, isNotNull);

      // Step 4: Decode received patch
      final downloadedPatch = protocol.decodePatch(patchReply);
      expect(downloadedPatch.name, equals('Slap Solo'));
      expect(downloadedPatch.slots.first.effectName, equals('DYN Comp'));
      expect(downloadedPatch.slots.first.parameters.first.currentValue, equals(8.0));
      expect(downloadedPatch.metadata['tempo'], equals(115.0));
    });
  });
}
