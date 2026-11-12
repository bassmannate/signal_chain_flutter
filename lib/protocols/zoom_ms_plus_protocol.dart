import 'dart:convert';
import 'dart:typed_data';

import '../core/midi/midi_message.dart';
import '../models/device_family.dart';
import '../models/effect_slot.dart';
import '../models/parameter_descriptor.dart';
import '../models/patch.dart';
import 'catalogs/effect_catalog.dart';
import 'device_protocol.dart';
import 'sysex_codec.dart';

/// Pure Dart protocol engine for Zoom MS Plus series pedals
/// (MS-50G+, MS-60B+, MS-70CDR+, MS-200D+).
class ZoomMsPlusProtocol extends DeviceProtocol {
  /// Zoom MIDI Manufacturer ID: 0x52.
  static const int manufacturerId = 0x52;

  /// Zoom MS Plus Family ID byte (data[3] in SysEx frames).
  static const int familyIdByte = 0x6E;

  /// Model ID codes (Identity Reply byte 8).
  static const int modelIdMs50gPlus = 0x23;
  static const int modelIdMs200dPlus = 0x25;
  static const int modelIdMs70cdrPlus = 0x26;
  static const int modelIdMs60bPlus = 0x27;

  /// SysEx Command Opcode bytes (V2 protocol).
  static const int cmdParameterEditEnable = 0x50;
  static const int cmdParameterEditDisable = 0x51;
  static const int cmdPcModeEnable = 0x52;
  static const int cmdPcModeDisable = 0x53;
  static const int cmdCurrentPatchRequest = 0x13; // with prefix 0x64
  static const int cmdCurrentPatchDump = 0x12; // with prefix 0x64
  static const int cmdMemoryPatchRequest = 0x46; // with prefix 0x00 0x00
  static const int cmdMemoryPatchDump = 0x45; // with prefix 0x00 0x00
  static const int cmdParameterEdit = 0x20; // with prefix 0x64 0x20 0x00
  static const int cmdParameterAccepted = 0x01; // with prefix 0x64 0x20 0x01
  static const int cmdBankAndProgramV2 = 0x26; // with prefix 0x64 0x26 0x00 0x00
  static const int cmdCurrentPatchDumpV1 = 0x28; // legacy Zoom current patch dump
  static const int cmdParameterEditV1 = 0x31; // legacy Zoom real-time parameter edit

  /// Target pedal constants in PTCF header.
  static const int ptcfTargetMs50gPlus = 0x00040000;
  static const int ptcfTargetMs60bPlus = 0x00080000;

  /// Fixed length of EDTB per-effect binary block in bytes.
  static const int edtbEffectBlockSize = 24;

  /// Fixed name field length in NAME chunk for MS Plus (28 ASCII chars + 4 nulls = 32 bytes).
  static const int msPlusNameLength = 32;

  /// Default maximum number of effect blocks supported on MS Plus series.
  static const int defaultMaxSlots = 6;

  final DeviceFamily defaultFamily;

  const ZoomMsPlusProtocol({
    this.defaultFamily = DeviceFamily.zoomMs60bPlus,
  });

  @override
  DeviceFamily get supportedFamily => defaultFamily;

  @override
  bool matchesIdentityResponse(MidiMessage response) {
    final data = response.data;
    if (!SysexCodec.isIdentityReply(data)) return false;
    // data[5] == 0x52 (Zoom), data[6] == 0x6E (MS Plus Family)
    return data.length >= 10 && data[5] == manufacturerId && data[6] == familyIdByte;
  }

  @override
  DeviceFamily parseDeviceFamily(MidiMessage response) {
    final data = response.data;
    if (!matchesIdentityResponse(response)) return DeviceFamily.unknown;
    final modelCode = data[8];
    switch (modelCode) {
      case modelIdMs50gPlus:
        return DeviceFamily.zoomMs50gPlus;
      case modelIdMs200dPlus:
        return DeviceFamily.zoomMs200dPlus;
      case modelIdMs70cdrPlus:
        return DeviceFamily.zoomMs70cdrPlus;
      case modelIdMs60bPlus:
        return DeviceFamily.zoomMs60bPlus;
      default:
        return DeviceFamily.unknown;
    }
  }

