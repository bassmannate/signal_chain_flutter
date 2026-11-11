import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../core/midi/midi_message.dart';
import '../../core/midi/midi_transport.dart';
import '../../models/effect_slot.dart';
import '../../models/parameter_descriptor.dart';
import '../../models/patch.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../../protocols/device_protocol.dart';
import '../connection/device_connection_controller.dart';

/// Controller managing active patch editing, slot inspection, and bidirectional
/// real-time parameter synchronization with connected hardware.
class PatchEditorController extends ChangeNotifier {
  final MidiTransport transport;
  final DeviceConnectionController connectionController;

  Patch? _patch;
  int _selectedSlotIndex = 0;
  bool _isDirty = false;
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<MidiMessage>? _midiSubscription;
  bool _isHandlingIncoming = false;

  PatchEditorController({
    required this.transport,
    required this.connectionController,
    Patch? initialPatch,
  }) : _patch = initialPatch {
    _midiSubscription = transport.onMessageReceived.listen(_handleIncomingMessage);
  }

  /// Currently loaded active preset.
  Patch? get patch => _patch;

  /// Index of the effect slot currently inspected in the UI.
  int get selectedSlotIndex => _selectedSlotIndex;

  /// Currently selected [EffectSlot], or null if chain is empty.
  EffectSlot? get selectedSlot {
    final current = _patch;
    if (current == null ||
        _selectedSlotIndex < 0 ||
        _selectedSlotIndex >= current.slots.length) {
      return null;
    }
    return current.slots[_selectedSlotIndex];
  }

  /// True if local patch state has unsaved modifications relative to hardware/library.
  bool get isDirty => _isDirty;

  /// True while performing a hardware patch pull or push.
  bool get isLoading => _isLoading;

  /// Most recent error message, or null.
  String? get errorMessage => _errorMessage;

  /// Resolved protocol engine from [connectionController].
  DeviceProtocol get protocol => connectionController.activeProtocol;

  /// Replaces the active editor patch and resets the dirty flag.
  void loadPatch(Patch patch) {
    _patch = patch;
    _isDirty = false;
    _selectedSlotIndex = 0;
    _errorMessage = null;
    notifyListeners();
  }

  /// Changes the inspected slot index.
  void selectSlot(int slotIndex) {
    if (_patch != null &&
        slotIndex >= 0 &&
        slotIndex < _patch!.slots.length &&
        _selectedSlotIndex != slotIndex) {
      _selectedSlotIndex = slotIndex;
      notifyListeners();
    }
  }

