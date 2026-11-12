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

  /// Alias for [buildCurrentPatchRequest] ensuring semantic clarity across controllers.
  MidiMessage buildRequestCurrentPatchMessage() => buildCurrentPatchRequest();

  /// Builds a request to recall or fetch the preset stored at memory slot [programNumber].
  MidiMessage buildPatchSlotRequest(int programNumber);

  /// Builds a SysEx message to write and save [patch] directly to persistent memory slot [programNumber].
  MidiMessage buildSavePatchToSlotMessage(Patch patch, int programNumber);

  /// Decodes an incoming patch dump SysEx message into a domain [Patch].
  Patch decodePatch(MidiMessage message);

  /// Encodes a domain [Patch] into a SysEx message ready for transmission to the device.
  ///
  /// If [programNumber] is provided, formats the message to save directly to that memory slot.
  MidiMessage encodePatch(Patch patch, {int? programNumber});

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

  /// Returns true if [message] represents the currently active edit buffer dump.
  bool isCurrentPatchDump(MidiMessage message);

  /// Returns true if [message] represents a persistent memory slot dump (0–99).
  bool isSlotPatchDump(MidiMessage message);

  /// Extracts the target memory slot index (0–99) from a slot dump message, or null.
  int? extractSlotIndex(MidiMessage message);

  /// Builds the sequence of MIDI messages needed to switch the active hardware preset
  /// to memory slot [slotIndex] (e.g. Bank Select CC0/CC32 + Program Change).
  List<MidiMessage> buildSlotSelectMessages(int slotIndex);

  /// Builds a real-time message to toggle or set the bypass/enabled state of an effect slot.
  MidiMessage? buildSlotBypassMessage({
    required int slotIndex,
    required bool isEnabled,
  }) => null;

  /// Builds a real-time message to set the active/focused effect slot on the hardware display.
  MidiMessage? buildSlotFocusMessage(int slotIndex) => null;

  /// Returns true if [message] is a real-time slot bypass event.
  bool isSlotBypass(MidiMessage message) => false;

  /// Parses slot index and bypass state from an incoming bypass message.
  ({int slotIndex, bool isEnabled})? parseSlotBypass(MidiMessage message) => null;

  /// Returns true if [message] is an effect slot focus/navigation change event from hardware.
  bool isSlotFocusChange(MidiMessage message) => false;

  /// Parses the newly focused slot index from a slot navigation event.
  int? parseSlotFocusChange(MidiMessage message) => null;

  /// Returns true if [message] is a hardware slot change notification (e.g. SysEx 64 26 or PC).
  bool isSlotChange(MidiMessage message) => false;

  /// Parses the target slot index from a hardware slot change message.
  int? parseSlotChange(MidiMessage message, {int patchesPerBank = 10}) => null;

  /// Returns true if [message] is a real-time parameter change feedback message from hardware.
  bool isParameterEdit(MidiMessage message);

  /// Parses real-time parameter change bytes from hardware feedback, or null if unparseable.
  ({int slotIndex, int paramIndex, int value})? parseParameterEdit(MidiMessage message);
}
