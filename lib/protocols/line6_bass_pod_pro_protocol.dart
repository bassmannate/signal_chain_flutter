import 'dart:typed_data';

import '../core/midi/midi_message.dart';
import '../models/device_family.dart';
import '../models/effect_slot.dart';
import '../models/parameter_descriptor.dart';
import '../models/patch.dart';
import 'catalogs/line6_bass_pod_pro_catalog.dart';
import 'device_protocol.dart';
import 'sysex_codec.dart';

/// Protocol implementation for the Line 6 Bass POD Pro rackmount processor.
///
/// Verified against hardware SysEx captures (firmware 1.40) and
/// `Bass POD Pro Sysex - English.pdf`:
/// - Universal Identity Reply Manufacturer ID: `00 01 0C` (USB Vendor `0x0E41`)
/// - Universal Identity Family Code (LSB first): `02 00` (`0x0002`)
/// - Device SysEx Header: `F0 00 01 0C 02` (`deviceFamilyByte = 0x02`)
/// - Requests (`opcode = 0x00`):
///   - Program Dump Request: `F0 00 01 0C 02 00 00 <prog> F7` (`0x00..0x23`)
///   - Edit Buffer Request: `F0 00 01 0C 02 00 01 F7`
///   - All Programs Request: `F0 00 01 0C 02 00 02 F7`
/// - Dumps (`opcode = 0x01`, `version = 0x01`, 80 bytes packed as 160 MSB-first nibbles):
///   - Program Dump: `F0 00 01 0C 02 01 00 <prog> <ver> <160 nibbles> F7` (170 bytes)
///   - Edit Buffer Dump: `F0 00 01 0C 02 01 01 <ver> <160 nibbles> F7` (169 bytes)
/// - Live Front-Panel Editing: Standard MIDI Control Changes on the POD's MIDI channel.
class Line6BassPodProProtocol extends DeviceProtocol {
  /// Line 6 3-byte SysEx Manufacturer ID.
  static const List<int> manufacturerId = [0x00, 0x01, 0x0C];

  /// Universal SysEx Identity family code (LSB first: 0x0002 = Bass POD / Pro).
  static const List<int> identityFamilyCode = [0x02, 0x00];

  /// Line 6 SysEx family byte for Bass POD / Bass POD Pro.
  static const int deviceFamilyByte = 0x02;

  /// SysEx opcodes (byte 5 after `F0`).
  static const int opcodeRequest = 0x00;
  static const int opcodeDump = 0x01;

  /// SysEx dump types (byte 6 after `F0`).
  static const int dumpTypeProgram = 0x00;
  static const int dumpTypeEditBuffer = 0x01;
  static const int dumpTypeAllPrograms = 0x02;

  /// Bass POD Pro data format version byte.
  static const int dumpVersion = 0x01;

  /// Total number of persistent program slots (1A..9D).
  static const int totalProgramSlots = 36;

  /// Unpacked program / edit buffer size in bytes.
  static const int editBufferSize = 80;

  /// Nibble-encoded single-program payload size in bytes.
  static const int nibblePayloadSize = editBufferSize * 2;

  /// Verified MIDI Control Change (CC) numbers from hardware capture spec.
  static const int ccEffectTweak = 1;
  static const int ccWahPedal = 4;
  static const int ccMasterVolume = 7;
  static const int ccAmpModel = 12;
  static const int ccDrive = 13;
  static const int ccBass = 14;
  static const int ccMid = 15;
  static const int ccTreble = 16;
  static const int ccChannelVolume = 17;
  static const int ccCompressor = 18;
  static const int ccEffectSelect = 19;
  static const int ccFxLoCut = 21;
  static const int ccNoiseGate = 22;
  static const int ccEffectOnOff = 60;
  static const int ccApplyFxToDi = 64;
  static const int ccCabinetModel = 71;
  static const int ccAirLevel = 72;

  static const int _cabBypassIndex = 10;
  static const int _fxBypassIndex = 10;

  static const List<String> ampModels = Line6BassPodProCatalog.ampModels;
  static const List<String> cabModels = Line6BassPodProCatalog.cabModels;
  static const List<String> effectTypes = Line6BassPodProCatalog.effectTypes;

  /// MIDI channel 0-15 (Channel 1 = 0).
  final int midiChannel;