  /// Requests the active edit buffer preset from the connected hardware.
  Future<void> pullCurrentPatch() async {
    if (!transport.isConnected) {
      _errorMessage = 'Cannot pull patch: MIDI transport is not connected.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final activeProto = protocol;
      final request = activeProto.buildCurrentPatchRequest();

      final response = await transport.sendSysExAndWait(
        request,
        responseMatcher: activeProto.isPatchDump,
        timeout: const Duration(seconds: 3),
      );

      final decoded = activeProto.decodePatch(response);
      _patch = decoded;
      _isDirty = false;
      _selectedSlotIndex = 0;
    } catch (e) {
      _errorMessage = 'Failed to pull patch from device: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pushes [patchToPush] (or the active patch) to the connected device.
  Future<void> pushPatchToDevice([Patch? patchToPush]) async {
    final target = patchToPush ?? _patch;
    if (target == null) {
      _errorMessage = 'No patch loaded to push to device.';
      notifyListeners();
      return;
    }

    if (!transport.isConnected) {
      _errorMessage = 'Cannot push patch: MIDI transport is not connected.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final activeProto = protocol;
      final dumpMessage = activeProto.encodePatch(target);
      await transport.send(dumpMessage);

      _patch = target;
      _isDirty = false;
    } catch (e) {
      _errorMessage = 'Failed to push patch to device: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles the bypass/enable state for the effect slot at [slotIndex].
  void toggleSlotEnabled(int slotIndex) {
    final current = _patch;
    if (current == null ||
        slotIndex < 0 ||
        slotIndex >= current.slots.length) {
      return;
    }

    final slot = current.slots[slotIndex];
    final updatedSlot = slot.copyWith(isEnabled: !slot.isEnabled);
    final newSlots = List<EffectSlot>.from(current.slots);
    newSlots[slotIndex] = updatedSlot;

    _patch = current.copyWith(slots: newSlots);
    _isDirty = true;
    notifyListeners();
  }

  /// Swaps the effect algorithm in [slotIndex] using [EffectCatalogRegistry].
  void changeSlotEffect(int slotIndex, String newEffectId) {
    final current = _patch;
    if (current == null ||
        slotIndex < 0 ||
        slotIndex >= current.slots.length) {
      return;
    }

    final family = connectionController.activeFamily;
    final def = EffectCatalogRegistry.getDefinition(family, newEffectId);

    final newParams = def.parameters.map((desc) {
      return ParameterValue(
        descriptor: desc,
        currentValue: desc.defaultValue.toDouble(),
      );
    }).toList();

    final updatedSlot = EffectSlot(
      slotIndex: slotIndex,
      effectId: def.effectId,
      effectName: def.name,
      isEnabled: true,
      parameters: newParams,
    );

    final newSlots = List<EffectSlot>.from(current.slots);
    newSlots[slotIndex] = updatedSlot;

    _patch = current.copyWith(slots: newSlots);
    _isDirty = true;
    notifyListeners();
  }

  /// Updates parameter at [paramIndex] in [slotIndex] to [newValue],
  /// updating local state immediately and transmitting real-time MIDI when connected.
  Future<void> updateParameter(
    int slotIndex,
    int paramIndex,
    int newValue,
  ) async {
    final current = _patch;
    if (current == null ||
        slotIndex < 0 ||
        slotIndex >= current.slots.length) {
      return;
    }

    final slot = current.slots[slotIndex];
    if (paramIndex < 0 || paramIndex >= slot.parameters.length) {
      return;
    }

    final param = slot.parameters[paramIndex];
    final updatedParam = param.copyWith(currentValue: newValue.toDouble());
    final newParams = List<ParameterValue>.from(slot.parameters);
    newParams[paramIndex] = updatedParam;

    final updatedSlot = slot.copyWith(parameters: newParams);
    final newSlots = List<EffectSlot>.from(current.slots);
    newSlots[slotIndex] = updatedSlot;

    _patch = current.copyWith(slots: newSlots);
    _isDirty = true;
    notifyListeners();

    // Dispatch real-time parameter change to hardware if connected
    if (transport.isConnected && !_isHandlingIncoming) {
      try {
        final editMsg = protocol.buildParameterEditMessage(
          slotIndex: slotIndex,
          paramIndex: paramIndex,
          value: newValue,
        );
        await transport.send(editMsg);
      } catch (e) {
        _errorMessage = 'Failed to transmit parameter edit: $e';
        notifyListeners();
      }
    }
  }

  /// Handles incoming messages received from hardware for bidirectional sync.
  void _handleIncomingMessage(MidiMessage message) {
    if (_isHandlingIncoming) return;

    final activeProto = protocol;

    if (activeProto.isParameterEdit(message)) {
      final edit = activeProto.parseParameterEdit(message);
      if (edit != null) {
        _applyIncomingParameterEdit(
          edit.slotIndex,
          edit.paramIndex,
          edit.value,
        );
      }
    } else if (activeProto.isPatchDump(message)) {
      try {
        final decoded = activeProto.decodePatch(message);
        _patch = decoded;
        _isDirty = false;
        notifyListeners();
      } catch (_) {
        // Ignore unparseable frames
      }
    }
  }

  /// Applies a hardware parameter update without re-dispatching over MIDI.
  void _applyIncomingParameterEdit(int slotIndex, int paramIndex, int value) {
    final current = _patch;
    if (current == null ||
        slotIndex < 0 ||
        slotIndex >= current.slots.length) {
      return;
    }

    final slot = current.slots[slotIndex];
    if (paramIndex < 0 || paramIndex >= slot.parameters.length) {
      return;
    }

    _isHandlingIncoming = true;
    try {
      final param = slot.parameters[paramIndex];
      final updatedParam = param.copyWith(currentValue: value.toDouble());
      final newParams = List<ParameterValue>.from(slot.parameters);
      newParams[paramIndex] = updatedParam;

      final updatedSlot = slot.copyWith(parameters: newParams);
      final newSlots = List<EffectSlot>.from(current.slots);
      newSlots[slotIndex] = updatedSlot;

      _patch = current.copyWith(slots: newSlots);
      notifyListeners();
    } finally {
      _isHandlingIncoming = false;
    }
  }

  @override
  void dispose() {
    _midiSubscription?.cancel();
    super.dispose();
  }
}

