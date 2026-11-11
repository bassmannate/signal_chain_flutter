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

  group('Line6BassPodProProtocol Identity Matching', () {
    test('matches and identifies Line 6 Bass Pod Pro identity reply', () {
      final reply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x0C, 0x01, 0x00, 0x03, 0x00, 0x31, 0x2E, 0x30, 0x30,
      ]);
      expect(protocol.matchesIdentityResponse(reply), isTrue);
      expect(protocol.parseDeviceFamily(reply), equals(DeviceFamily.line6BassPodPro));
    });

    test('rejects non-Line 6 identity replies', () {
      final zoomReply = MidiMessage.sysEx([
        0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x27, 0x00,
      ]);
      expect(protocol.matchesIdentityResponse(zoomReply), isFalse);
      expect(protocol.parseDeviceFamily(zoomReply), equals(DeviceFamily.unknown));
    });
  });

  group('Line6BassPodProProtocol Command Framing & CC Mapping', () {
    test('buildInitSequence and buildCurrentPatchRequest generate edit buffer request', () {
      final req = protocol.buildCurrentPatchRequest();
      expect(req.data, equals([0xF0, 0x00, 0x01, 0x0C, 0x01, 0x00, 0xF7]));

      final initSeq = protocol.buildInitSequence();
      expect(initSeq.length, equals(1));
      expect(initSeq.first.data, equals([0xF0, 0x00, 0x01, 0x0C, 0x01, 0x00, 0xF7]));
    });

    test('buildPatchSlotRequest generates standard MIDI Program Change', () {
      final pcMsg = protocol.buildPatchSlotRequest(14);
      expect(pcMsg.isProgramChange, isTrue);
      expect(pcMsg.data, equals([0xC0, 14]));
    });

    test('buildProgramDumpRequest generates program dump SysEx', () {
      final dumpReq = protocol.buildProgramDumpRequest(7);
      expect(dumpReq.data, equals([0xF0, 0x00, 0x01, 0x0C, 0x01, 0x01, 0x07, 0xF7]));
    });

    test('buildParameterEditMessage maps Amp controls to CCs', () {
      // Slot 0 (Amp):
      // Param 0 (Amp Model) -> CC #12
      final m0 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 0, value: 5);
      expect(m0.data, equals([0xB0, Line6BassPodProProtocol.ccAmpModel, 5]));

      // Param 1 (Drive) -> CC #4
      final m1 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 1, value: 95);
      expect(m1.data, equals([0xB0, Line6BassPodProProtocol.ccDrive, 95]));

      // Param 2 (Bass) -> CC #14
      final m2 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 2, value: 80);
      expect(m2.data, equals([0xB0, Line6BassPodProProtocol.ccBass, 80]));

      // Param 3 (Mid) -> CC #15
      final m3 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 3, value: 64);
      expect(m3.data, equals([0xB0, Line6BassPodProProtocol.ccMid, 64]));

      // Param 4 (Treble) -> CC #16
      final m4 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 4, value: 72);
      expect(m4.data, equals([0xB0, Line6BassPodProProtocol.ccTreble, 72]));

      // Param 5 (Channel Volume) -> CC #17
      final m5 = protocol.buildParameterEditMessage(slotIndex: 0, paramIndex: 5, value: 110);
      expect(m5.data, equals([0xB0, Line6BassPodProProtocol.ccChannelVolume, 110]));
    });

    test('buildParameterEditMessage maps Cabinet, Compressor, and FX controls to CCs', () {
      // Slot 1 (Cabinet), Param 0 (Cab Model) -> CC #13
      final cabMsg = protocol.buildParameterEditMessage(slotIndex: 1, paramIndex: 0, value: 3);
      expect(cabMsg.data, equals([0xB0, Line6BassPodProProtocol.ccCabinetModel, 3]));

      // Slot 2 (Compressor), Param 0 -> CC #64
      final compMsg = protocol.buildParameterEditMessage(slotIndex: 2, paramIndex: 0, value: 60);
      expect(compMsg.data, equals([0xB0, Line6BassPodProProtocol.ccCompressor, 60]));

      // Slot 3 (FX), Param 0 (FX Select) -> CC #11
      final fxSelMsg = protocol.buildParameterEditMessage(slotIndex: 3, paramIndex: 0, value: 2);
      expect(fxSelMsg.data, equals([0xB0, Line6BassPodProProtocol.ccEffectSelect, 2]));

      // Slot 3 (FX), Param 1 (FX Tweak) -> CC #19
      final fxTweakMsg = protocol.buildParameterEditMessage(slotIndex: 3, paramIndex: 1, value: 45);
      expect(fxTweakMsg.data, equals([0xB0, Line6BassPodProProtocol.ccEffectTweak, 45]));
    });

    test('parseParameterEdit resolves incoming CCs to slot, param, and value', () {
      // CC #4 (Drive) value 88
      final ccMsg = MidiMessage.controlChange(channel: 0, controller: 4, value: 88);
      expect(protocol.isParameterEdit(ccMsg), isTrue);

      final parsed = protocol.parseParameterEdit(ccMsg);
      expect(parsed, isNotNull);
      expect(parsed!.slotIndex, equals(0));
      expect(parsed.paramIndex, equals(1));
      expect(parsed.value, equals(88));
    });
  });

  group('Line6BassPodProProtocol Patch Decoding & Encoding Round-Trip', () {
    test('encodes and decodes 72-byte edit buffer patch losslessly', () {
      final originalPatch = Patch(
        id: 'line6_test_preset',
        name: 'SVT Punch',
        deviceFamily: DeviceFamily.line6BassPodPro,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: 'line6_amp_7',
            effectName: 'Rock Classic (Ampeg SVT)',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'amp_model',
                  name: 'Amp Model',
                  min: 0,
                  max: 15,
                  defaultValue: 0,
                ),
                currentValue: 7.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'drive',
                  name: 'Drive',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 85.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'bass',
                  name: 'Bass',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 90.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'mid',
                  name: 'Mid',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 45.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'treble',
                  name: 'Treble',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 70.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'chan_vol',
                  name: 'Channel Volume',
                  min: 0,
                  max: 127,
                  defaultValue: 100,
                ),
                currentValue: 105.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 1,
            effectId: 'line6_cab_6',
            effectName: '8x10 1974 Classic',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'cab_model',
                  name: 'Cabinet Model',
                  min: 0,
                  max: 7,
                  defaultValue: 0,
                ),
                currentValue: 6.0,
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
                descriptor: const ParameterDescriptor(
                  id: 'comp_threshold',
                  name: 'Comp Ratio / Threshold',
                  min: 0,
                  max: 127,
                  defaultValue: 0,
                ),
                currentValue: 50.0,
              ),
            ],
          ),
          EffectSlot(
            slotIndex: 3,
            effectId: 'line6_fx_1',
            effectName: 'Chorus',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'fx_type',
                  name: 'Effect Type',
                  min: 0,
                  max: 7,
                  defaultValue: 0,
                ),
                currentValue: 1.0,
              ),
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'fx_tweak',
                  name: 'Effect Tweak',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 40.0,
              ),
            ],
          ),
        ],
        metadata: {'masterVolume': 115.0},
      );

      final encodedMsg = protocol.encodePatch(originalPatch);
      expect(encodedMsg.isSysEx, isTrue);
      expect(protocol.isPatchDump(encodedMsg), isTrue);

      final decodedPatch = protocol.decodePatch(encodedMsg);

      expect(decodedPatch.name, equals('SVT Punch'));
      expect(decodedPatch.deviceFamily, equals(DeviceFamily.line6BassPodPro));
      expect(decodedPatch.metadata['masterVolume'], equals(115.0));

      // Amp checks
      final amp = decodedPatch.slots[0];
      expect(amp.effectName, equals('Rock Classic (Ampeg SVT)'));
      expect(amp.parameters[0].currentValue, equals(7.0));
      expect(amp.parameters[1].currentValue, equals(85.0)); // Drive
      expect(amp.parameters[2].currentValue, equals(90.0)); // Bass
      expect(amp.parameters[3].currentValue, equals(45.0)); // Mid
      expect(amp.parameters[4].currentValue, equals(70.0)); // Treble
      expect(amp.parameters[5].currentValue, equals(105.0)); // Chan Vol

      // Cab checks
      final cab = decodedPatch.slots[1];
      expect(cab.effectName, equals('8x10 1974 Classic'));
      expect(cab.parameters[0].currentValue, equals(6.0));

      // Comp checks
      final comp = decodedPatch.slots[2];
      expect(comp.isEnabled, isTrue);
      expect(comp.parameters[0].currentValue, equals(50.0));

      // FX checks
      final fx = decodedPatch.slots[3];
      expect(fx.effectName, equals('Chorus'));
      expect(fx.parameters[0].currentValue, equals(1.0));
      expect(fx.parameters[1].currentValue, equals(40.0));
    });
  });

  group('Line6BassPodProProtocol Simulation over MockMidiTransport', () {
    test('identifies Bass Pod Pro and retrieves active edit buffer', () async {
      final mock = MockMidiTransport(initialPorts: [
        const MidiPortDescriptor(
          id: 'line6_pod_port',
          name: 'Line 6 Bass Pod Pro Port',
          isInput: true,
          isOutput: true,
        ),
      ]);
      await mock.connect('line6_pod_port');

      final samplePatch = Patch(
        id: 'line6_active',
        name: 'Grit Bass',
        deviceFamily: DeviceFamily.line6BassPodPro,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: 'line6_amp_1',
            effectName: 'Classic (SVT)',
            isEnabled: true,
            parameters: [
              ParameterValue(
                descriptor: const ParameterDescriptor(
                  id: 'drive',
                  name: 'Drive',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 77.0,
              ),
            ],
          ),
        ],
      );
      final sampleDump = protocol.encodePatch(samplePatch);

      // Identity responder
      mock.registerResponder(
        (req) => req.isSysEx && req.data.length >= 5 && req.data[1] == 0x7E && req.data[4] == 0x01,
        (req) => MidiMessage.sysEx([
          0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x0C, 0x01, 0x00, 0x03, 0x00,
        ]),
      );

      // Edit buffer dump responder
      mock.registerResponder(
        (req) => protocol.isPatchDump(req) || (req.isSysEx && req.data.length == 7 && req.data[5] == 0x00),
        (req) => sampleDump,
      );

      // 1. Identity Inquiry
      final idReply = await mock.sendSysExAndWait(
        protocol.buildIdentityRequest(),
        responseMatcher: protocol.matchesIdentityResponse,
        timeout: const Duration(milliseconds: 500),
      );
      expect(idReply, isNotNull);
      expect(protocol.parseDeviceFamily(idReply), equals(DeviceFamily.line6BassPodPro));

      // 2. Fetch Edit Buffer Dump
      final dumpReply = await mock.sendSysExAndWait(
        protocol.buildCurrentPatchRequest(),
        responseMatcher: protocol.isPatchDump,
        timeout: const Duration(milliseconds: 500),
      );
      expect(dumpReply, isNotNull);

      final decoded = protocol.decodePatch(dumpReply);
      expect(decoded.name, equals('Grit Bass'));
      expect(decoded.slots[0].parameters[1].currentValue, equals(77.0));
    });
  });
}
