import 'dart:convert';
import 'dart:typed_data';

import '../core/midi/midi_message.dart';
import '../models/device_family.dart';
import '../models/effect_slot.dart';
import '../models/parameter_descriptor.dart';
import '../models/patch.dart';
import 'device_protocol.dart';
import 'sysex_codec.dart';

/// Pure Dart protocol engine for the Line 6 Bass Pod Pro rackmount processor.
///
/// Features Line 6 3-byte SysEx headers (`0x00 0x01 0x0C`), 72-byte edit buffer
/// dump decoding/encoding, Program Change preset switching, and real-time CC modulation.
class Line6BassPodProProtocol extends DeviceProtocol {
  /// Line 6 3-byte MIDI Manufacturer ID: 0x00 0x01 0x0C.
  static const List<int> manufacturerId = [0x00, 0x01, 0x0C];

  /// Bass Pod Pro family / device identifier byte.
  static const int deviceFamilyByte = 0x01;

  /// SysEx Command Opcodes
  static const int cmdEditBufferDumpRequest = 0x00;
  static const int cmdProgramDumpRequest = 0x01;
  static const int cmdEditBufferDump = 0x00;

  /// Standard Continuous Controller (CC) Mappings for Bass Pod Pro
  static const int ccDrive = 4;
  static const int ccMasterVolume = 7;
  static const int ccEffectSelect = 11;
  static const int ccAmpModel = 12;
  static const int ccCabinetModel = 13;
  static const int ccBass = 14;
  static const int ccMid = 15;
  static const int ccTreble = 16;
  static const int ccChannelVolume = 17;
  static const int ccEffectTweak = 19;
  static const int ccCompressor = 64;

  /// 72-byte Edit Buffer payload size.
  static const int editBufferSize = 72;

  /// Standard Bass Pod Pro Amp Models
  static const List<String> ampModels = [
    'Tube Preamp',
    'Classic (SVT)',
    'Brit Major (Marshall Major)',
    'Silver Panel (Bassman)',
    'Session (Eden WT-800)',
    'California (Mesa 400+)',
    'Submaster (SWR SM-400)',
    'Rock Classic (Ampeg SVT)',
    'Modern Class (SWR)',
    'British Class (Vox AC-100)',
    'Stadium (Sunn Coliseum)',
    'Motor City (B-15)',
    'Fuzz Bass',
    'Sub Synth',
    'Double Dynamic',
    'Bypass',
  ];

  /// Standard Bass Pod Pro Cabinet Models
  static const List<String> cabModels = [
    '1x12 1964 Flip Top',
    '1x15 1968 Sunn',
    '2x10 1998 Modern',
    '2x15 1972 California',
    '4x10 1995 Line 6 custom',
    '4x12 1967 British',
    '8x10 1974 Classic',
    'No Cabinet',
  ];

  /// Standard Bass Pod Pro Effects
  static const List<String> effectTypes = [
    'Bypass',
    'Chorus',
    'Flanger',
    'Rotary Speaker',
    'Envelope Follower',
    'Octaver',
    'Delay',
    'Tremolo',
  ];

  final int midiChannel;

  const Line6BassPodProProtocol({
    this.midiChannel = 0,
  });

  @override
  DeviceFamily get supportedFamily => DeviceFamily.line6BassPodPro;

  @override
  bool matchesIdentityResponse(MidiMessage response) {
    final data = response.data;
    if (!SysexCodec.isIdentityReply(data)) return false;
    // 3-byte manufacturer ID: data[5] == 0x00, data[6] == 0x01, data[7] == 0x0C
    return data.length >= 8 &&
        data[5] == manufacturerId[0] &&
        data[6] == manufacturerId[1] &&
        data[7] == manufacturerId[2];
  }

  @override
  DeviceFamily parseDeviceFamily(MidiMessage response) {
    if (matchesIdentityResponse(response)) {
      return DeviceFamily.line6BassPodPro;
    }
    return DeviceFamily.unknown;
  }

  @override
  List<MidiMessage> buildInitSequence() {
    return [
      buildCurrentPatchRequest(),
    ];
  }

  @override
  MidiMessage? buildEditorModeMessage({required bool enable}) {
    // Line 6 Pod series does not require a special editor mode latch.
    return null;
  }

