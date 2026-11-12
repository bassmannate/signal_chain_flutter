import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/line6_bass_pod_pro_protocol.dart';

void main() {
  const protocol = Line6BassPodProProtocol(midiChannel: 0);

  group('Line6BassPodProProtocol Identity Handshake & Matching', () {
    test('buildIdentityRequest generates standard Universal SysEx Identity Request', () {
      final req = protocol.buildIdentityRequest();
      expect(req.data, equals([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]));
    });

    test('matches hardware firmware 1.40 Line 6 Bass POD Pro identity response', () {
      // Verbatim hardware capture from Bass POD Pro firmware 1.40
      final reply = MidiMessage.sysEx([
        0xF0, 0x7E, 0x7F, 0x06, 0x02,
        0x00, 0x01, 0x0C, // Line 6 manufacturer ID (USB Vendor 0x0E41)
        0x02, 0x00, // Family code LSB first: 0x0002 (Bass POD / Pro)
        0x01, 0x00, // Member code: 0x0001
        0x30, 0x31, 0x34, 0x30, // Firmware "0140"
        0xF7,
      ]);

      expect(protocol.matchesIdentityResponse(reply), isTrue);
      expect(protocol.parseDeviceFamily(reply), equals(DeviceFamily.line6BassPodPro));
    });

    test('rejects other Line 6 family codes and non-Line 6 identity responses', () {
      // Line 6 POD 2.0 / POD Pro (family code 0x0001) must not match Bass POD Pro
      final pod2Reply = MidiMessage.sysEx([
        0xF0, 0x7E, 0x7F, 0x06, 0x02,
        0x00, 0x01, 0x0C,
        0x01, 0x00,
        0x01, 0x00,
        0x32, 0x30, 0x30, 0x30,
        0xF7,
      ]);

      final zoomReply = MidiMessage.sysEx([
        0xF0, 0x7E, 0x7F, 0x06, 0x02,
        0x52, 0x6E, 0x00, 0x27, 0x00,
        0x31, 0x2E, 0x30, 0x30,
        0xF7,
      ]);

      expect(protocol.matchesIdentityResponse(pod2Reply), isFalse);
      expect(() => protocol.parseDeviceFamily(pod2Reply), throwsFormatException);
      expect(protocol.matchesIdentityResponse(zoomReply), isFalse);
    });
  });

  group('Line6BassPodProProtocol Command Framing & CC Mapping', () {
    test('buildInitSequence and request messages follow 0x02 family SysEx spec', () {
      expect(protocol.buildEditorModeMessage(enable: true), isNull);

      final initSeq = protocol.buildInitSequence();
      expect(initSeq.length, equals(1));
      expect(
        initSeq.first.data,
        equals([0xF0, 0x00, 0x01, 0x0C, 0x02, 0x00, 0x01, 0xF7]),
      );

      final curReq = protocol.buildCurrentPatchRequest();
      expect(
        curReq.data,
        equals([0xF0, 0x00, 0x01, 0x0C, 0x02, 0x00, 0x01, 0xF7]),
      );

      final slotReq7 = protocol.buildProgramDumpRequest(7);
      expect(
        slotReq7.data,
        equals([0xF0, 0x00, 0x01, 0x0C, 0x02, 0x00, 0x00, 0x07, 0xF7]),
      );

      final slotReq35 = protocol.buildPatchSlotRequest(35);
      expect(
        slotReq35.data,
        equals([0xF0, 0x00, 0x01, 0x0C, 0x02, 0x00, 0x00, 0x23, 0xF7]),
      );

      final allReq = protocol.buildAllProgramsDumpRequest();
      expect(
        allReq.data,
        equals([0xF0, 0x00, 0x01, 0x0C, 0x02, 0x00, 0x02, 0xF7]),
      );
    });

    test('buildSlotSelectMessages offsets PC by +1 (Manual = 0, 1A..9D = 1..36)', () {
      expect(protocol.buildSlotSelectMessages(0).first.data, equals([0xC0, 1]));
      expect(protocol.buildSlotSelectMessages(35).first.data, equals([0xC0, 36]));
    });

    test('buildParameterEditMessage maps Amp controls to verified CCs', () {
      final m0 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 0, value: 5);
      expect(m0.data, equals([0xB0, Line6BassPodProProtocol.ccAmpModel, 5])); // CC#12

      final m1 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 1, value: 94);
      expect(m1.data, equals([0xB0, Line6BassPodProProtocol.ccDrive, 94])); // CC#13

      final m2 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 2, value: 80);
      expect(m2.data, equals([0xB0, Line6BassPodProProtocol.ccBass, 80])); // CC#14

      final m3 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 3, value: 64);
      expect(m3.data, equals([0xB0, Line6BassPodProProtocol.ccMid, 64])); // CC#15

      final m4 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 4, value: 72);
      expect(m4.data, equals([0xB0, Line6BassPodProProtocol.ccTreble, 72])); // CC#16

      final m5 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 5, value: 110);
      expect(m5.data, equals([0xB0, Line6BassPodProProtocol.ccChannelVolume, 110])); // CC#17
    });

    test('buildParameterEditMessage maps Cabinet, Compressor, and FX controls to verified CCs', () {
      final cabMsg = protocol.buildParameterEditMessage(slotIndex: 1, paramIndex: 0, value: 11);
      expect(cabMsg.data, equals([0xB0, Line6BassPodProProtocol.ccCabinetModel, 11])); // CC#71

      final airMsg = protocol.buildParameterEditMessage(slotIndex: 1, paramIndex: 1, value: 50);
      expect(airMsg.data, equals([0xB0, Line6BassPodProProtocol.ccAirLevel, 50])); // CC#72

      final compMsg = protocol.buildParameterEditMessage(slotIndex: 2, paramIndex: 0, value: 60);
      expect(compMsg.data, equals([0xB0, Line6BassPodProProtocol.ccCompressor, 60])); // CC#18

      final gateMsg = protocol.buildParameterEditMessage(slotIndex: 2, paramIndex: 1, value: 127);
      expect(gateMsg.data, equals([0xB0, Line6BassPodProProtocol.ccNoiseGate, 127])); // CC#22

      final fxSelMsg = protocol.buildParameterEditMessage(slotIndex: 3, paramIndex: 0, value: 9);
      expect(fxSelMsg.data, equals([0xB0, Line6BassPodProProtocol.ccEffectSelect, 9])); // CC#19

      final fxTweakMsg = protocol.buildParameterEditMessage(slotIndex: 3, paramIndex: 1, value: 44);
      expect(fxTweakMsg.data, equals([0xB0, Line6BassPodProProtocol.ccEffectTweak, 44])); // CC#1

      final fxLoCutMsg = protocol.buildParameterEditMessage(slotIndex: 3, paramIndex: 2, value: 20);
      expect(fxLoCutMsg.data, equals([0xB0, Line6BassPodProProtocol.ccFxLoCut, 20])); // CC#21

      final fxBypassMsg = protocol.buildSlotBypassMessage(slotIndex: 3, isEnabled: true);
      expect(fxBypassMsg?.data, equals([0xB0, Line6BassPodProProtocol.ccEffectOnOff, 127])); // CC#60
    });

    test('parseParameterEdit resolves incoming verified CCs to slot, param, and value', () {
      final msgDrive = MidiMessage.controlChange(channel: 0, controller: 13, value: 112);
      expect(protocol.isParameterEdit(msgDrive), isTrue);
      expect(
        protocol.parseParameterEdit(msgDrive),
        equals((slotIndex: 0, paramIndex: 1, value: 112)),
      );

      final msgCab = MidiMessage.controlChange(channel: 0, controller: 71, value: 8);
      expect(protocol.isParameterEdit(msgCab), isTrue);
      expect(
        protocol.parseParameterEdit(msgCab),
        equals((slotIndex: 1, paramIndex: 0, value: 8)),
      );

      final msgWrongCh = MidiMessage.controlChange(channel: 1, controller: 13, value: 112);
      expect(protocol.isParameterEdit(msgWrongCh), isFalse);
      expect(protocol.parseParameterEdit(msgWrongCh), isNull);
    });
  });

  group('Line6BassPodProProtocol Hardware Capture & Round-Trip Decoding', () {
    test('decodes real firmware 1.40 hardware edit-buffer capture ("Eighties")', () {
      // Verbatim hardware SysEx capture from test/fixtures/bass-pod-pro-edit-buffer.txt (169 bytes)
      final capturedEditBuffer = MidiMessage.sysEx([
        0xF0, 0x00, 0x01, 0x0C, 0x02, 0x01, 0x01, 0x01,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x0D, 0x00, 0x0D, 0x02, 0x03, 0x02, 0x01, 0x03, 0x08, 0x00, 0x00, 0x03, 0x0F, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00,
        0x00, 0x0D, 0x00, 0x0E, 0x00, 0x00, 0x02, 0x01, 0x07, 0x0F, 0x00, 0x00, 0x07, 0x0F, 0x02, 0x00, 0x00, 0x00, 0x01, 0x0E, 0x07, 0x0F, 0x03, 0x09, 0x05, 0x03, 0x02, 0x06, 0x03, 0x04, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, 0x0F, 0x0E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x08, 0x01, 0x0C, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x04, 0x05, 0x06, 0x09, 0x06, 0x07, 0x06, 0x08, 0x07, 0x04, 0x06, 0x09, 0x06, 0x05, 0x07, 0x03, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00,
        0xF7,
      ]);

      expect(capturedEditBuffer.data.length, equals(169));
      expect(protocol.isCurrentPatchDump(capturedEditBuffer), isTrue);
      expect(protocol.isSlotPatchDump(capturedEditBuffer), isFalse);
      expect(protocol.isPatchDump(capturedEditBuffer), isTrue);

      final patch = protocol.decodePatch(capturedEditBuffer);
      expect(patch.name, equals('Eighties'));
      expect(patch.programNumber, isNull);
      expect(patch.slots.length, equals(4));

      // Slot 0: Amp ("Eighties", model 5)
      final amp = patch.slots[0];
      expect(amp.effectId, equals('line6_amp_5'));
      expect(amp.effectName, equals('Eighties'));
      expect(amp.parameters[0].currentValue, equals(5.0)); // Amp Model
      expect(amp.parameters[1].currentValue, equals(26.0)); // Drive (13 * 2)
      expect(amp.parameters[2].currentValue, equals(70.0)); // Bass (35 * 2)
      expect(amp.parameters[3].currentValue, equals(66.0)); // Mid (33 * 2)
      expect(amp.parameters[4].currentValue, equals(112.0)); // Treble (56 * 2)
      expect(amp.parameters[5].currentValue, equals(126.0)); // Channel Vol (63 * 2)

      // Slot 1: Cabinet (model 0: "4x10 Hartke")
      final cab = patch.slots[1];
      expect(cab.effectId, equals('line6_cab_0'));
      expect(cab.effectName, equals('4x10 Hartke'));
      expect(cab.isEnabled, isTrue);

      // Slot 2: Compressor (0) & Noise Gate (1)
      final comp = patch.slots[2];
      expect(comp.isEnabled, isTrue);
      expect(comp.parameters[0].currentValue, equals(0.0));
      expect(comp.parameters[1].currentValue, equals(1.0));

      // Slot 3: Effect (model 10: "Bypass")
      final fx = patch.slots[3];
      expect(fx.effectId, equals('line6_fx_10'));
      expect(fx.effectName, equals('Bypass'));
      expect(fx.isEnabled, isFalse);
    });

    test('round-trips a full Patch through MSB-first nibble edit-buffer and slot dumps', () {
      const originalPatch = Patch(
        id: 'line6_test_patch',
        name: 'Motor City Punch',
        deviceFamily: DeviceFamily.line6BassPodPro,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: 'line6_amp_13',
            effectName: 'Motor City',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'amp_model', name: 'Amp Model', min: 0, max: 15, defaultValue: 0),
                currentValue: 13.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'drive', name: 'Drive', min: 0, max: 126, defaultValue: 64, step: 2),
                currentValue: 96.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'bass', name: 'Bass', min: 0, max: 126, defaultValue: 64, step: 2),
                currentValue: 84.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'mid', name: 'Mid', min: 0, max: 126, defaultValue: 64, step: 2),
                currentValue: 52.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'treble', name: 'Treble', min: 0, max: 126, defaultValue: 64, step: 2),
                currentValue: 74.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'channel_volume', name: 'Channel Volume', min: 0, max: 126, defaultValue: 100, step: 2),
                currentValue: 112.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 1,
            effectId: 'line6_cab_11',
            effectName: '8x10 Ampeg SVT',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'cab_model', name: 'Cabinet', min: 0, max: 15, defaultValue: 0),
                currentValue: 11.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'air_level', name: 'A.I.R. Level', min: 0, max: 126, defaultValue: 0, step: 2),
                currentValue: 40.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 2,
            effectId: 'line6_comp',
            effectName: 'Compressor',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'compressor', name: 'Compress', min: 0, max: 126, defaultValue: 0, step: 2),
                currentValue: 50.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'noise_gate', name: 'Noise Gate', min: 0, max: 1, defaultValue: 0),
                currentValue: 1.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 3,
            effectId: 'line6_fx_9',
            effectName: 'Analog Chorus',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'fx_select', name: 'Effect Type', min: 0, max: 15, defaultValue: 10),
                currentValue: 9.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'fx_tweak', name: 'Effect Tweak', min: 0, max: 126, defaultValue: 0, step: 2),
                currentValue: 46.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'fx_lo_cut', name: 'FX Lo Cut', min: 0, max: 126, defaultValue: 0, step: 2),
                currentValue: 18.0,
              ),
            ],
          ),
        ],
      );

      // 1. Edit buffer round-trip (169 bytes)
      final editDump = protocol.encodePatch(originalPatch);
      expect(editDump.data.length, equals(169));
      expect(protocol.isCurrentPatchDump(editDump), isTrue);
      final decodedEdit = protocol.decodePatch(editDump);
      expect(decodedEdit.name, equals('Motor City Punch'));
      expect(decodedEdit.slots[0].effectName, equals('Motor City'));
      expect(decodedEdit.slots[0].parameters[1].currentValue, equals(96.0));
      expect(decodedEdit.slots[1].effectName, equals('8x10 Ampeg SVT'));
      expect(decodedEdit.slots[1].parameters[1].currentValue, equals(40.0));
      expect(decodedEdit.slots[2].parameters[0].currentValue, equals(50.0));
      expect(decodedEdit.slots[2].parameters[1].currentValue, equals(1.0));
      expect(decodedEdit.slots[3].effectName, equals('Analog Chorus'));
      expect(decodedEdit.slots[3].isEnabled, isTrue);
      expect(decodedEdit.slots[3].parameters[1].currentValue, equals(46.0));
      expect(decodedEdit.slots[3].parameters[2].currentValue, equals(18.0));

      // 2. Program slot dump round-trip (170 bytes)
      final slotDump = protocol.buildSavePatchToSlotMessage(originalPatch, 21);
      expect(slotDump.data.length, equals(170));
      expect(protocol.isSlotPatchDump(slotDump), isTrue);
      expect(protocol.extractSlotIndex(slotDump), equals(21));
      final decodedSlot = protocol.decodePatch(slotDump);
      expect(decodedSlot.programNumber, equals(21));
      expect(decodedSlot.name, equals('Motor City Punch'));
      expect(decodedSlot.slots[0].effectId, equals('line6_amp_13'));
    });

    test('decodeEditBuffer handles raw un-nibbled 80-byte payload gracefully', () {
      final raw = Uint8List(80);
      raw[3] = 8; // Rock Classic
      raw[4] = 40; // Drive = 80
      raw[31] = 11; // 8x10 Ampeg SVT
      final nameStr = 'Raw Pod Test    ';
      for (int i = 0; i < 16; i++) {
        raw[64 + i] = nameStr.codeUnitAt(i);
      }

      final patch = protocol.decodeEditBuffer(raw, programNumber: 5);
      expect(patch.name, equals('Raw Pod Test'));
      expect(patch.programNumber, equals(5));
      expect(patch.slots[0].effectName, equals('Rock Classic'));
      expect(patch.slots[0].parameters[1].currentValue, equals(80.0));
      expect(patch.slots[1].effectName, equals('8x10 Ampeg SVT'));
    });
  });

  group('Line6BassPodProProtocol Simulation over MockMidiTransport', () {
    test('simulates identity handshake and edit-buffer dump over mock transport', () async {
      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'mock_1',
            name: 'Line 6 Bass POD Pro',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      await transport.connect('mock_1');

      const samplePatch = Patch(
        id: 'sim_1',
        name: 'Simulated SVT',
        deviceFamily: DeviceFamily.line6BassPodPro,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: 'line6_amp_8',
            effectName: 'Rock Classic',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'amp_model', name: 'Amp Model', min: 0, max: 15, defaultValue: 8),
                currentValue: 8.0,
              ),
              ParameterValue(
                descriptor: ParameterDescriptor(id: 'drive', name: 'Drive', min: 0, max: 126, defaultValue: 64, step: 2),
                currentValue: 100.0,
              ),
            ],
          ),
        ],
      );

      final sampleDump = protocol.encodePatch(samplePatch);

      // Register auto-responder for Universal Identity Request
      transport.registerResponder(
        (req) =>
            req.isSysEx &&
            req.data.length >= 5 &&
            req.data[1] == 0x7E &&
            req.data[3] == 0x06 &&
            req.data[4] == 0x01,
        (req) => MidiMessage.sysEx([
          0x7E, 0x00, 0x06, 0x02,
          0x00, 0x01, 0x0C,
          0x02, 0x00, 0x01, 0x00,
          0x30, 0x31, 0x34, 0x30,
        ]),
      );

      // Register auto-responder for Edit Buffer Request (F0 00 01 0C 02 00 01 F7)
      transport.registerResponder(
        (req) =>
            req.isSysEx &&
            req.data.length >= 7 &&
            req.data[1] == 0x00 &&
            req.data[2] == 0x01 &&
            req.data[3] == 0x0C &&
            req.data[4] == 0x02 &&
            req.data[5] == 0x00 &&
            req.data[6] == 0x01,
        (req) => sampleDump,
      );

      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      await transport.send(protocol.buildIdentityRequest());
      await transport.send(protocol.buildCurrentPatchRequest());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, equals(2));
      expect(protocol.matchesIdentityResponse(received[0]), isTrue);
      expect(protocol.isPatchDump(received[1]), isTrue);

      final decoded = protocol.decodePatch(received[1]);
      expect(decoded.name, equals('Simulated SVT'));
      expect(decoded.slots[0].effectName, equals('Rock Classic'));
      expect(decoded.slots[0].parameters[1].currentValue, equals(100.0));

      await sub.cancel();
      transport.dispose();
    });
  });
}