  @override
  List<MidiMessage> buildInitSequence() {
    return [
      // 1. Send PC Mode Disable (0x53) to ensure the pedal exits USB lock screen mode if stuck in it
      MidiMessage.sysEx([manufacturerId, 0x00, familyIdByte, cmdPcModeDisable]),
      // 2. Send Parameter Edit Enable (0x50) to allow normal playable screen and live SysEx notifications
      MidiMessage.sysEx([manufacturerId, 0x00, familyIdByte, cmdParameterEditEnable]),
    ];
  }

  @override
  MidiMessage? buildEditorModeMessage({required bool enable}) {
    final cmd = enable ? cmdParameterEditEnable : cmdParameterEditDisable;
    return MidiMessage.sysEx([manufacturerId, 0x00, familyIdByte, cmd]);
  }

  @override
  MidiMessage buildCurrentPatchRequest() {
    // F0 52 00 6E 64 13 F7
    return MidiMessage.sysEx([manufacturerId, 0x00, familyIdByte, 0x64, cmdCurrentPatchRequest]);
  }

  @override
  MidiMessage buildPatchSlotRequest(int programNumber, {int patchesPerBank = 10}) {
    final bank = programNumber ~/ patchesPerBank;
    final prog = programNumber % patchesPerBank;
    // F0 52 00 6E 46 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> F7
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      familyIdByte,
      cmdMemoryPatchRequest,
      0x00,
      0x00,
      bank & 0x7F,
      (bank >> 7) & 0x7F,
      prog & 0x7F,
      (prog >> 7) & 0x7F,
    ]);
  }

  @override
  MidiMessage buildSlotBypassMessage({
    required int slotIndex,
    required bool isEnabled,
  }) {
    // Zoom MS Plus: paramNumber 0 = Effect Bypass (1 = Enabled, 0 = Bypassed)
    // F0 52 00 6E 64 20 00 <slot> 00 <01/00> 00 00 00 00 F7
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      familyIdByte,
      0x64,
      cmdParameterEdit,
      0x00,
      slotIndex & 0x7F,
      0x00,
      isEnabled ? 0x01 : 0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
  }

  @override
  MidiMessage buildParameterEditMessage({
    required int slotIndex,
    required int paramIndex,
    required int value,
  }) {
    // On Zoom MS Plus pedals:
    // paramNumber 0 = Bypass, paramNumber 1 = Effect ID, paramNumber >= 2 = Knobs (paramIndex + 2)
    // F0 52 00 6E 64 20 00 <slot> <paramNumber> <v0> <v1> <v2> <v3> <v4> F7
    final paramNumber = (paramIndex + 2) & 0x7F;
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      familyIdByte,
      0x64,
      cmdParameterEdit,
      0x00,
      slotIndex & 0x7F,
      paramNumber,
      value & 0x7F,
      (value >> 7) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 21) & 0x7F,
      (value >> 28) & 0x7F,
    ]);
  }

  @override
  bool isPatchDump(MidiMessage message) {
    return isCurrentPatchDump(message) || isSlotPatchDump(message);
  }

  @override
  bool isCurrentPatchDump(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 7) return false;
    if (data[1] != manufacturerId || data[2] != 0x00) {
      return false;
    }
    final isZoomFamily = data[3] == familyIdByte ||
        data[3] == 0x58 ||
        data[3] == 0x59 ||
        data[3] == 0x61;
    if (!isZoomFamily) return false;

    // Check for Current Patch V2 (64 12 01)
    final isCurrentV2 = data.length >= 7 &&
        data[4] == 0x64 &&
        data[5] == cmdCurrentPatchDump &&
        data[6] == 0x01;
    // Check for Current Patch dump opcode 0x28 (Zoom MS legacy / 0x28 dump)
    final isCurrentV1 = data[4] == cmdCurrentPatchDumpV1;

    return isCurrentV2 || isCurrentV1;
  }

  @override
  bool isSlotPatchDump(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 7) return false;
    if (data[1] != manufacturerId || data[2] != 0x00) {
      return false;
    }
    final isZoomFamily = data[3] == familyIdByte ||
        data[3] == 0x58 ||
        data[3] == 0x59 ||
        data[3] == 0x61;
    if (!isZoomFamily) return false;

    // Check for Memory Slot V2 (45 00 00)
    final isMemoryV2 = data.length >= 7 &&
        data[4] == cmdMemoryPatchDump &&
        data[5] == 0x00 &&
        data[6] == 0x00;
    // Check for legacy Zoom MS memory slot dump (08 00 00)
    final isMemoryV1 = data.length >= 8 &&
        data[4] == 0x08 &&
        data[5] == 0x00 &&
        data[6] == 0x00;

    return isMemoryV2 || isMemoryV1;
  }

  @override
  int? extractSlotIndex(MidiMessage message) {
    if (!isSlotPatchDump(message)) return null;
    final data = message.data;
    if (data[4] == cmdMemoryPatchDump && data.length >= 11) {
      final bank = data[7] | (data[8] << 7);
      final prog = data[9] | (data[10] << 7);
      return (bank * 10) + prog;
    }
    if (data[4] == 0x08 && data.length >= 8) {
      return data[7] & 0x7F;
    }
    return null;
  }

  @override
  List<MidiMessage> buildSlotSelectMessages(int slotIndex, {int patchesPerBank = 10}) {
    final bank = slotIndex ~/ patchesPerBank;
    final prog = slotIndex % patchesPerBank;
    return [
      MidiMessage.controlChange(channel: 0, controller: 0x00, value: 0x00),
      MidiMessage.controlChange(channel: 0, controller: 0x20, value: bank & 0x7F),
      MidiMessage.programChange(channel: 0, program: prog & 0x7F),
    ];
  }

  @override
  MidiMessage? buildSlotFocusMessage(int slotIndex) {
    // Zoom MS Plus: Change active displayed effect slot using 64 20 00 64 01 <slot>
    // F0 52 00 6E 64 20 00 64 01 <slotIndex> 00 00 00 00 F7
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      familyIdByte,
      0x64,
      cmdParameterEdit,
      0x00,
      0x64,
      0x01,
      slotIndex & 0x7F,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
  }

  @override
  bool isSlotBypass(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 10) return false;
    if (data[1] != manufacturerId || data[2] != 0x00) return false;

    // Zoom MS Plus: F0 52 00 6E 64 20 00 <slot> 00 <val> ... F7
    // Must be opcode 64 20 00 (unsolicited edit from pedal) with paramNumber == 0
    // data[7] is slotIndex (< 6), ensuring device-level opcodes (data[7] == 0x64) are excluded.
    return data[3] == familyIdByte &&
        data[4] == 0x64 &&
        data[5] == cmdParameterEdit &&
        data[6] == 0x00 &&
        (data[7] & 0x7F) < 6 &&
        data[8] == 0x00;
  }

  @override
  ({int slotIndex, bool isEnabled})? parseSlotBypass(MidiMessage message) {
    if (!isSlotBypass(message)) return null;
    final data = message.data;
    final slot = data[7] & 0x7F;
    final enabled = data.length > 9 ? (data[9] & 0x7F) != 0 : true;
    return (slotIndex: slot, isEnabled: enabled);
  }

  @override
  bool isSlotFocusChange(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 11) return false;
    if (data[1] != manufacturerId || data[2] != 0x00) return false;

    // Zoom MS Plus currentEffectSlotV2:
    // F0 52 00 6E 64 20 00 64 01 <newEffectSlot> ... F7
    return data[3] == familyIdByte &&
        data[4] == 0x64 &&
        data[5] == cmdParameterEdit &&
        data[6] == 0x00 &&
        data[7] == 0x64 &&
        data[8] == 0x01;
  }

  @override
  int? parseSlotFocusChange(MidiMessage message) {
    if (!isSlotFocusChange(message)) return null;
    return message.data[9] & 0x7F;
  }

  @override
  bool isSlotChange(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 13) return false;
    if (data[1] != manufacturerId || data[2] != 0x00) return false;

    // Zoom MS Plus bankAndProgramNumberV2:
    // F0 52 00 6E 64 26 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> F7
    return data[3] == familyIdByte &&
        data[4] == 0x64 &&
        data[5] == cmdBankAndProgramV2 &&
        data[6] == 0x00 &&
        data[7] == 0x00;
  }

  @override
  int? parseSlotChange(MidiMessage message, {int patchesPerBank = 10}) {
    if (!isSlotChange(message)) return null;
    final data = message.data;
    final bank = (data[8] & 0x7F) | ((data[9] & 0x7F) << 7);
    final prog = (data[10] & 0x7F) | ((data[11] & 0x7F) << 7);
    return (bank * patchesPerBank) + prog;
  }

  @override
  bool isParameterEdit(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 8) return false;
    if (data[1] != manufacturerId || data[2] != 0x00) {
      return false;
    }
    // MS Plus V2 format: F0 52 00 6E 64 20 00 <slot> <paramNumber >= 2> ...
    // Note: data[6] MUST be 0x00 (unsolicited edit from pedal).
    // data[6] == 0x01 is parameterValueAcceptedV2 ACK from the pedal and must NOT trigger a new edit!
    // data[8] >= 0x02 is a knob parameter (0 = bypass, 1 = effect ID).
    // data[7] is slotIndex (< 6), ensuring device-level opcodes (data[7] == 0x64) are excluded.
    final isV2 = data.length >= 10 &&
        data[3] == familyIdByte &&
        data[4] == 0x64 &&
        data[5] == cmdParameterEdit &&
        data[6] == 0x00 &&
        (data[7] & 0x7F) < 6 &&
        (data[8] & 0x7F) >= 2;

    // Zoom MS V1 format: F0 52 00 <family> 31 <slot> <param> <v_lsb> <v_msb> F7
    final isV1 = data[4] == cmdParameterEditV1;

    return isV2 || isV1;
  }

  @override
  ({int slotIndex, int paramIndex, int value})? parseParameterEdit(MidiMessage message) {
    if (!isParameterEdit(message)) return null;
    final data = message.data;

    if (data[4] == cmdParameterEditV1 && data.length >= 8) {
      final slot = data[5] & 0x7F;
      final param = data[6] & 0x7F;
      final val = data.length > 8
          ? ((data[7] & 0x7F) | ((data[8] & 0x7F) << 7))
          : (data[7] & 0x7F);
      return (slotIndex: slot, paramIndex: param, value: val);
    }

    if (data[4] == 0x64 && data[5] == cmdParameterEdit) {
      const offset = 7; // after F0 52 00 6E 64 20 00
      if (data.length < offset + 4) return null; // needs at least slot, param, val_lsb, and F7

      final slot = data[offset] & 0x7F;
      final rawParam = data[offset + 1] & 0x7F;
      // On Zoom MS Plus: paramIndex = paramNumber - 2
      final paramIndex = rawParam >= 2 ? rawParam - 2 : rawParam;
      int val = 0;
      int shift = 0;

      // Read remaining bytes up to trailing 0xF7
      for (int i = offset + 2; i < data.length - 1 && shift <= 28; i++) {
        val |= (data[i] & 0x7F) << shift;
        shift += 7;
      }
      return (slotIndex: slot, paramIndex: paramIndex, value: val);
    }

    return null;
  }

  @override
  Patch decodePatch(MidiMessage message) {
    final data = message.data;
    if (!isPatchDump(message)) {
      throw FormatException('Message is not a valid Zoom MS Plus patch dump SysEx: $message');
    }

    int offset;
    int? programNumber;
    if (data[4] == 0x64 && data[5] == cmdCurrentPatchDump) {
      // Current Patch V2: Header is 9 bytes
      offset = 9;
    } else if (data[4] == cmdCurrentPatchDumpV1) {
      // Current Patch V1 / 0x28 dump:
      // Try offset 5 (F0 52 00 dev 28) or offset 7
      if (data.length > 7) {
        final test5 = SysexCodec.unpack7BitTo8Bit(data, start: 5, end: data.length - 2);
        if (test5.length >= 4 && ascii.decode(test5.sublist(0, 4), allowInvalid: true) == 'PTCF') {
          offset = 5;
        } else {
          offset = 7;
        }
      } else {
        offset = 5;
      }
    } else {
      // Memory Location V2: Header is 13 bytes
      final bank = data[7] | (data[8] << 7);
      final prog = data[9] | (data[10] << 7);
      programNumber = (bank * 10) + prog;
      offset = 13;
    }

    // Unpack 7-bit payload to 8-bit PTCF buffer.
    // Strip trailing 0xF7, optional zero padding, and 5 CRC bytes.
    int end = data.length - 2; // exclude 0xF7
    if (end >= offset + 6 && data[end] == 0x00) {
      end -= 6; // strip padding + 5 CRC bytes
    } else if (end >= offset + 5) {
      end -= 5; // strip 5 CRC bytes
    }

    Uint8List unpacked = SysexCodec.unpack7BitTo8Bit(data, start: offset, end: end);
    // If unpacked doesn't start with PTCF, attempt fallback without CRC stripping
    if (unpacked.length < 4 || ascii.decode(unpacked.sublist(0, 4), allowInvalid: true) != 'PTCF') {
      final unstripped = SysexCodec.unpack7BitTo8Bit(data, start: offset, end: data.length - 1);
      if (unstripped.length >= 4 && ascii.decode(unstripped.sublist(0, 4), allowInvalid: true) == 'PTCF') {
        unpacked = unstripped;
      }
    }

    return decodePtcf(unpacked, programNumber: programNumber);
  }

  /// Strips trailing null bytes (0x00) and spaces, preserving printable ASCII characters.
  static String _cleanName(List<int> bytes) {
    if (bytes.isEmpty) return '';
    int end = bytes.length;
    while (end > 0 && (bytes[end - 1] == 0x00 || bytes[end - 1] == 0x20)) {
      end--;
    }
    if (end <= 0) return '';
    final chars = <int>[];
    for (int i = 0; i < end; i++) {
      final b = bytes[i];
      if (b >= 32 && b <= 126) {
        chars.add(b);
      } else if (b == 0) {
        chars.add(32);
      }
    }
    return String.fromCharCodes(chars).trim();
  }

  /// Decodes raw 8-bit PTCF binary payload into a domain [Patch].
  Patch decodePtcf(Uint8List ptcf, {int? programNumber}) {
    if (ptcf.length < 8) {
      throw const FormatException('PTCF data buffer too short.');
    }
    final magic = ascii.decode(ptcf.sublist(0, 4));
    if (magic != 'PTCF') {
      throw FormatException('Invalid magic header: expected "PTCF", got "$magic"');
    }

    final byteData = ByteData.sublistView(ptcf);
    final ptcfLength = byteData.getUint32(4, Endian.little);
    final version = byteData.getUint32(8, Endian.little);
    final numEffects = byteData.getUint32(12, Endian.little);
    final target = byteData.getUint32(16, Endian.little);

    // Short name at offset 26 (10 bytes)
    final shortName = ptcf.length >= 36
        ? _cleanName(ptcf.sublist(26, 36))
        : 'Patch';

    // Effect IDs table
    final effectIds = <int>[];
    int cursor = 36;
    for (int i = 0; i < numEffects && cursor + 4 <= ptcf.length; i++) {
      effectIds.add(byteData.getUint32(cursor, Endian.little));
      cursor += 4;
    }

    // Parse subchunks: TXJ1, TXE1, EDTB, PRM2, NAME
    String patchName = shortName.isNotEmpty ? shortName : 'Patch';
    String description = '';
    double tempo = 120.0;
    int activeEffectSlot = 0;
    final List<EffectSlot> slots = [];

    final maxScanLength = (ptcfLength > 8 && ptcfLength <= ptcf.length)
        ? ptcfLength
        : ptcf.length;

    while (cursor + 8 <= maxScanLength) {
      final chunkId = ascii.decode(ptcf.sublist(cursor, cursor + 4), allowInvalid: true);
      final chunkSize = byteData.getUint32(cursor + 4, Endian.little);
      cursor += 8;

      if (cursor + chunkSize > ptcf.length) break;
      final chunkData = ptcf.sublist(cursor, cursor + chunkSize);
      cursor += chunkSize;

      switch (chunkId) {
        case 'NAME':
          final nameStr = _cleanName(chunkData);
          if (nameStr.isNotEmpty) patchName = nameStr;
          break;

        case 'TXE1':
          description = _cleanName(chunkData);
          break;

        case 'PRM2':
          if (chunkData.length >= 2) {
            final t1 = chunkData[chunkData.length - 2];
            final t2 = chunkData[chunkData.length - 1];
            final rawTempo = ((t1 & 0xF0) >> 4) | ((t2 & 0x0F) << 4);
            if (rawTempo > 0) tempo = rawTempo.toDouble();
          }
          if (chunkData.length > 10) {
            activeEffectSlot = (chunkData[10] & 0xE0) >> 5;
          }
          break;

        case 'EDTB':
          // Process each 24-byte effect block
          for (int slotIdx = 0; slotIdx < numEffects; slotIdx++) {
            final blockStart = slotIdx * edtbEffectBlockSize;
            if (blockStart + edtbEffectBlockSize > chunkData.length) break;

            final rawBlock = chunkData.sublist(blockStart, blockStart + edtbEffectBlockSize);
            // Invert byte order for big-endian bit extraction matching Zoom specification
            final reversed = Uint8List.fromList(rawBlock.reversed.toList());

            int bitpos = 191; // 24 * 8 - 1
            final isEnabled = SysexCodec.getBits(reversed, bitpos, bitpos) == 1;
            bitpos -= 1;

            final dspId = SysexCodec.getBits(reversed, bitpos - 28, bitpos);
            bitpos -= 29;

            final rawValues = <double>[];

            // 5 parameters of 12 bits
            for (int p = 0; p < 5 && bitpos - 11 >= 0; p++) {
              final val = SysexCodec.getBits(reversed, bitpos - 11, bitpos);
              bitpos -= 12;
              rawValues.add(val.toDouble());
            }

            // 3 parameters of 8 bits
            for (int p = 5; p < 8 && bitpos - 7 >= 0; p++) {
              final val = SysexCodec.getBits(reversed, bitpos - 7, bitpos);
              bitpos -= 8;
              rawValues.add(val.toDouble());
            }

            // 4 parameters of 12 bits
            for (int p = 8; p < 12 && bitpos - 11 >= 0; p++) {
              final val = SysexCodec.getBits(reversed, bitpos - 11, bitpos);
              bitpos -= 12;
              rawValues.add(val.toDouble());
            }

            final hexId = '0x${dspId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
            final family = _resolveFamilyFromTarget(target);
            final effectDef = EffectCatalogRegistry.getDefinition(family, hexId);

            final parameters = <ParameterValue>[];
            for (int p = 0; p < rawValues.length; p++) {
              final val = rawValues[p];
              final ParameterDescriptor desc;
              if (p < effectDef.parameters.length) {
                desc = effectDef.parameters[p];
              } else {
                final is12Bit = p < 5 || p >= 8;
                desc = ParameterDescriptor(
                  id: 'param_$p',
                  name: 'Param ${p + 1}',
                  min: 0,
                  max: is12Bit ? 4095 : 255,
                  defaultValue: 0,
                );
              }
              parameters.add(ParameterValue(
                descriptor: desc,
                currentValue: val,
              ));
            }

            final effectName = (dspId != 0 && !effectDef.name.startsWith('Unknown'))
                ? effectDef.name
                : _lookupEffectName(dspId);

            slots.add(EffectSlot(
              slotIndex: slotIdx,
              effectId: hexId,
              effectName: effectName,
              isEnabled: isEnabled,
              parameters: parameters,
            ));
          }
          break;
      }
    }

    // Fallback scan for 'NAME' chunk marker if not resolved during chunk loop
    if (patchName == shortName || patchName.isEmpty) {
      for (int i = 36; i <= ptcf.length - 12; i++) {
        if (ptcf[i] == 0x4E && ptcf[i + 1] == 0x41 && ptcf[i + 2] == 0x4D && ptcf[i + 3] == 0x45) {
          final size = byteData.getUint32(i + 4, Endian.little);
          if (size > 0 && size <= 64 && i + 8 + size <= ptcf.length) {
            final fallbackName = _cleanName(ptcf.sublist(i + 8, i + 8 + size));
            if (fallbackName.isNotEmpty) {
              patchName = fallbackName;
              break;
            }
          }
        }
      }
    }

    return Patch(
      id: programNumber != null ? 'zoom_slot_$programNumber' : 'zoom_active_patch',
      name: patchName,
      deviceFamily: _resolveFamilyFromTarget(target),
      programNumber: programNumber,
      slots: slots,
      metadata: {
        'tempo': tempo,
        'activeEffectSlot': activeEffectSlot,
        'target': target,
        'version': version,
        'shortName': shortName,
        'description': description,
      },
    );
  }

  @override
  MidiMessage buildSavePatchToSlotMessage(
    Patch patch,
    int programNumber, {
    int patchesPerBank = 10,
  }) {
    final ptcfData = encodePtcf(patch);
    final packed7Bit = SysexCodec.pack8BitTo7Bit(ptcfData);
    final crc = SysexCodec.calculateZoom7BitCrc(ptcfData);

    final patchLength = ptcfData.length;
    final lenLsb = patchLength & 0x7F;
    final lenMsb = (patchLength >> 7) & 0x7F;

    final bank = (programNumber ~/ patchesPerBank).clamp(0, 127);
    final prog = (programNumber % patchesPerBank).clamp(0, 127);

    // F0 52 00 6E 45 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> <len_lsb> <len_msb> <data...> <CRC> 00 F7
    final List<int> payload = [
      manufacturerId,
      0x00,
      familyIdByte,
      cmdMemoryPatchDump,
      0x00,
      0x00,
      bank & 0x7F,
      (bank >> 7) & 0x7F,
      prog & 0x7F,
      (prog >> 7) & 0x7F,
      lenLsb,
      lenMsb,
      ...packed7Bit,
      ...crc,
      0x00, // zero padding
    ];

    return MidiMessage.sysEx(payload);
  }

  @override
  MidiMessage encodePatch(Patch patch, {int? programNumber}) {
    if (programNumber != null) {
      return buildSavePatchToSlotMessage(patch, programNumber);
    }
    final ptcfData = encodePtcf(patch);
    final packed7Bit = SysexCodec.pack8BitTo7Bit(ptcfData);
    final crc = SysexCodec.calculateZoom7BitCrc(ptcfData);

    final patchLength = ptcfData.length;
    final lenLsb = patchLength & 0x7F;
    final lenMsb = (patchLength >> 7) & 0x7F;

    final List<int> payload = [
      manufacturerId,
      0x00,
      familyIdByte,
      0x64,
      cmdCurrentPatchDump,
      0x01,
      lenLsb,
      lenMsb,
      ...packed7Bit,
      ...crc,
      0x00, // zero padding
    ];

    return MidiMessage.sysEx(payload);
  }

  /// Encodes a domain [Patch] into an 8-bit PTCF binary payload.
  Uint8List encodePtcf(Patch patch) {
    final numEffects = patch.slots.isEmpty ? defaultMaxSlots : patch.slots.length;
    final target = (patch.metadata['target'] as int?) ??
        (patch.deviceFamily == DeviceFamily.zoomMs50gPlus
            ? ptcfTargetMs50gPlus
            : ptcfTargetMs60bPlus);
    final version = (patch.metadata['version'] as int?) ?? 1;

    // Build EDTB block (numEffects * 24 bytes)
    final edtbBytes = Uint8List(numEffects * edtbEffectBlockSize);
    for (int slotIdx = 0; slotIdx < numEffects; slotIdx++) {
      final slot = slotIdx < patch.slots.length ? patch.slots[slotIdx] : null;
      final reversed = Uint8List(edtbEffectBlockSize);

      int bitpos = 191;
      final isEnabled = slot?.isEnabled ?? true;
      SysexCodec.setBits(reversed, bitpos, bitpos, isEnabled ? 1 : 0);
      bitpos -= 1;

      final dspId = slot != null ? _parseEffectId(slot.effectId) : 0;
      SysexCodec.setBits(reversed, bitpos - 28, bitpos, dspId);
      bitpos -= 29;

      if (slot != null) {
        for (int p = 0; p < 5 && bitpos - 11 >= 0; p++) {
          final val = p < slot.parameters.length ? slot.parameters[p].currentValue.round() : 0;
          SysexCodec.setBits(reversed, bitpos - 11, bitpos, val);
          bitpos -= 12;
        }
        for (int p = 5; p < 8 && bitpos - 7 >= 0; p++) {
          final val = p < slot.parameters.length ? slot.parameters[p].currentValue.round() : 0;
          SysexCodec.setBits(reversed, bitpos - 7, bitpos, val);
          bitpos -= 8;
        }
        for (int p = 8; p < 12 && bitpos - 11 >= 0; p++) {
          final val = p < slot.parameters.length ? slot.parameters[p].currentValue.round() : 0;
          SysexCodec.setBits(reversed, bitpos - 11, bitpos, val);
          bitpos -= 12;
        }
      }

      final forwardBlock = Uint8List.fromList(reversed.reversed.toList());
      edtbBytes.setRange(
        slotIdx * edtbEffectBlockSize,
        (slotIdx + 1) * edtbEffectBlockSize,
        forwardBlock,
      );
    }

    // Build PRM2 block (32 bytes)
    final prm2Bytes = Uint8List(32);
    final tempo = ((patch.metadata['tempo'] as num?)?.round()) ?? 120;
    prm2Bytes[prm2Bytes.length - 2] = (tempo & 0x0F) << 4;
    prm2Bytes[prm2Bytes.length - 1] = (tempo >> 4) & 0x0F;
    final activeSlot = (patch.metadata['activeEffectSlot'] as int?) ?? 0;
    prm2Bytes[10] = (activeSlot & 0x07) << 5;

    // Build NAME chunk (32 bytes: 28 ascii + 4 nulls)
    final nameBytes = Uint8List(msPlusNameLength);
    final rawName = patch.name.padRight(28, ' ').substring(0, 28);
    nameBytes.setRange(0, 28, ascii.encode(rawName));

    // Calculate total PTCF chunk length
    // Header (4 PTCF + 4 len) + toplevel: 4 (ver) + 4 (numEff) + 4 (tgt) + 6 (unk) + 10 (shortName) + 4*numEffects
    final topLevelDataSize = 4 + 4 + 4 + 6 + 10 + (numEffects * 4);
    final edtbChunkSize = 8 + edtbBytes.length;
    final prm2ChunkSize = 8 + prm2Bytes.length;
    final nameChunkSize = 8 + nameBytes.length;
    final totalSize = 8 + topLevelDataSize + edtbChunkSize + prm2ChunkSize + nameChunkSize;

    final output = Uint8List(totalSize);
    final bd = ByteData.sublistView(output);

    output.setRange(0, 4, ascii.encode('PTCF'));
    bd.setUint32(4, totalSize, Endian.little);
    bd.setUint32(8, version, Endian.little);
    bd.setUint32(12, numEffects, Endian.little);
    bd.setUint32(16, target, Endian.little);
    // 6 bytes unknown (offset 20..25) left as 0
    final shortNameStr = patch.name.padRight(10, ' ').substring(0, 10);
    output.setRange(26, 36, ascii.encode(shortNameStr));

    int offset = 36;
    for (int i = 0; i < numEffects; i++) {
      final slot = i < patch.slots.length ? patch.slots[i] : null;
      final id = slot != null ? _parseEffectId(slot.effectId) : 0;
      bd.setUint32(offset, id, Endian.little);
      offset += 4;
    }

    // Write EDTB
    output.setRange(offset, offset + 4, ascii.encode('EDTB'));
    bd.setUint32(offset + 4, edtbBytes.length, Endian.little);
    offset += 8;
    output.setRange(offset, offset + edtbBytes.length, edtbBytes);
    offset += edtbBytes.length;

    // Write PRM2
    output.setRange(offset, offset + 4, ascii.encode('PRM2'));
    bd.setUint32(offset + 4, prm2Bytes.length, Endian.little);
    offset += 8;
    output.setRange(offset, offset + prm2Bytes.length, prm2Bytes);
    offset += prm2Bytes.length;

    // Write NAME
    output.setRange(offset, offset + 4, ascii.encode('NAME'));
    bd.setUint32(offset + 4, nameBytes.length, Endian.little);
    offset += 8;
    output.setRange(offset, offset + nameBytes.length, nameBytes);

    return output;
  }

  DeviceFamily _resolveFamilyFromTarget(int target) {
    if ((target & ptcfTargetMs50gPlus) != 0) return DeviceFamily.zoomMs50gPlus;
    if ((target & ptcfTargetMs60bPlus) != 0) return DeviceFamily.zoomMs60bPlus;
    return defaultFamily;
  }

  int _parseEffectId(String idStr) {
    if (idStr.startsWith('0x') || idStr.startsWith('0X')) {
      return int.tryParse(idStr.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(idStr) ?? 0;
  }

  String _lookupEffectName(int dspId) {
    if (dspId == 0) return 'Bypass';
    final hexId = '0x${dspId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    final def = EffectCatalogRegistry.getDefinition(defaultFamily, hexId);
    if (!def.name.startsWith('Unknown')) {
      return def.name;
    }
    switch (dspId) {
      case 0x01000010:
        return 'DYN Comp';
      case 0x01000020:
        return 'M Comp';
      case 0x02000010:
        return 'Bass Preamp';
      case 0x03000010:
        return 'Bass Drive';
      case 0x06000010:
        return 'Bass Chorus';
      case 0x08000010:
        return 'Delay';
      case 0x09000010:
        return 'Hall Reverb';
      default:
        return 'Effect 0x${dspId.toRadixString(16).toUpperCase()}';
    }
  }
}