  const Line6BassPodProProtocol({
    this.midiChannel = 0,
  });

  @override
  DeviceFamily get supportedFamily => DeviceFamily.line6BassPodPro;

  @override
  bool matchesIdentityResponse(MidiMessage response) {
    if (!SysexCodec.isIdentityReply(response.data)) return false;
    final data = response.data;
    if (data.length < 10) return false;
    return data[5] == manufacturerId[0] &&
        data[6] == manufacturerId[1] &&
        data[7] == manufacturerId[2] &&
        data[8] == identityFamilyCode[0] &&
        data[9] == identityFamilyCode[1];
  }

  @override
  DeviceFamily parseDeviceFamily(MidiMessage response) {
    if (!matchesIdentityResponse(response)) {
      throw FormatException('Not a valid Line 6 Bass POD Pro identity response: $response');
    }
    return DeviceFamily.line6BassPodPro;
  }

  @override
  List<MidiMessage> buildInitSequence() {
    return [buildCurrentPatchRequest()];
  }

  @override
  MidiMessage? buildEditorModeMessage({required bool enable}) {
    // Bass POD Pro accepts live MIDI CCs and SysEx requests directly without an editor mode toggle.
    return null;
  }

  @override
  MidiMessage buildCurrentPatchRequest() {
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      opcodeRequest,
      dumpTypeEditBuffer,
    ]);
  }

  @override
  MidiMessage buildPatchSlotRequest(int programNumber) {
    return buildProgramDumpRequest(programNumber);
  }

  /// Requests a specific program slot (`0..35` corresponding to 1A..9D).
  MidiMessage buildProgramDumpRequest(int programNumber) {
    final clamped = programNumber.clamp(0, totalProgramSlots - 1);
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      opcodeRequest,
      dumpTypeProgram,
      clamped,
    ]);
  }

  /// Requests all 36 internal programs (`0..35`) as a bulk SysEx dump.
  MidiMessage buildAllProgramsDumpRequest() {
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      opcodeRequest,
      dumpTypeAllPrograms,
    ]);
  }

  @override
  MidiMessage buildParameterEditMessage({
    required int slotIndex,
    required int paramIndex,
    required int value,
  }) {
    final cc = _mapSlotParamToCc(slotIndex, paramIndex);
    return MidiMessage.controlChange(
      channel: midiChannel,
      controller: cc,
      value: value.clamp(0, 127),
    );
  }

  @override
  MidiMessage? buildSlotBypassMessage({
    required int slotIndex,
    required bool isEnabled,
  }) {
    if (slotIndex == 3) {
      return MidiMessage.controlChange(
        channel: midiChannel,
        controller: ccEffectOnOff,
        value: isEnabled ? 127 : 0,
      );
    }
    return null;
  }

  @override
  bool isPatchDump(MidiMessage message) {
    return isCurrentPatchDump(message) || isSlotPatchDump(message);
  }

  bool _hasLine6Header(MidiMessage message, {required int opcode, required int dumpType}) {
    if (!message.isSysEx) return false;
    final data = message.data;
    return data.length >= 9 &&
        data[1] == manufacturerId[0] &&
        data[2] == manufacturerId[1] &&
        data[3] == manufacturerId[2] &&
        data[4] == deviceFamilyByte &&
        data[5] == opcode &&
        data[6] == dumpType;
  }

  @override
  bool isCurrentPatchDump(MidiMessage message) {
    return _hasLine6Header(
          message,
          opcode: opcodeDump,
          dumpType: dumpTypeEditBuffer,
        ) &&
        message.data.length >= 8 + editBufferSize + 1;
  }

  @override
  bool isSlotPatchDump(MidiMessage message) {
    return _hasLine6Header(
          message,
          opcode: opcodeDump,
          dumpType: dumpTypeProgram,
        ) &&
        message.data.length >= 9 + editBufferSize + 1;
  }

  @override
  int? extractSlotIndex(MidiMessage message) {
    if (!isSlotPatchDump(message)) return null;
    return message.data[7] & 0x7F;
  }

  @override
  List<MidiMessage> buildSlotSelectMessages(int slotIndex) {
    final clamped = slotIndex.clamp(0, totalProgramSlots - 1);
    // Bass POD Pro reserves Program Change 0 for Manual mode; 1..36 select 1A..9D.
    return [
      MidiMessage.programChange(
        channel: midiChannel,
        program: (clamped + 1) & 0x7F,
      ),
    ];
  }

  @override
  bool isParameterEdit(MidiMessage message) {
    if (!message.isControlChange) return false;
    if ((message.data[0] & 0x0F) != midiChannel) return false;
    return _supportedCcList.contains(message.data[1]);
  }

  @override
  ({int slotIndex, int paramIndex, int value})? parseParameterEdit(MidiMessage message) {
    if (!isParameterEdit(message)) return null;
    final cc = message.data[1];
    final val = message.data[2];
    final mapping = _mapCcToSlotParam(cc);
    if (mapping == null) return null;
    return (slotIndex: mapping.slot, paramIndex: mapping.param, value: val);
  }

  @override
  Patch decodePatch(MidiMessage message) {
    if (!isPatchDump(message)) {
      throw FormatException('Message is not a valid Line 6 Bass POD Pro SysEx dump: $message');
    }
    final data = message.data;
    final isProgramDump = data[6] == dumpTypeProgram;
    final int? programNumber = isProgramDump ? (data[7] & 0x7F) : null;
    final int payloadStart = isProgramDump ? 9 : 8; // Skip version byte (`data[8]` or `data[7]`)
    final payload = data.sublist(payloadStart, data.length - 1);

    final Uint8List buffer;
    if (payload.length >= nibblePayloadSize) {
      buffer = SysexCodec.unpackNibbles(
        payload.sublist(0, nibblePayloadSize),
        msbFirst: true,
      );
    } else if (payload.length >= editBufferSize) {
      buffer = Uint8List.fromList(payload.sublist(0, editBufferSize));
    } else {
      throw FormatException(
        'Line 6 Bass POD Pro dump payload too short: ${payload.length} bytes',
      );
    }

    return decodeEditBuffer(buffer, programNumber: programNumber);
  }

  /// Decodes an unpacked 80-byte Bass POD Pro program buffer into a [Patch].
  Patch decodeEditBuffer(Uint8List buffer, {int? programNumber}) {
    if (buffer.length < editBufferSize) {
      throw ArgumentError('Buffer too short for Bass POD Pro: ${buffer.length} < $editBufferSize');
    }

    // Patch name is at bytes 64..79 (16-char space-padded ASCII).
    final nameBytes = buffer.sublist(64, 80);
    final rawName = String.fromCharCodes(
      nameBytes.map((b) => (b >= 0x20 && b <= 0x7E) ? b : 0x20),
    ).trimRight();
    final patchName = rawName.isEmpty ? 'Untitled' : rawName;

    // Slot 0: Amp Model & Tone Stack
    final ampModelIdx = (buffer[3] & 0x0F).clamp(0, ampModels.length - 1);
    final drive = _read6BitScaled(buffer, 4);
    final bass = _read6BitScaled(buffer, 6);
    final mid = _read6BitScaled(buffer, 7);
    final treble = _read6BitScaled(buffer, 8);
    final chanVol = _read6BitScaled(buffer, 10);

    final ampSlot = EffectSlot(
      slotIndex: 0,
      effectId: 'line6_amp_$ampModelIdx',
      effectName: ampModels[ampModelIdx],
      isEnabled: true,
      parameters: [
        ParameterValue(
          descriptor: ParameterDescriptor(
            id: 'amp_model',
            name: 'Amp Model',
            min: 0,
            max: ampModels.length - 1,
            defaultValue: 0,
            labels: ampModels,
          ),
          currentValue: ampModelIdx.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'drive',
            name: 'Drive',
            min: 0,
            max: 126,
            defaultValue: 64,
            step: 2,
          ),
          currentValue: drive.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'bass',
            name: 'Bass',
            min: 0,
            max: 126,
            defaultValue: 64,
            step: 2,
          ),
          currentValue: bass.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'mid',
            name: 'Mid',
            min: 0,
            max: 126,
            defaultValue: 64,
            step: 2,
          ),
          currentValue: mid.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'treble',
            name: 'Treble',
            min: 0,
            max: 126,
            defaultValue: 64,
            step: 2,
          ),
          currentValue: treble.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'channel_volume',
            name: 'Channel Volume',
            min: 0,
            max: 126,
            defaultValue: 100,
            step: 2,
          ),
          currentValue: chanVol.toDouble(),
        ),
      ],
    );

    // Slot 1: Cabinet & A.I.R. Level
    final cabModelIdx = (buffer[31] & 0x0F).clamp(0, cabModels.length - 1);
    final airLevel = _read6BitScaled(buffer, 32);

    final cabSlot = EffectSlot(
      slotIndex: 1,
      effectId: 'line6_cab_$cabModelIdx',
      effectName: cabModels[cabModelIdx],
      isEnabled: cabModelIdx != _cabBypassIndex,
      parameters: [
        ParameterValue(
          descriptor: ParameterDescriptor(
            id: 'cab_model',
            name: 'Cabinet',
            min: 0,
            max: cabModels.length - 1,
            defaultValue: 0,
            labels: cabModels,
          ),
          currentValue: cabModelIdx.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'air_level',
            name: 'A.I.R. Level',
            min: 0,
            max: 126,
            defaultValue: 0,
            step: 2,
          ),
          currentValue: airLevel.toDouble(),
        ),
      ],
    );

    // Slot 2: Compressor & Noise Gate
    final compressVal = _read6BitScaled(buffer, 11);
    final noiseGateBit = buffer[0] & 0x01;

    final compSlot = EffectSlot(
      slotIndex: 2,
      effectId: 'line6_comp',
      effectName: 'Compressor',
      isEnabled: compressVal > 0 || noiseGateBit == 1,
      parameters: [
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'compressor',
            name: 'Compress',
            min: 0,
            max: 126,
            defaultValue: 0,
            step: 2,
          ),
          currentValue: compressVal.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'noise_gate',
            name: 'Noise Gate',
            min: 0,
            max: 1,
            defaultValue: 0,
            labels: ['Off', 'On'],
          ),
          currentValue: noiseGateBit.toDouble(),
        ),
      ],
    );

    // Slot 3: Effect / Modulation / Drive
    final fxTypeIdx = (buffer[49] & 0x0F).clamp(0, effectTypes.length - 1);
    final fxTweak = _read6BitScaled(buffer, 50);
    final fxLoCut = _read6BitScaled(buffer, 51);
    final fxOnBit = buffer[52] & 0x01;

    final fxSlot = EffectSlot(
      slotIndex: 3,
      effectId: 'line6_fx_$fxTypeIdx',
      effectName: effectTypes[fxTypeIdx],
      isEnabled: fxTypeIdx != _fxBypassIndex && fxOnBit == 1,
      parameters: [
        ParameterValue(
          descriptor: ParameterDescriptor(
            id: 'fx_select',
            name: 'Effect Type',
            min: 0,
            max: effectTypes.length - 1,
            defaultValue: _fxBypassIndex.toDouble(),
            labels: effectTypes,
          ),
          currentValue: fxTypeIdx.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'fx_tweak',
            name: 'Effect Tweak',
            min: 0,
            max: 126,
            defaultValue: 0,
            step: 2,
          ),
          currentValue: fxTweak.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'fx_lo_cut',
            name: 'FX Lo Cut',
            min: 0,
            max: 126,
            defaultValue: 0,
            step: 2,
          ),
          currentValue: fxLoCut.toDouble(),
        ),
      ],
    );

    return Patch(
      id: programNumber != null ? 'line6_slot_$programNumber' : 'line6_edit_buffer',
      name: patchName,
      deviceFamily: DeviceFamily.line6BassPodPro,
      programNumber: programNumber,
      slots: [ampSlot, cabSlot, compSlot, fxSlot],
    );
  }

  @override
  MidiMessage buildSavePatchToSlotMessage(
    Patch patch,
    int programNumber, {
    bool useNibbles = true,
  }) {
    final clampedSlot = programNumber.clamp(0, totalProgramSlots - 1);
    final buffer = encodeEditBuffer(patch);
    final payloadData = useNibbles
        ? SysexCodec.packNibbles(buffer, msbFirst: true)
        : buffer;
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      opcodeDump,
      dumpTypeProgram,
      clampedSlot,
      dumpVersion,
      ...payloadData,
    ]);
  }

  @override
  MidiMessage encodePatch(
    Patch patch, {
    bool useNibbles = true,
    int? programNumber,
  }) {
    if (programNumber != null) {
      return buildSavePatchToSlotMessage(
        patch,
        programNumber,
        useNibbles: useNibbles,
      );
    }
    final buffer = encodeEditBuffer(patch);
    final payloadData = useNibbles
        ? SysexCodec.packNibbles(buffer, msbFirst: true)
        : buffer;
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      opcodeDump,
      dumpTypeEditBuffer,
      dumpVersion,
      ...payloadData,
    ]);
  }

  /// Packs a [Patch] into the 80-byte Bass POD Pro program buffer.
  Uint8List encodeEditBuffer(Patch patch) {
    final buffer = Uint8List(editBufferSize);

    // Slot 0: Amp
    final ampSlot = _findSlot(patch, 0);
    if (ampSlot != null) {
      final ampModelIdx = (_findParamValue(ampSlot, const ['amp_model'])?.round() ??
              _parseIndexedEffectId(ampSlot.effectId, 'line6_amp_') ??
              0)
          .clamp(0, ampModels.length - 1);
      buffer[3] = (buffer[3] & 0xF0) | (ampModelIdx & 0x0F);

      final drive = _findParamValue(ampSlot, const ['drive'], fallbackIndex: 1) ?? 64;
      final bass = _findParamValue(ampSlot, const ['bass'], fallbackIndex: 2) ?? 64;
      final mid = _findParamValue(ampSlot, const ['mid'], fallbackIndex: 3) ?? 64;
      final treble = _findParamValue(ampSlot, const ['treble'], fallbackIndex: 4) ?? 64;
      final chanVol = _findParamValue(ampSlot, const ['channel_volume'], fallbackIndex: 5) ?? 100;

      _write6BitScaled(buffer, 4, drive);
      _write6BitScaled(buffer, 6, bass);
      _write6BitScaled(buffer, 7, mid);
      _write6BitScaled(buffer, 8, treble);
      _write6BitScaled(buffer, 10, chanVol);
    }

    // Slot 1: Cabinet
    final cabSlot = _findSlot(patch, 1);
    if (cabSlot != null) {
      final cabModelIdx = (_findParamValue(cabSlot, const ['cab_model', 'cabinet_model'])?.round() ??
              _parseIndexedEffectId(cabSlot.effectId, 'line6_cab_') ??
              0)
          .clamp(0, cabModels.length - 1);
      buffer[31] = (buffer[31] & 0xF0) | (cabModelIdx & 0x0F);

      final airLevel = _findParamValue(cabSlot, const ['air_level'], fallbackIndex: 1) ?? 0;
      _write6BitScaled(buffer, 32, airLevel);
    }

    // Slot 2: Compressor & Noise Gate
    final compSlot = _findSlot(patch, 2);
    if (compSlot != null) {
      final compressVal = _findParamValue(
            compSlot,
            const ['compressor', 'threshold'],
            fallbackIndex: 0,
          ) ??
          0;
      final noiseGate = _findParamValue(
            compSlot,
            const ['noise_gate', 'enabled'],
            fallbackIndex: 1,
          ) ??
          0;
      _write6BitScaled(buffer, 11, compressVal);
      buffer[0] = (buffer[0] & 0xFE) | (noiseGate >= 0.5 ? 1 : 0);
    }

    // Slot 3: Effect
    final fxSlot = _findSlot(patch, 3);
    if (fxSlot != null) {
      final fxTypeIdx = (_findParamValue(fxSlot, const ['fx_select', 'fx_type'])?.round() ??
              _parseIndexedEffectId(fxSlot.effectId, 'line6_fx_') ??
              _fxBypassIndex)
          .clamp(0, effectTypes.length - 1);
      buffer[49] = (buffer[49] & 0xF0) | (fxTypeIdx & 0x0F);

      final fxTweak = _findParamValue(fxSlot, const ['fx_tweak', 'tweak'], fallbackIndex: 1) ?? 0;
      final fxLoCut = _findParamValue(fxSlot, const ['fx_lo_cut'], fallbackIndex: 2) ?? 0;
      _write6BitScaled(buffer, 50, fxTweak);
      _write6BitScaled(buffer, 51, fxLoCut);

      final isFxActive = fxSlot.isEnabled && fxTypeIdx != _fxBypassIndex;
      buffer[52] = (buffer[52] & 0xFE) | (isFxActive ? 1 : 0);
    }

    // Patch name (bytes 64..79, ASCII padded with spaces 0x20)
    final name = patch.name;
    for (int i = 0; i < 16; i++) {
      buffer[64 + i] = i < name.length ? (name.codeUnitAt(i) & 0x7F) : 0x20;
    }

    return buffer;
  }

  static int _read6BitScaled(Uint8List buffer, int offset) {
    return (buffer[offset] & 0x3F) * 2;
  }

  static void _write6BitScaled(Uint8List buffer, int offset, double value) {
    final stored = (value.round().clamp(0, 127) / 2).round().clamp(0, 63);
    buffer[offset] = (buffer[offset] & 0xC0) | stored;
  }

  static EffectSlot? _findSlot(Patch patch, int slotIndex) {
    for (final slot in patch.slots) {
      if (slot.slotIndex == slotIndex) return slot;
    }
    return null;
  }

  static double? _findParamValue(
    EffectSlot slot,
    List<String> candidateIds, {
    int? fallbackIndex,
  }) {
    for (final param in slot.parameters) {
      if (candidateIds.contains(param.descriptor.id)) {
        return param.currentValue;
      }
    }
    if (fallbackIndex != null &&
        fallbackIndex >= 0 &&
        fallbackIndex < slot.parameters.length) {
      return slot.parameters[fallbackIndex].currentValue;
    }
    return null;
  }

  static int? _parseIndexedEffectId(String effectId, String prefix) {
    if (!effectId.startsWith(prefix)) return null;
    return int.tryParse(effectId.substring(prefix.length));
  }

  int _mapSlotParamToCc(int slotIndex, int paramIndex) {
    switch (slotIndex) {
      case 0:
        switch (paramIndex) {
          case 0:
            return ccAmpModel;
          case 1:
            return ccDrive;
          case 2:
            return ccBass;
          case 3:
            return ccMid;
          case 4:
            return ccTreble;
          case 5:
            return ccChannelVolume;
          default:
            return ccDrive;
        }
      case 1:
        switch (paramIndex) {
          case 0:
            return ccCabinetModel;
          case 1:
            return ccAirLevel;
          default:
            return ccCabinetModel;
        }
      case 2:
        switch (paramIndex) {
          case 0:
            return ccCompressor;
          case 1:
            return ccNoiseGate;
          default:
            return ccCompressor;
        }
      case 3:
        switch (paramIndex) {
          case 0:
            return ccEffectSelect;
          case 1:
            return ccEffectTweak;
          case 2:
            return ccFxLoCut;
          case 3:
            return ccEffectOnOff;
          default:
            return ccEffectTweak;
        }
      default:
        return ccDrive;
    }
  }

  ({int slot, int param})? _mapCcToSlotParam(int cc) {
    switch (cc) {
      case ccAmpModel:
        return (slot: 0, param: 0);
      case ccDrive:
        return (slot: 0, param: 1);
      case ccBass:
        return (slot: 0, param: 2);
      case ccMid:
        return (slot: 0, param: 3);
      case ccTreble:
        return (slot: 0, param: 4);
      case ccChannelVolume:
        return (slot: 0, param: 5);
      case ccCabinetModel:
        return (slot: 1, param: 0);
      case ccAirLevel:
        return (slot: 1, param: 1);
      case ccCompressor:
        return (slot: 2, param: 0);
      case ccNoiseGate:
        return (slot: 2, param: 1);
      case ccEffectSelect:
        return (slot: 3, param: 0);
      case ccEffectTweak:
        return (slot: 3, param: 1);
      case ccFxLoCut:
        return (slot: 3, param: 2);
      case ccEffectOnOff:
        return (slot: 3, param: 3);
      default:
        return null;
    }
  }

  static const List<int> _supportedCcList = [
    ccEffectTweak,
    ccWahPedal,
    ccMasterVolume,
    ccAmpModel,
    ccDrive,
    ccBass,
    ccMid,
    ccTreble,
    ccChannelVolume,
    ccCompressor,
    ccEffectSelect,
    ccFxLoCut,
    ccNoiseGate,
    ccEffectOnOff,
    ccApplyFxToDi,
    ccCabinetModel,
    ccAirLevel,
  ];
}
