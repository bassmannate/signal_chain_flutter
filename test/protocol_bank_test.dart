import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/models/bank_slot_descriptor.dart';
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

  group('ZoomMsPlusProtocol - Memory Bank Slots (0–99)', () {
    const protocol = ZoomMsPlusProtocol();

    test('buildInitSequence sends 0x53 (PC Mode Disable) and 0x50 (Parameter Edit Enable) and NEVER 0x52', () {
      final seq = protocol.buildInitSequence();
      expect(seq.length, equals(2));

      // 1. First message must be 0x53 (PC Mode Disable)
      expect(
        seq[0].data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x53, 0xF7]),
      );

      // 2. Second message must be 0x50 (Parameter Edit Enable)
      expect(
        seq[1].data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x50, 0xF7]),
      );

      // 3. Ensure 0x52 (PC Mode Enable which locks the screen) is never present
      for (final msg in seq) {
        expect(msg.data.contains(0x52) && msg.data[4] == 0x52, isFalse,
            reason: 'Init sequence must not send 0x52 PC Mode Enable (USB lock icon)');
      }
    });

    test('isCurrentPatchDump, isSlotPatchDump, and extractSlotIndex accurately differentiate edit buffer from slots', () {
      const sample = Patch(
        id: 'zoom_diff_test',
        name: 'Distortion 1',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [],
      );

      final currentV2 = protocol.encodePatch(sample);
      expect(protocol.isCurrentPatchDump(currentV2), isTrue);
      expect(protocol.isSlotPatchDump(currentV2), isFalse);
      expect(protocol.extractSlotIndex(currentV2), isNull);

      final slot42 = protocol.buildSavePatchToSlotMessage(sample, 42);
      expect(protocol.isCurrentPatchDump(slot42), isFalse);
      expect(protocol.isSlotPatchDump(slot42), isTrue);
      expect(protocol.extractSlotIndex(slot42), equals(42));
    });

    test('buildSlotSelectMessages builds Bank Select CC 0/32 and Program Change without slot write', () {
      final messages = protocol.buildSlotSelectMessages(42);
      expect(messages.length, equals(3));

      // CC 0 = 0
      expect(messages[0].isControlChange, isTrue);
      expect(messages[0].data[1], equals(0x00));
      expect(messages[0].data[2], equals(0x00));

      // CC 32 = bank 4
      expect(messages[1].isControlChange, isTrue);
      expect(messages[1].data[1], equals(0x20));
      expect(messages[1].data[2], equals(4));

      // PC = prog 2
      expect(messages[2].isProgramChange, isTrue);
      expect(messages[2].data[1], equals(2));
    });

    test('buildPatchSlotRequest encodes exact SysEx for slots 0, 1, 9, 10, 42, 99', () {
      // Slot 0 -> Bank 0, Prog 0
      final req0 = protocol.buildPatchSlotRequest(0);
      expect(
        req0.data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF7]),
      );

      // Slot 1 -> Bank 0, Prog 1
      final req1 = protocol.buildPatchSlotRequest(1);
      expect(
        req1.data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xF7]),
      );

      // Slot 9 -> Bank 0, Prog 9
      final req9 = protocol.buildPatchSlotRequest(9);
      expect(
        req9.data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x00, 0x00, 0x09, 0x00, 0xF7]),
      );

      // Slot 10 -> Bank 1, Prog 0
      final req10 = protocol.buildPatchSlotRequest(10);
      expect(
        req10.data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xF7]),
      );

      // Slot 42 -> Bank 4, Prog 2
      final req42 = protocol.buildPatchSlotRequest(42);
      expect(
        req42.data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x04, 0x00, 0x02, 0x00, 0xF7]),
      );

      // Slot 99 -> Bank 9, Prog 9
      final req99 = protocol.buildPatchSlotRequest(99);
      expect(
        req99.data,
        equals([0xF0, 0x52, 0x00, 0x6E, 0x46, 0x00, 0x00, 0x09, 0x00, 0x09, 0x00, 0xF7]),
      );
    });

    test('buildSavePatchToSlotMessage encodes valid Memory Slot Dump V2 framing and round-trips', () {
      const samplePatch = Patch(
        id: 'zoom_test_slot',
        name: 'FunkSlap',
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
                currentValue: 7,
              ),
            ],
          ),
        ],
        metadata: {'tempo': 128},
      );

      const targetSlot = 42; // Bank 4, Prog 2
      final saveMsg = protocol.buildSavePatchToSlotMessage(samplePatch, targetSlot);

      expect(saveMsg.isSysEx, isTrue);
      // Header: F0 52 00 6E 45 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> <len_lsb> <len_msb>
      expect(saveMsg.data[0], equals(0xF0));
      expect(saveMsg.data[1], equals(0x52)); // Manufacturer
      expect(saveMsg.data[2], equals(0x00));
      expect(saveMsg.data[3], equals(0x6E)); // Family
      expect(saveMsg.data[4], equals(0x45)); // Memory Dump Command
      expect(saveMsg.data[5], equals(0x00));
      expect(saveMsg.data[6], equals(0x00));
      expect(saveMsg.data[7], equals(4)); // Bank LSB
      expect(saveMsg.data[8], equals(0)); // Bank MSB
      expect(saveMsg.data[9], equals(2)); // Prog LSB
      expect(saveMsg.data[10], equals(0)); // Prog MSB
      expect(saveMsg.data.last, equals(0xF7));

      // Verify isPatchDump recognizes the memory dump
      expect(protocol.isPatchDump(saveMsg), isTrue);

      // Verify decodePatch extracts targetSlot and patch contents correctly
      final decoded = protocol.decodePatch(saveMsg);
      expect(decoded.programNumber, equals(42));
      expect(decoded.name, equals('FunkSlap'));
      expect(decoded.tempo, equals(128));
      expect(decoded.slots.length, equals(1));
      expect(decoded.slots.first.effectName, equals('DYN Comp'));
    });

    test('encodePatch with programNumber parameter delegates to buildSavePatchToSlotMessage', () {
      const sample = Patch(
        id: 'zoom_test',
        name: 'RockBass',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [],
      );

      final slotMsg = protocol.encodePatch(sample, programNumber: 73);
      expect(slotMsg.data[4], equals(0x45)); // Memory dump
      expect(slotMsg.data[7], equals(7)); // Bank 7
      expect(slotMsg.data[9], equals(3)); // Prog 3

      final editBufferMsg = protocol.encodePatch(sample);
      expect(editBufferMsg.data[4], equals(0x64)); // Current patch edit buffer dump
      expect(editBufferMsg.data[5], equals(0x12));
    });

    test('accurately extracts patch name with trailing null bytes stripped and printable ASCII preserved', () {
      const sample = Patch(
        id: 'zoom_ptcf_name_test',
        name: 'Funk & Slap 42',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [],
      );

      final msg = protocol.buildSavePatchToSlotMessage(sample, 18);
      final decoded = protocol.decodePatch(msg);

      expect(decoded.name, equals('Funk & Slap 42'));
      expect(decoded.name.contains('\x00'), isFalse);
      expect(decoded.programNumber, equals(18));
    });

    test('supports Current Patch dump opcode 0x28 and 0x64 0x12 in isPatchDump and decodePatch', () {
      const sample = Patch(
        id: 'zoom_active',
        name: 'Active Slap',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        slots: [],
      );

      final v2Msg = protocol.encodePatch(sample);
      expect(protocol.isPatchDump(v2Msg), isTrue);
      final decodedV2 = protocol.decodePatch(v2Msg);
      expect(decodedV2.name, equals('Active Slap'));

      // Construct a 0x28 message wrapping the same PTCF payload
      final packed7Bit = protocol.encodePatch(sample).data.sublist(9, protocol.encodePatch(sample).data.length - 7);
      final v1Data = [
        0xF0, 0x52, 0x00, 0x6E, 0x28,
        ...packed7Bit,
        0xF7,
      ];
      final v1Msg = MidiMessage(Uint8List.fromList(v1Data));
      expect(protocol.isPatchDump(v1Msg), isTrue);
    });

    test('parses both 0x64 0x20 (MS Plus) and 0x31 (MS V1) real-time parameter edits', () {
      // 1. MS Plus parameter edit (F0 52 00 6E 64 20 00 <slot> <param> <v0> <v1> <v2> <v3> <v4> F7)
      final v2Msg = protocol.buildParameterEditMessage(
        slotIndex: 2,
        paramIndex: 3,
        value: 120,
      );
      expect(protocol.isParameterEdit(v2Msg), isTrue);
      final parsedV2 = protocol.parseParameterEdit(v2Msg);
      expect(parsedV2, isNotNull);
      expect(parsedV2!.slotIndex, equals(2));
      expect(parsedV2.paramIndex, equals(3));
      expect(parsedV2.value, equals(120));

      // 2. Legacy Zoom MS parameter edit (F0 52 00 6E 31 <slot> <param> <v_lsb> <v_msb> F7)
      // slot 1, param 4, value 75 (0x4B, 0x00)
      final v1Msg = MidiMessage(Uint8List.fromList([
        0xF0, 0x52, 0x00, 0x6E, 0x31, 0x01, 0x04, 0x4B, 0x00, 0xF7,
      ]));
      expect(protocol.isParameterEdit(v1Msg), isTrue);
      final parsedV1 = protocol.parseParameterEdit(v1Msg);
      expect(parsedV1, isNotNull);
      expect(parsedV1!.slotIndex, equals(1));
      expect(parsedV1.paramIndex, equals(4));
      expect(parsedV1.value, equals(75));
    });
  });

  group('Line6BassPodProProtocol - Memory Bank Slots', () {
    const protocol = Line6BassPodProProtocol();

    test('buildProgramDumpRequest encodes correct SysEx for arbitrary slots', () {
      final req0 = protocol.buildProgramDumpRequest(0);
      expect(req0.data, equals([0xF0, 0x00, 0x01, 0x0C, 0x01, 0x01, 0x00, 0xF7]));

      final req15 = protocol.buildProgramDumpRequest(15);
      expect(req15.data, equals([0xF0, 0x00, 0x01, 0x0C, 0x01, 0x01, 0x0F, 0xF7]));

      final req63 = protocol.buildProgramDumpRequest(63);
      expect(req63.data, equals([0xF0, 0x00, 0x01, 0x0C, 0x01, 0x01, 0x3F, 0xF7]));
    });

    test('buildSavePatchToSlotMessage encodes Program Dump SysEx with program number and round-trips', () {
      const patch = Patch(
        id: 'line6_test',
        name: 'SVT Grunt',
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
                  id: 'drive',
                  name: 'Drive',
                  min: 0,
                  max: 127,
                  defaultValue: 64,
                ),
                currentValue: 88,
              ),
            ],
          ),
        ],
      );

      final saveMsg = protocol.buildSavePatchToSlotMessage(patch, 12);
      expect(saveMsg.isSysEx, isTrue);
      expect(saveMsg.data[1], equals(0x00));
      expect(saveMsg.data[2], equals(0x01));
      expect(saveMsg.data[3], equals(0x0C));
      expect(saveMsg.data[4], equals(0x01));
      expect(saveMsg.data[5], equals(0x01)); // Program dump opcode
      expect(saveMsg.data[6], equals(12)); // Program number

      expect(protocol.isPatchDump(saveMsg), isTrue);

      final decoded = protocol.decodePatch(saveMsg);
      expect(decoded.programNumber, equals(12));
      expect(decoded.name, equals('SVT Grunt'));
      expect(decoded.slots[0].parameters.firstWhere((p) => p.descriptor.id == 'drive').currentValue, equals(88));
    });
  });

  group('BankSlotDescriptor Model', () {
    test('formats slot indices, banks, and labels cleanly', () {
      const slot0 = BankSlotDescriptor(
        index: 0,
        name: 'Init Patch',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
      );
      expect(slot0.formattedSlotIndex, equals('00'));
      expect(slot0.bankAndProgramNumber, equals('1-1'));
      expect(slot0.slotLabel, equals('#00 (1-1)'));

      const slot42 = BankSlotDescriptor(
        index: 42,
        name: 'Modern Slap',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
        isLoaded: true,
      );
      expect(slot42.formattedSlotIndex, equals('42'));
      expect(slot42.bankAndProgramNumber, equals('5-3'));
      expect(slot42.slotLabel, equals('#42 (5-3)'));

      const slot99 = BankSlotDescriptor(
        index: 99,
        name: 'Ambient Delay',
        deviceFamily: DeviceFamily.zoomMs60bPlus,
      );
      expect(slot99.formattedSlotIndex, equals('99'));
      expect(slot99.bankAndProgramNumber, equals('10-10'));
      expect(slot99.slotLabel, equals('#99 (10-10)'));
    });

    test('supports equality and copyWith', () {
      const slotA = BankSlotDescriptor(index: 5, name: 'Patch A');
      final slotB = slotA.copyWith(name: 'Patch B', isLoaded: true);
      expect(slotB.index, equals(5));
      expect(slotB.name, equals('Patch B'));
      expect(slotB.isLoaded, isTrue);
      expect(slotA == slotB, isFalse);

      final slotAClone = slotA.copyWith();
      expect(slotAClone, equals(slotA));
    });
  });
}
