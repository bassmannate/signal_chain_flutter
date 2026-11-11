import '../core/midi/midi_message.dart';
import '../models/device_family.dart';
import '../models/patch.dart';

/// Abstract contract for a device-specific MIDI SysEx protocol engine.
///
/// Implements pure Dart encoding, decoding, parameter mapping, and handshake
/// framing for a particular hardware processor family.
abstract class DeviceProtocol {
  const DeviceProtocol();

  /// The primary [DeviceFamily] supported by this protocol handler.
  DeviceFamily get supportedFamily;

  /// Returns true if the incoming identity reply [response] matches this protocol's hardware.
  bool matchesIdentityResponse(MidiMessage response);

  /// Resolves the specific [DeviceFamily] model from an identity reply [response].
  DeviceFamily parseDeviceFamily(MidiMessage response);

  /// Generates the standard Universal Non-Real-Time Identity Request SysEx message.
  MidiMessage buildIdentityRequest({int channel = 0x7F}) {
    return MidiMessage.sysEx([0x7E, channel & 0x7F, 0x06, 0x01]);
  }

  /// Builds the device initialization sequence (e.g. editor mode enable, handshake pings).
  List<MidiMessage> buildInitSequence();

  /// Builds an editor mode enable or disable message, if supported by the device.
  MidiMessage? buildEditorModeMessage({required bool enable});

  /// Builds a SysEx request for the currently active edit buffer preset.
  MidiMessage buildCurrentPatchRequest();

  /// Builds a request to recall or fetch the preset stored at memory slot [programNumber].
  MidiMessage buildPatchSlotRequest(int programNumber);

  /// Decodes an incoming patch dump SysEx message into a domain [Patch].
  Patch decodePatch(MidiMessage message);

  /// Encodes a domain [Patch] into a SysEx message ready for transmission to the device.
  MidiMessage encodePatch(Patch patch);

  /// Builds a real-time parameter change message for an effect parameter.
  ///
  /// [slotIndex] is the zero-based index of the effect in the chain.
  /// [paramIndex] is the zero-based parameter index within that effect block.
  /// [value] is the raw discrete or continuous integer value.
  MidiMessage buildParameterEditMessage({
    required int slotIndex,
    required int paramIndex,
    required int value,
  });

  /// Returns true if [message] is a patch dump payload that can be parsed by [decodePatch].
  bool isPatchDump(MidiMessage message);

  /// Returns true if [message] is a real-time parameter change feedback message from hardware.
  bool isParameterEdit(MidiMessage message);

  /// Parses real-time parameter change bytes from hardware feedback, or null if unparseable.
  ({int slotIndex, int paramIndex, int value})? parseParameterEdit(MidiMessage message);
}