  @override
  MidiMessage buildCurrentPatchRequest() {
    // F0 00 01 0C 01 00 F7
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      cmdEditBufferDumpRequest,
    ]);
  }

  @override
  MidiMessage buildPatchSlotRequest(int programNumber) {
    // Recalls preset using standard MIDI Program Change
    return MidiMessage.programChange(
      channel: midiChannel,
      program: programNumber.clamp(0, 127),
    );
  }

  /// Builds a SysEx request for a specific program memory slot dump.
  MidiMessage buildProgramDumpRequest(int programNumber) {
    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      cmdProgramDumpRequest,
      programNumber & 0x7F,
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
  bool isPatchDump(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 10) return false;
    return data[1] == manufacturerId[0] &&
        data[2] == manufacturerId[1] &&
        data[3] == manufacturerId[2] &&
        data[4] == deviceFamilyByte &&
        data[5] == cmdEditBufferDump;
  }

  @override
  bool isParameterEdit(MidiMessage message) {
    if (!message.isControlChange) return false;
    final cc = message.data[1];
    return _supportedCcList.contains(cc);
  }

  @override
  ({int slotIndex, int paramIndex, int value})? parseParameterEdit(MidiMessage message) {
    if (!isParameterEdit(message)) return null;
    final cc = message.data[1];
    final value = message.data[2];
    final mapped = _mapCcToSlotParam(cc);
    if (mapped == null) return null;
    return (slotIndex: mapped.slot, paramIndex: mapped.param, value: value);
  }

  @override
  Patch decodePatch(MidiMessage message) {
    final data = message.data;
    if (!isPatchDump(message)) {
      throw FormatException('Message is not a valid Line 6 Bass Pod Pro SysEx dump: $message');
    }

    // Header: F0 00 01 0C 01 00 (6 bytes)
    final payloadBytes = data.sublist(6, data.length - 1); // exclude trailing F7
    Uint8List buffer;

    if (payloadBytes.length >= editBufferSize * 2) {
      // 144-byte nibblized format
      buffer = SysexCodec.unpackNibbles(payloadBytes);
    } else if (payloadBytes.length >= editBufferSize) {
      // 72-byte raw format
      buffer = payloadBytes.sublist(0, editBufferSize);
    } else {
      throw FormatException(
        'Line 6 SysEx payload too short: expected at least $editBufferSize bytes, got ${payloadBytes.length}',
      );
    }

    return decodeEditBuffer(buffer);
  }

  /// Decodes a 72-byte Edit Buffer payload into a domain [Patch].
  Patch decodeEditBuffer(Uint8List buffer, {int? programNumber}) {
    if (buffer.length < editBufferSize) {
      throw ArgumentError('Buffer too short for Bass Pod Pro: ${buffer.length} < $editBufferSize');
    }

    // Extract ASCII Patch Name from bytes 56..71 (16 bytes)
    final rawName = ascii.decode(buffer.sublist(56, 72), allowInvalid: true).trim();
    final patchName = rawName.isEmpty ? 'Bass Preset' : rawName;

    // Slot 0: Amp Block
    final ampModelIdx = buffer[0].clamp(0, ampModels.length - 1);
    final drive = buffer[2].toDouble();
    final bass = buffer[3].toDouble();
    final mid = buffer[4].toDouble();
    final treble = buffer[5].toDouble();
    final chanVol = buffer[6].toDouble();

    final ampSlot = EffectSlot(
      slotIndex: 0,
      effectId: 'line6_amp_$ampModelIdx',
      effectName: ampModels[ampModelIdx],
      isEnabled: true,
      parameters: [
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'amp_model',
            name: 'Amp Model',
            min: 0,
            max: 15,
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
            max: 127,
            defaultValue: 64,
          ),
          currentValue: drive,
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'bass',
            name: 'Bass',
            min: 0,
            max: 127,
            defaultValue: 64,
          ),
          currentValue: bass,
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'mid',
            name: 'Mid',
            min: 0,
            max: 127,
            defaultValue: 64,
          ),
          currentValue: mid,
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'treble',
            name: 'Treble',
            min: 0,
            max: 127,
            defaultValue: 64,
          ),
          currentValue: treble,
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'chan_vol',
            name: 'Channel Volume',
            min: 0,
            max: 127,
            defaultValue: 100,
          ),
          currentValue: chanVol,
        ),
      ],
    );

    // Slot 1: Cabinet Block
    final cabModelIdx = buffer[1].clamp(0, cabModels.length - 1);
    final cabSlot = EffectSlot(
      slotIndex: 1,
      effectId: 'line6_cab_$cabModelIdx',
      effectName: cabModels[cabModelIdx],
      isEnabled: true,
      parameters: [
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'cab_model',
            name: 'Cabinet Model',
            min: 0,
            max: 7,
            defaultValue: 0,
            labels: cabModels,
          ),
          currentValue: cabModelIdx.toDouble(),
        ),
      ],
    );

    // Slot 2: Compressor Block
    final compLevel = buffer[7].toDouble();
    final compEnabled = buffer.length > 11 ? buffer[11] != 0 : compLevel > 0;
    final compSlot = EffectSlot(
      slotIndex: 2,
      effectId: 'line6_comp',
      effectName: 'Compressor',
      isEnabled: compEnabled,
      parameters: [
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'comp_threshold',
            name: 'Comp Ratio / Threshold',
            min: 0,
            max: 127,
            defaultValue: 0,
          ),
          currentValue: compLevel,
        ),
      ],
    );

    // Slot 3: Modulation / FX Block
    final fxTypeIdx = buffer[8].clamp(0, effectTypes.length - 1);
    final fxTweak = buffer[9].toDouble();
    final fxSlot = EffectSlot(
      slotIndex: 3,
      effectId: 'line6_fx_$fxTypeIdx',
      effectName: effectTypes[fxTypeIdx],
      isEnabled: fxTypeIdx != 0,
      parameters: [
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'fx_type',
            name: 'Effect Type',
            min: 0,
            max: 7,
            defaultValue: 0,
            labels: effectTypes,
          ),
          currentValue: fxTypeIdx.toDouble(),
        ),
        ParameterValue(
          descriptor: const ParameterDescriptor(
            id: 'fx_tweak',
            name: 'Effect Tweak',
            min: 0,
            max: 127,
            defaultValue: 64,
          ),
          currentValue: fxTweak,
        ),
      ],
    );

    final masterVol = buffer[10].toDouble();

    return Patch(
      id: programNumber != null ? 'line6_prog_$programNumber' : 'line6_edit_buffer',
      name: patchName,
      deviceFamily: DeviceFamily.line6BassPodPro,
      programNumber: programNumber,
      slots: [ampSlot, cabSlot, compSlot, fxSlot],
      metadata: {
        'masterVolume': masterVol,
        'rawDump': Uint8List.fromList(buffer),
      },
    );
  }

  @override
  MidiMessage encodePatch(Patch patch, {bool useNibbles = true}) {
    final buffer = Uint8List(editBufferSize);

    // If existing raw dump is preserved in metadata, start with it
    final existingRaw = patch.metadata['rawDump'] as Uint8List?;
    if (existingRaw != null && existingRaw.length >= editBufferSize) {
      buffer.setRange(0, editBufferSize, existingRaw);
    }

    // Populate parameters from slots
    for (final slot in patch.slots) {
      switch (slot.slotIndex) {
        case 0: // Amp Block
          for (final p in slot.parameters) {
            final val = p.currentValue.round().clamp(0, 127);
            switch (p.descriptor.id) {
              case 'amp_model':
                buffer[0] = val & 0x0F;
                break;
              case 'drive':
                buffer[2] = val;
                break;
              case 'bass':
                buffer[3] = val;
                break;
              case 'mid':
                buffer[4] = val;
                break;
              case 'treble':
                buffer[5] = val;
                break;
              case 'chan_vol':
                buffer[6] = val;
                break;
            }
          }
          break;

        case 1: // Cabinet Block
          for (final p in slot.parameters) {
            if (p.descriptor.id == 'cab_model') {
              buffer[1] = p.currentValue.round().clamp(0, 15);
            }
          }
          break;

        case 2: // Compressor Block
          buffer[11] = slot.isEnabled ? 1 : 0;
          for (final p in slot.parameters) {
            if (p.descriptor.id == 'comp_threshold') {
              buffer[7] = p.currentValue.round().clamp(0, 127);
            }
          }
          break;

        case 3: // Modulation / FX Block
          for (final p in slot.parameters) {
            final val = p.currentValue.round().clamp(0, 127);
            if (p.descriptor.id == 'fx_type') {
              buffer[8] = val & 0x0F;
            } else if (p.descriptor.id == 'fx_tweak') {
              buffer[9] = val;
            }
          }
          break;
      }
    }

    if (patch.metadata.containsKey('masterVolume')) {
      final mv = (patch.metadata['masterVolume'] as num).round().clamp(0, 127);
      buffer[10] = mv;
    }

    // Write ASCII name to bytes 56..71 (16 bytes)
    final paddedName = patch.name.padRight(16, ' ').substring(0, 16);
    buffer.setRange(56, 72, ascii.encode(paddedName));

    final payloadData = useNibbles ? SysexCodec.packNibbles(buffer) : buffer;

    return MidiMessage.sysEx([
      ...manufacturerId,
      deviceFamilyByte,
      cmdEditBufferDump,
      ...payloadData,
    ]);
  }

  int _mapSlotParamToCc(int slotIndex, int paramIndex) {
    switch (slotIndex) {
      case 0: // Amp
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
      case 1: // Cabinet
        return ccCabinetModel;
      case 2: // Compressor
        return ccCompressor;
      case 3: // FX
        return paramIndex == 0 ? ccEffectSelect : ccEffectTweak;
      default:
        return ccDrive;
    }
  }

  ({int slot, int param})? _mapCcToSlotParam(int cc) {
    switch (cc) {
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
      case ccAmpModel:
        return (slot: 0, param: 0);
      case ccCabinetModel:
        return (slot: 1, param: 0);
      case ccCompressor:
        return (slot: 2, param: 0);
      case ccEffectSelect:
        return (slot: 3, param: 0);
      case ccEffectTweak:
        return (slot: 3, param: 1);
      default:
        return null;
    }
  }

  static const List<int> _supportedCcList = [
    ccDrive,
    ccMasterVolume,
    ccEffectSelect,
    ccAmpModel,
    ccCabinetModel,
    ccBass,
    ccMid,
    ccTreble,
    ccChannelVolume,
    ccEffectTweak,
    ccCompressor,
  ];
}
