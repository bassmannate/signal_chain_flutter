import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../../core/midi/midi_message.dart';
import '../../core/midi/midi_transport.dart';
import '../../core/midi/mock_midi_transport.dart';
import '../../models/device_family.dart';
import '../../models/effect_slot.dart';
import '../../models/parameter_descriptor.dart';
import '../../models/patch.dart';
import '../../models/patch_diff.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../../protocols/device_protocol.dart';
import '../connection/device_connection_controller.dart';
import '../library/patch_library_controller.dart';
import 'patch_edit_history.dart';

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
  bool _isSyncingStructure = false;

  final PatchEditHistory _history;
  CompareSlot _activeCompareSlot = CompareSlot.a;
  Patch? _compareSlotA;
  Patch? _compareSlotB;
  PatchLibraryController? _libraryController;

  bool _isDisposed = false;
  bool _isRestoringBank = false;
  bool _cancelBankRestore = false;
  double _bankRestoreProgress = 0.0;
  String? _bankRestoreStatus;
  int _bankRestoreCompletedCount = 0;
  int _bankRestoreTotalCount = 0;

  PatchEditorController({
    required this.transport,
    required this.connectionController,
    Patch? initialPatch,
    PatchEditHistory? history,
  })  : _patch = initialPatch,
        _history = history ?? PatchEditHistory(),
        _compareSlotA = initialPatch {
    connectionController.setEditorController(this);
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

  /// Batch hardware bank restore progress state.
  bool get isRestoringBank => _isRestoringBank;
  double get bankRestoreProgress => _bankRestoreProgress;
  String? get bankRestoreStatus => _bankRestoreStatus;
  int get bankRestoreCompletedCount => _bankRestoreCompletedCount;
  int get bankRestoreTotalCount => _bankRestoreTotalCount;

  /// Binds an optional [PatchLibraryController] for "Save Copy As..." duplication.
  void setLibraryController(PatchLibraryController? libraryController) {
    _libraryController = libraryController;
  }

  /// Resolved protocol engine from [connectionController].
  DeviceProtocol get protocol => connectionController.activeProtocol;

  /// True if additional effect slots can be added to the current patch.
  bool get canAddEffectSlot =>
      _patch != null &&
      _patch!.slots.length < connectionController.activeFamily.maxEffectSlots &&
      connectionController.activeFamily.isZoomMsPlus;

  /// True if slots can be removed from the current patch.
  bool get canRemoveEffectSlot =>
      _patch != null &&
      _patch!.slots.length > 1 &&
      connectionController.activeFamily.isZoomMsPlus;

  /// True if slots can be reordered in the signal chain for this device family.
  bool get canReorderSlots =>
      connectionController.activeFamily.isZoomMsPlus;

  /// Undo/Redo availability and descriptive labels.
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  String? get undoLabel => _history.undoLabel;
  String? get redoLabel => _history.redoLabel;

  /// Active A/B comparison slot and snapshots.
  CompareSlot get activeCompareSlot => _activeCompareSlot;
  Patch? get comparePatchA => _compareSlotA;
  Patch? get comparePatchB => _compareSlotB;
  bool get hasCompareSnapshotB => _compareSlotB != null;

  /// True when both A and B snapshots exist and differ from each other.
  bool get hasABDifference {
    final a = _compareSlotA;
    final b = _compareSlotB;
    if (a == null || b == null) return false;
    return PatchDiff.compute(a, b).hasChanges;
  }

  void _resetSessionBaseline(Patch patch) {
    _history.reset();
    _activeCompareSlot = CompareSlot.a;
    _compareSlotA = patch;
    _compareSlotB = null;
  }

  void _syncActiveCompareSnapshot() {
    final current = _patch;
    if (current == null) return;
    if (_activeCompareSlot == CompareSlot.a) {
      if (_compareSlotB == null) {
        // First edit after loading: keep A as baseline and fork into B.
        _activeCompareSlot = CompareSlot.b;
        _compareSlotB = current;
      } else {
        _compareSlotA = current;
      }
    } else {
      _compareSlotB = current;
    }
  }

  void _recordUserEdit({
    required Patch previousPatch,
    required int previousSelectedSlot,
    required bool previousDirty,
    required String label,
    String? coalesceKey,
  }) {
    _history.recordEdit(
      previousPatch: previousPatch,
      previousSelectedSlot: previousSelectedSlot,
      previousDirty: previousDirty,
      label: label,
      coalesceKey: coalesceKey,
    );
    _syncActiveCompareSnapshot();
  }

  /// Begins an explicit edit gesture (e.g. continuous rotary knob drag),
  /// coalescing all intermediate parameter updates into a single Undo step.
  void beginEditGesture({String label = 'Adjust Parameter'}) {
    final current = _patch;
    if (current == null) return;
    _history.beginGesture(
      preGesturePatch: current,
      selectedSlotIndex: _selectedSlotIndex,
      isDirty: _isDirty,
      label: label,
    );
  }

  /// Ends an explicit edit gesture, committing a single Undo entry if changed.
  void endEditGesture() {
    if (_history.commitGesture(_patch)) {
      notifyListeners();
    }
  }

  /// Reverts the active patch to the previous Undo snapshot and syncs hardware.
  bool undo() {
    final current = _patch;
    if (current == null) return false;

    final entry = _history.undo(
      currentPatch: current,
      currentSelectedSlot: _selectedSlotIndex,
      currentDirty: _isDirty,
    );
    if (entry == null) return false;

    _applyRestoredPatch(
      fromPatch: current,
      targetPatch: entry.patch,
      targetSlotIndex: entry.selectedSlotIndex,
      targetDirty: entry.isDirty,
    );
    return true;
  }

  /// Re-applies the next Redo snapshot and syncs hardware.
  bool redo() {
    final current = _patch;
    if (current == null) return false;

    final entry = _history.redo(
      currentPatch: current,
      currentSelectedSlot: _selectedSlotIndex,
      currentDirty: _isDirty,
    );
    if (entry == null) return false;

    _applyRestoredPatch(
      fromPatch: current,
      targetPatch: entry.patch,
      targetSlotIndex: entry.selectedSlotIndex,
      targetDirty: entry.isDirty,
    );
    return true;
  }

  void _applyRestoredPatch({
    required Patch fromPatch,
    required Patch targetPatch,
    required int targetSlotIndex,
    required bool targetDirty,
  }) {
    _patch = targetPatch;
    _isDirty = targetDirty;
    if (targetPatch.slots.isNotEmpty) {
      _selectedSlotIndex = targetSlotIndex.clamp(0, targetPatch.slots.length - 1);
    } else {
      _selectedSlotIndex = 0;
    }

    if (_activeCompareSlot == CompareSlot.a) {
      _compareSlotA = targetPatch;
    } else {
      _compareSlotB = targetPatch;
    }

    _syncPatchTransitionToDevice(fromPatch, targetPatch);
    notifyListeners();
  }

  /// Stores the current patch into Compare Slot A.
  void captureCompareA() {
    final current = _patch;
    if (current == null) return;
    _compareSlotA = current;
    notifyListeners();
  }

  /// Toggles the active editor between Compare Slot A and Compare Slot B,
  /// dispatching targeted hardware deltas so the pedal updates live.
  void toggleCompareSlot() {
    final current = _patch;
    if (current == null) return;

    _compareSlotA ??= current;
    _compareSlotB ??= current;

    final targetSlot =
        _activeCompareSlot == CompareSlot.a ? CompareSlot.b : CompareSlot.a;
    final targetPatch =
        targetSlot == CompareSlot.a ? _compareSlotA! : _compareSlotB!;

    _activeCompareSlot = targetSlot;
    _patch = targetPatch;
    if (targetPatch.slots.isNotEmpty) {
      _selectedSlotIndex = _selectedSlotIndex.clamp(0, targetPatch.slots.length - 1);
    } else {
      _selectedSlotIndex = 0;
    }
    _isDirty = true;

    _syncPatchTransitionToDevice(current, targetPatch);
    notifyListeners();
  }

  /// Copies Compare Slot A into B (or B into A) and updates the active view if needed.
  void copyCompareSlot({required CompareSlot from, required CompareSlot to}) {
    if (from == to) return;
    final source = from == CompareSlot.a ? _compareSlotA : _compareSlotB;
    if (source == null) return;

    final previous = _patch;
    if (to == CompareSlot.a) {
      _compareSlotA = source;
    } else {
      _compareSlotB = source;
    }

    if (_activeCompareSlot == to && previous != null) {
      _history.recordEdit(
        previousPatch: previous,
        previousSelectedSlot: _selectedSlotIndex,
        previousDirty: _isDirty,
        label: from == CompareSlot.a ? 'Copy A to B' : 'Copy B to A',
      );
      _patch = source;
      _isDirty = true;
      _syncPatchTransitionToDevice(previous, source);
    }
    notifyListeners();
  }

  /// Swaps the contents of Compare Slot A and Compare Slot B.
  void swapCompareSlots() {
    final a = _compareSlotA;
    final b = _compareSlotB;
    if (a == null || b == null) return;

    final previous = _patch;
    _compareSlotA = b;
    _compareSlotB = a;

    final nextActive =
        _activeCompareSlot == CompareSlot.a ? _compareSlotA! : _compareSlotB!;
    if (previous != null) {
      _patch = nextActive;
      _syncPatchTransitionToDevice(previous, nextActive);
    }
    notifyListeners();
  }

  /// Computes a structured [PatchDiff] between Compare Slot A and Compare Slot B
  /// (falling back to the current patch if B is not yet initialized).
  PatchDiff? diffAB() {
    final a = _compareSlotA;
    final b = _compareSlotB ?? _patch;
    if (a == null || b == null) return null;
    return PatchDiff.compute(a, b);
  }

  /// Replaces the active editor patch and resets the dirty flag and edit history.
  void loadPatch(Patch patch) {
    _patch = patch;
    _isDirty = false;
    _selectedSlotIndex = 0;
    _errorMessage = null;
    _resetSessionBaseline(patch);
    if (patch.programNumber != null) {
      connectionController.setActiveHardwareSlotIndex(
        patch.programNumber,
        syncEditorPatchProgramNumber: false,
      );
    }
    notifyListeners();
  }

  /// Activates [targetPatch] in the editor and immediately dispatches live
  /// hardware delta updates (used by Live Performance Setlist Mode).
  ///
  /// On Zoom MS Plus (`0x6E`), transmits targeted `64 20 00` slot/parameter/bypass
  /// deltas (never `64 12 01` or `0x45`). On Line 6 Bass POD Pro (`0x0E41`),
  /// transmits `encodePatch`.
  void activatePatchLive(Patch targetPatch, {bool syncHardware = true}) {
    final previous = _patch;
    _patch = targetPatch;
    _isDirty = false;
    _selectedSlotIndex = 0;
    _errorMessage = null;
    _resetSessionBaseline(targetPatch);

    if (syncHardware && transport.isConnected && !_isHandlingIncoming) {
      if (previous != null) {
        _syncPatchTransitionToDevice(previous, targetPatch);
      } else if (connectionController.activeFamily.isLine6BassPodPro) {
        try {
          unawaited(transport.send(protocol.encodePatch(targetPatch)));
        } catch (e) {
          _errorMessage = 'Failed to sync patch to device: $e';
        }
      } else {
        _syncStructureToDevice();
      }
    }
    notifyListeners();
  }

  /// Sets the hardware memory slot index on the active patch without marking it dirty.
  void setHardwareSlotIndex(int slotIndex) {
    if (_patch != null && _patch!.programNumber != slotIndex) {
      _patch = _patch!.copyWith(programNumber: slotIndex);
      notifyListeners();
    }
  }

  /// Changes the inspected slot index and synchronizes hardware focus if connected.
  void selectSlot(int slotIndex) {
    if (_patch != null &&
        slotIndex >= 0 &&
        slotIndex < _patch!.slots.length &&
        _selectedSlotIndex != slotIndex) {
      _selectedSlotIndex = slotIndex;
      notifyListeners();

      if (transport.isConnected && !_isHandlingIncoming) {
        try {
          final msg = protocol.buildSlotFocusMessage(slotIndex);
          if (msg != null) {
            unawaited(transport.send(msg));
          }
        } catch (_) {}
      }
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
      _resetSessionBaseline(decoded);
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

  /// Pulls preset stored at hardware memory slot [slotIndex] (0–99) into the active editor buffer
  /// and updates the connected hardware's active memory slot.
  ///
  /// Single-click responsive: immediately loads cached patch if already available in
  /// [connectionController.bankSlots], avoiding redundant network round-trips and avoiding
  /// overwriting the slot with previous patch state.
  ///
  /// When [notifyHardware] is true (default, triggered by user clicking a slot in the UI),
  /// sends slot switch messages (CC0/CC32/PC) to the pedal.
  /// When [notifyHardware] is false (triggered by incoming hardware events from the physical pedal),
  /// no switch messages are sent back to the pedal, preventing feedback/flopping loops.
  Future<void> loadPatchFromDeviceSlot(int slotIndex, {bool notifyHardware = true}) async {
    if (!transport.isConnected) {
      if (!notifyHardware) {
        connectionController.setActiveHardwareSlotIndex(
          slotIndex,
          syncEditorPatchProgramNumber: false,
        );
        if (_patch != null && _patch!.programNumber != slotIndex) {
          _patch = _patch!.copyWith(programNumber: slotIndex);
        }
        notifyListeners();
        return;
      }
      _errorMessage = 'Cannot load slot $slotIndex: MIDI transport is not connected.';
      notifyListeners();
      return;
    }

    // Always update the tracked active slot index immediately so the UI bank view
    // highlights the pedal's newly selected patch right away.
    connectionController.setActiveHardwareSlotIndex(
      slotIndex,
      syncEditorPatchProgramNumber: false,
    );

    // 1. Check if patch is already cached in local memory (fast path: zero MIDI needed to fetch).
    final cachedSlot =
        (slotIndex >= 0 && slotIndex < connectionController.bankSlots.length)
            ? connectionController.bankSlots[slotIndex]
            : null;

    if (cachedSlot != null && cachedSlot.patch != null) {
      final patchToLoad = cachedSlot.patch!.copyWith(programNumber: slotIndex);
      _isHandlingIncoming = true;
      try {
        loadPatch(patchToLoad);
        connectionController.setActiveHardwareSlotIndex(
          slotIndex,
          syncEditorPatchProgramNumber: false,
        );
      } finally {
        _isHandlingIncoming = false;
      }

      // Send slot switch message(s) to pedal (CC0/CC32/PC) ONLY when initiated by app UI!
      if (notifyHardware) {
        final switchMessages = protocol.buildSlotSelectMessages(slotIndex);
        for (final msg in switchMessages) {
          try {
            await transport.send(msg);
          } catch (_) {}
        }
      }
      return;
    }

    // When switching on physical pedal and the slot isn't cached yet, reflect the
    // new programNumber immediately while fetching the slot/current patch from hardware.
    if (!notifyHardware && _patch != null && _patch!.programNumber != slotIndex) {
      _patch = _patch!.copyWith(programNumber: slotIndex);
      notifyListeners();
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final activeProto = protocol;
      final timeout = notifyHardware
          ? const Duration(seconds: 2)
          : connectionController.currentPatchTimeout;

      MidiMessage? response;
      try {
        final request = activeProto.buildPatchSlotRequest(slotIndex);
        response = await transport.sendSysExAndWait(
          request,
          responseMatcher: (m) =>
              (activeProto.isSlotPatchDump(m) &&
                  activeProto.extractSlotIndex(m) == slotIndex) ||
              (!notifyHardware && activeProto.isCurrentPatchDump(m)),
          timeout: timeout,
        );
      } on TimeoutException {
        response = null;
      } catch (_) {
        if (notifyHardware) rethrow;
        response = null;
      }

      // Hardware fallback for physical pedal switches: request current edit buffer if slot dump didn't answer.
      if (response == null && !notifyHardware && transport.isConnected) {
        try {
          final currentRequest = activeProto.buildCurrentPatchRequest();
          response = await transport.sendSysExAndWait(
            currentRequest,
            responseMatcher: (m) =>
                activeProto.isCurrentPatchDump(m) ||
                (activeProto.isSlotPatchDump(m) &&
                    activeProto.extractSlotIndex(m) == slotIndex),
            timeout: connectionController.currentPatchTimeout,
          );
        } on TimeoutException {
          response = null;
        } catch (_) {
          response = null;
        }
      }

      if (_isDisposed) return;

      if (response == null) {
        if (notifyHardware) {
          throw TimeoutException('Timed out requesting hardware slot $slotIndex');
        }
        return;
      }

      final patchToLoad = activeProto.decodePatch(response).copyWith(programNumber: slotIndex);
      connectionController.updateBankSlot(
        slotIndex,
        patchName: patchToLoad.name.trim().isNotEmpty
            ? patchToLoad.name.trim()
            : 'Slot ${slotIndex.toString().padLeft(2, '0')}',
        patch: patchToLoad,
      );

      // 3. Load patch into active editor buffer without echoing back
      _isHandlingIncoming = true;
      try {
        loadPatch(patchToLoad);
        connectionController.setActiveHardwareSlotIndex(
          slotIndex,
          syncEditorPatchProgramNumber: false,
        );
      } finally {
        _isHandlingIncoming = false;
      }

      // 4. Send slot switch message(s) to pedal (CC0/CC32/PC) ONLY when initiated by app UI!
      if (notifyHardware) {
        final switchMessages = activeProto.buildSlotSelectMessages(slotIndex);
        for (final msg in switchMessages) {
          try {
            await transport.send(msg);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (notifyHardware) {
        _errorMessage = 'Failed to load hardware slot $slotIndex: $e';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets a standardized error message when attempting to write a preset from
  /// an incompatible hardware generation onto the connected pedal.
  void reportCrossGenerationWriteError({
    required DeviceFamily patchDevice,
    required DeviceFamily targetDevice,
  }) {
    _errorMessage =
        'Cannot write ${patchDevice.displayName} patch to ${targetDevice.displayName}: '
        'incompatible hardware generation '
        '(${patchDevice.generation.displayName} vs ${targetDevice.generation.displayName}).';
    notifyListeners();
  }

  /// Writes and saves [patchToSave] (or active patch) to persistent hardware memory slot [slotIndex] (0–99).
  Future<void> savePatchToDeviceSlot(int slotIndex, [Patch? patchToSave]) async {
    final target = patchToSave ?? _patch;
    if (target == null) {
      _errorMessage = 'No patch loaded to save to hardware slot.';
      notifyListeners();
      return;
    }

    final targetFamily = connectionController.activeFamily;
    if (targetFamily != DeviceFamily.unknown &&
        target.deviceFamily != DeviceFamily.unknown &&
        !target.deviceFamily.isSameGeneration(targetFamily)) {
      reportCrossGenerationWriteError(
        patchDevice: target.deviceFamily,
        targetDevice: targetFamily,
      );
      return;
    }

    if (!transport.isConnected) {
      _errorMessage = 'Cannot save to hardware: MIDI transport is not connected.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final activeProto = protocol;
      final saveMessage = activeProto.encodePatch(target, programNumber: slotIndex);

      if (transport is MockMidiTransport) {
        // If mock transport has a registered responder or is in test mode,
        // use sendSysEx or await ACK if a responder matches.
        await transport.sendSysEx(saveMessage);
      } else {
        // Physical hardware: Transmit slot save and await hardware success ACK
        try {
          await transport.sendRequest(
            saveMessage,
            responseMatcher: activeProto.isSuccessAck,
            timeout: const Duration(milliseconds: 2500),
          );
        } on TimeoutException {
          throw StateError(
            'Hardware device did not acknowledge saving to slot $slotIndex within timeout.',
          );
        }
      }

      final updated = target.copyWith(programNumber: slotIndex);
      _patch = updated;
      _isDirty = false;
      connectionController.setActiveHardwareSlotIndex(slotIndex);
      connectionController.updateBankSlot(
        slotIndex,
        patchName: updated.name,
        patch: updated,
      );
    } catch (e) {
      _errorMessage = 'Failed to write patch to slot $slotIndex: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Duplicates the active patch under [newName] without overwriting the original.
  ///
  /// When a [PatchLibraryController] is supplied or bound via [setLibraryController],
  /// persists the duplicated preset to the library before loading it into the editor.
  Future<Patch?> saveCopyAs(
    String newName, {
    PatchLibraryController? libraryController,
  }) async {
    final current = _patch;
    if (current == null) return null;

    final maxLen = connectionController.activeFamily.maxNameLength;
    final trimmed = newName.trim();
    final fallbackName = '${current.name} Copy';
    final rawName = trimmed.isEmpty ? fallbackName : trimmed;
    final resolvedName =
        rawName.length > maxLen ? rawName.substring(0, maxLen).trimRight() : rawName;

    final targetLib = libraryController ?? _libraryController;
    final Patch copy;
    if (targetLib != null) {
      copy = await targetLib.duplicatePatch(current, newName: resolvedName);
    } else {
      final now = DateTime.now();
      copy = Patch(
        id: 'copy_${now.microsecondsSinceEpoch}',
        name: resolvedName,
        deviceFamily: current.deviceFamily,
        programNumber: null,
        slots: current.slots,
        tags: current.tags,
        author: current.author,
        notes: current.notes,
        updatedAt: now,
        metadata: current.metadata,
      );
    }

    loadPatch(copy);
    return copy;
  }

  /// Cancels an active batch hardware bank restore operation.
  void cancelBankRestore() {
    if (_isRestoringBank) {
      _cancelBankRestore = true;
      _bankRestoreStatus = 'Bank restore canceled';
      notifyListeners();
    }
  }

  /// Sequentially writes [patches] to hardware memory slots starting at [startSlotIndex],
  /// verifying per-slot hardware ACKs and reporting incremental progress.
  ///
  /// Returns the number of slots written before completion or cancellation.
  Future<int> restoreBankSlots({
    required List<Patch> patches,
    int startSlotIndex = 0,
    Duration interSlotDelay = const Duration(milliseconds: 10),
  }) async {
    if (!transport.isConnected) {
      _errorMessage = 'Cannot restore hardware bank: MIDI device is not connected.';
      notifyListeners();
      throw StateError(_errorMessage!);
    }
    if (patches.isEmpty) {
      return 0;
    }

    final targetFamily = connectionController.activeFamily;
    final compatiblePatches = patches.where((p) {
      if (targetFamily == DeviceFamily.unknown ||
          p.deviceFamily == DeviceFamily.unknown) {
        return true;
      }
      return p.deviceFamily.isSameGeneration(targetFamily);
    }).toList();

    if (compatiblePatches.isEmpty) {
      _errorMessage =
          'Cannot restore hardware bank: no patches compatible with ${targetFamily.displayName} (${targetFamily.generation.displayName}).';
      notifyListeners();
      return 0;
    }

    final totalMemorySlots = targetFamily.totalMemorySlots;
    final clampedStart = startSlotIndex.clamp(0, totalMemorySlots - 1);
    final availableSlots = totalMemorySlots - clampedStart;
    final count = min(compatiblePatches.length, availableSlots);
    if (count <= 0) {
      return 0;
    }

    _isRestoringBank = true;
    _cancelBankRestore = false;
    _bankRestoreCompletedCount = 0;
    _bankRestoreTotalCount = count;
    _bankRestoreProgress = 0.0;
    _bankRestoreStatus = 'Preparing bank restore ($count slots)...';
    _errorMessage = null;
    notifyListeners();

    try {
      for (int i = 0; i < count; i++) {
        if (_cancelBankRestore || !transport.isConnected) {
          break;
        }

        final targetSlot = clampedStart + i;
        final patch = compatiblePatches[i];
        _bankRestoreStatus =
            'Restoring slot #${targetSlot.toString().padLeft(2, '0')} (${i + 1}/$count): ${patch.name}';
        _bankRestoreProgress = i / count;
        notifyListeners();

        await savePatchToDeviceSlot(targetSlot, patch);
        _bankRestoreCompletedCount = i + 1;
        _bankRestoreProgress = _bankRestoreCompletedCount / count;
        notifyListeners();

        if (interSlotDelay > Duration.zero &&
            i + 1 < count &&
            !_cancelBankRestore) {
          await Future<void>.delayed(interSlotDelay);
        }
      }

      if (_cancelBankRestore) {
        _bankRestoreStatus =
            'Bank restore canceled ($_bankRestoreCompletedCount/$count written)';
      } else {
        _bankRestoreStatus =
            'Restored $_bankRestoreCompletedCount/$count hardware slots';
      }
      return _bankRestoreCompletedCount;
    } catch (e) {
      _errorMessage = 'Batch bank restore failed: $e';
      _bankRestoreStatus = _errorMessage;
      rethrow;
    } finally {
      _isRestoringBank = false;
      notifyListeners();
    }
  }

  /// Updates the active patch name in real-time, enforcing device-specific
  /// character limits and translating invalid/unprintable characters to spaces.
  void updatePatchName(String newName) {
    final current = _patch;
    if (current == null) return;

    final maxLen = connectionController.activeFamily.maxNameLength;

    // Replace unprintable or non-ASCII characters with spaces
    final buffer = StringBuffer();
    for (int i = 0; i < newName.length && buffer.length < maxLen; i++) {
      final code = newName.codeUnitAt(i);
      if (code >= 32 && code <= 126) {
        buffer.writeCharCode(code);
      } else {
        buffer.write(' ');
      }
    }
    final sanitized = buffer.toString();
    if (sanitized == current.name) return;

    final previousDirty = _isDirty;
    _patch = current.copyWith(name: sanitized);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: _selectedSlotIndex,
      previousDirty: previousDirty,
      label: 'Rename Patch',
      coalesceKey: 'patch_name',
    );
    _syncStructureToDevice();
    notifyListeners();
  }

  /// Updates active patch tempo in BPM, clamped to device boundaries (typically 40–250 BPM).
  void updatePatchTempo(int bpm) {
    final current = _patch;
    if (current == null) return;

    final clamped = bpm.clamp(40, 250);
    if (clamped == current.tempo) return;

    final previousDirty = _isDirty;
    final newMetadata = Map<String, dynamic>.from(current.metadata);
    newMetadata['tempo'] = clamped;

    _patch = current.copyWith(metadata: newMetadata);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: _selectedSlotIndex,
      previousDirty: previousDirty,
      label: 'Change Tempo',
      coalesceKey: 'patch_tempo',
    );
    _syncStructureToDevice();
    notifyListeners();
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

    final previousDirty = _isDirty;
    _patch = current.copyWith(slots: newSlots);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: _selectedSlotIndex,
      previousDirty: previousDirty,
      label: updatedSlot.isEnabled
          ? 'Enable ${slot.effectName}'
          : 'Bypass ${slot.effectName}',
    );
    notifyListeners();

    // Dispatch real-time bypass change to hardware if connected
    if (transport.isConnected && !_isHandlingIncoming) {
      try {
        final bypassMsg = protocol.buildSlotBypassMessage(
          slotIndex: slotIndex,
          isEnabled: updatedSlot.isEnabled,
        );
        if (bypassMsg != null) {
          unawaited(transport.send(bypassMsg));
        }
      } catch (e) {
        _errorMessage = 'Failed to transmit bypass edit: $e';
        notifyListeners();
      }
    }
  }

  /// Adds a new effect slot with [effectId] at [index] (or at the end if omitted).
  ///
  /// Respects device maximum slot limits (e.g. 6 slots on Zoom MS Plus) and initializes
  /// default parameter values from [EffectCatalogRegistry]. Returns true if added.
  bool addEffectSlot({int? index, required dynamic effectId}) {
    final current = _patch;
    if (current == null) return false;

    final family = connectionController.activeFamily;
    if (current.slots.length >= family.maxEffectSlots) {
      return false;
    }

    final idString = effectId is int
        ? '0x${effectId.toRadixString(16).padLeft(8, '0').toUpperCase()}'
        : effectId.toString();

    final def = EffectCatalogRegistry.getDefinition(family, idString);
    final newParams = def.parameters.map((desc) {
      return ParameterValue(
        descriptor: desc,
        currentValue: desc.defaultValue.toDouble(),
      );
    }).toList();

    final insertIndex = (index == null || index > current.slots.length)
        ? current.slots.length
        : (index < 0 ? 0 : index);

    final newSlots = List<EffectSlot>.from(current.slots);
    newSlots.insert(
      insertIndex,
      EffectSlot(
        slotIndex: insertIndex,
        effectId: def.effectId,
        effectName: def.name,
        isEnabled: true,
        parameters: newParams,
      ),
    );

    // Re-index slots
    for (int i = 0; i < newSlots.length; i++) {
      newSlots[i] = newSlots[i].copyWith(slotIndex: i);
    }

    final meta = Map<String, dynamic>.from(current.metadata);
    meta['activeEffectSlot'] = insertIndex;

    final previousSlot = _selectedSlotIndex;
    final previousDirty = _isDirty;
    _patch = current.copyWith(slots: newSlots, metadata: meta);
    _isDirty = true;
    _selectedSlotIndex = insertIndex;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: previousSlot,
      previousDirty: previousDirty,
      label: 'Add ${def.name}',
    );
    final affected = [for (int i = insertIndex; i < newSlots.length; i++) i];
    _syncStructureToDevice(affectedSlots: affected);
    notifyListeners();
    return true;
  }

  /// Inserts a new effect slot from [entry] at exact [index] in the signal chain.
  ///
  /// Enforces device maximum slot limits (e.g. 6 slots on Zoom MS Plus), marks the
  /// patch dirty, synchronizes structure to hardware, and sets active selection to [index].
  bool insertEffectSlotAt(int index, EffectCatalogEntry entry) {
    return addEffectSlot(index: index, effectId: entry.effectId);
  }

  /// Removes the effect slot at [slotIndex], preventing invalid states and safely
  /// adjusting [selectedSlotIndex]. Returns true if removed.
  bool removeEffectSlot(int slotIndex) {
    final current = _patch;
    if (current == null ||
        slotIndex < 0 ||
        slotIndex >= current.slots.length) {
      return false;
    }

    // Require at least 1 slot remaining
    if (current.slots.length <= 1) {
      return false;
    }

    final clearedSlotIndex = current.slots.length - 1;
    final removedName = current.slots[slotIndex].effectName;
    final previousSlot = _selectedSlotIndex;
    final previousDirty = _isDirty;
    final newSlots = List<EffectSlot>.from(current.slots);
    newSlots.removeAt(slotIndex);

    // Re-index remaining slots
    for (int i = 0; i < newSlots.length; i++) {
      newSlots[i] = newSlots[i].copyWith(slotIndex: i);
    }

    // Safely adjust selectedSlotIndex
    if (_selectedSlotIndex >= newSlots.length) {
      _selectedSlotIndex = newSlots.length - 1;
    } else if (_selectedSlotIndex > slotIndex) {
      _selectedSlotIndex--;
    }

    final meta = Map<String, dynamic>.from(current.metadata);
    meta['activeEffectSlot'] = _selectedSlotIndex;

    _patch = current.copyWith(slots: newSlots, metadata: meta);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: previousSlot,
      previousDirty: previousDirty,
      label: 'Remove $removedName',
    );
    final affected = [for (int i = slotIndex; i < newSlots.length; i++) i];
    _syncStructureToDevice(
      affectedSlots: affected,
      clearedSlots: [clearedSlotIndex],
    );
    notifyListeners();
    return true;
  }

  /// Moves the effect slot from [oldIndex] to [newIndex] for signal chain reordering.
  /// Returns true if moved.
  bool moveEffectSlot(int oldIndex, int newIndex) {
    final current = _patch;
    if (current == null ||
        oldIndex < 0 ||
        oldIndex >= current.slots.length ||
        newIndex < 0 ||
        newIndex >= current.slots.length) {
      return false;
    }

    if (oldIndex == newIndex) return true;

    final newSlots = List<EffectSlot>.from(current.slots);
    final movedSlot = newSlots.removeAt(oldIndex);
    newSlots.insert(newIndex, movedSlot);

    // Re-index slots
    for (int i = 0; i < newSlots.length; i++) {
      newSlots[i] = newSlots[i].copyWith(slotIndex: i);
    }

    // Adjust selected slot index
    final previousSlot = _selectedSlotIndex;
    final previousDirty = _isDirty;
    if (_selectedSlotIndex == oldIndex) {
      _selectedSlotIndex = newIndex;
    } else if (oldIndex < _selectedSlotIndex && newIndex >= _selectedSlotIndex) {
      _selectedSlotIndex--;
    } else if (oldIndex > _selectedSlotIndex && newIndex <= _selectedSlotIndex) {
      _selectedSlotIndex++;
    }

    final minIdx = min(oldIndex, newIndex);
    final maxIdx = max(oldIndex, newIndex);
    final affected = [for (int i = minIdx; i <= maxIdx; i++) i];

    final meta = Map<String, dynamic>.from(current.metadata);
    meta['activeEffectSlot'] = _selectedSlotIndex;

    _patch = current.copyWith(slots: newSlots, metadata: meta);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: previousSlot,
      previousDirty: previousDirty,
      label: 'Reorder Slots',
    );
    _syncStructureToDevice(affectedSlots: affected);
    notifyListeners();
    return true;
  }

  /// Swaps the effect slots at [indexA] and [indexB], immediately updating local
  /// state and synchronizing the affected slots live to hardware.
  bool swapEffectSlots(int indexA, int indexB) {
    final current = _patch;
    if (current == null ||
        indexA < 0 ||
        indexA >= current.slots.length ||
        indexB < 0 ||
        indexB >= current.slots.length) {
      return false;
    }

    if (indexA == indexB) return true;

    final newSlots = List<EffectSlot>.from(current.slots);
    final temp = newSlots[indexA];
    newSlots[indexA] = newSlots[indexB].copyWith(slotIndex: indexA);
    newSlots[indexB] = temp.copyWith(slotIndex: indexB);

    final previousSlot = _selectedSlotIndex;
    final previousDirty = _isDirty;
    if (_selectedSlotIndex == indexA) {
      _selectedSlotIndex = indexB;
    } else if (_selectedSlotIndex == indexB) {
      _selectedSlotIndex = indexA;
    }

    final meta = Map<String, dynamic>.from(current.metadata);
    meta['activeEffectSlot'] = _selectedSlotIndex;

    _patch = current.copyWith(slots: newSlots, metadata: meta);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: previousSlot,
      previousDirty: previousDirty,
      label: 'Swap Slots',
    );
    _syncStructureToDevice(affectedSlots: [indexA, indexB]);
    notifyListeners();
    return true;
  }

  /// Reorders the signal chain by moving the effect slot at [fromIndex] to insertion
  /// index [toIndex], adjusting the index for items shifted after [fromIndex].
  bool reorderEffectSlots(int fromIndex, int toIndex) {
    final current = _patch;
    if (current == null ||
        fromIndex < 0 ||
        fromIndex >= current.slots.length) {
      return false;
    }

    final targetIndex = fromIndex < toIndex ? toIndex - 1 : toIndex;
    if (targetIndex < 0 || targetIndex >= current.slots.length) {
      return false;
    }
    if (fromIndex == targetIndex) return true;

    return moveEffectSlot(fromIndex, targetIndex);
  }

  /// Swaps the effect algorithm in [slotIndex] using [EffectCatalogRegistry].
  ///
  /// Accepts either integer DSP effect ID or string hex identifier.
  void changeSlotEffect(int slotIndex, dynamic newEffectId) {
    final current = _patch;
    if (current == null ||
        slotIndex < 0 ||
        slotIndex >= current.slots.length) {
      return;
    }

    final idString = newEffectId is int
        ? '0x${newEffectId.toRadixString(16).padLeft(8, '0').toUpperCase()}'
        : newEffectId.toString();

    final family = connectionController.activeFamily;
    final def = EffectCatalogRegistry.getDefinition(family, idString);

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

    final meta = Map<String, dynamic>.from(current.metadata);
    meta['activeEffectSlot'] = _selectedSlotIndex;

    final previousDirty = _isDirty;
    _patch = current.copyWith(slots: newSlots, metadata: meta);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: _selectedSlotIndex,
      previousDirty: previousDirty,
      label: 'Change to ${def.name}',
    );
    _syncStructureToDevice(affectedSlots: [slotIndex]);
    notifyListeners();
  }

  /// Dispatches live edit buffer structural updates to hardware when connected via 64 20 00 opcodes.
  void _syncStructureToDevice({List<int>? affectedSlots, List<int>? clearedSlots}) {
    if (!transport.isConnected || _isHandlingIncoming) return;
    final current = _patch;
    if (current == null) return;

    _isSyncingStructure = true;
    try {
      final slotsToSync = affectedSlots ?? List.generate(current.slots.length, (i) => i);
      for (final slotIdx in slotsToSync) {
        if (slotIdx >= 0 && slotIdx < current.slots.length) {
          final slot = current.slots[slotIdx];
          final messages = protocol.buildSlotSyncSequence(slotIdx, slot);
          for (final msg in messages) {
            transport.send(msg);
          }
        }
      }

      if (clearedSlots != null) {
        for (final clearedIdx in clearedSlots) {
          final clearMsg = protocol.buildEffectTypeMessage(clearedIdx, 0);
          if (clearMsg != null) {
            transport.send(clearMsg);
          }
          final bypassMsg = protocol.buildSlotBypassMessage(
            slotIndex: clearedIdx,
            isEnabled: false,
          );
          if (bypassMsg != null) {
            transport.send(bypassMsg);
          }
        }
      }

      // Update hardware slot focus cursor
      final focusMsg = protocol.buildSlotFocusMessage(_selectedSlotIndex);
      if (focusMsg != null) {
        transport.send(focusMsg);
      }
    } catch (e) {
      _errorMessage = 'Failed to sync patch structure to device: $e';
    } finally {
      _isSyncingStructure = false;
    }
  }

  /// Synchronizes an Undo/Redo or A/B transition from [fromPatch] to [targetPatch]
  /// to connected hardware.
  ///
  /// On Zoom MS Plus (`0x6E`), dispatches targeted `64 20 00` slot/parameter/bypass
  /// deltas (never `64 12 01`). On Line 6 Bass POD Pro (`0x0E41`), dispatches
  /// `encodePatch`.
  void _syncPatchTransitionToDevice(Patch fromPatch, Patch targetPatch) {
    if (!transport.isConnected || _isHandlingIncoming) return;

    if (connectionController.activeFamily.isLine6BassPodPro) {
      try {
        final dump = protocol.encodePatch(targetPatch);
        unawaited(transport.send(dump));
      } catch (e) {
        _errorMessage = 'Failed to sync patch transition to device: $e';
      }
      return;
    }

    _isSyncingStructure = true;
    try {
      for (int i = 0; i < targetPatch.slots.length; i++) {
        final targetSlot = targetPatch.slots[i];
        if (i >= fromPatch.slots.length ||
            fromPatch.slots[i].effectId != targetSlot.effectId) {
          final messages = protocol.buildSlotSyncSequence(i, targetSlot);
          for (final msg in messages) {
            transport.send(msg);
          }
        } else {
          final fromSlot = fromPatch.slots[i];
          if (fromSlot.isEnabled != targetSlot.isEnabled) {
            final bypassMsg = protocol.buildSlotBypassMessage(
              slotIndex: i,
              isEnabled: targetSlot.isEnabled,
            );
            if (bypassMsg != null) {
              transport.send(bypassMsg);
            }
          }
          final paramCount = min(
            fromSlot.parameters.length,
            targetSlot.parameters.length,
          );
          for (int p = 0; p < paramCount; p++) {
            final prevVal = fromSlot.parameters[p].currentValue;
            final nextVal = targetSlot.parameters[p].currentValue;
            if ((prevVal - nextVal).abs() > 0.05) {
              final editMsg = protocol.buildParameterEditMessage(
                slotIndex: i,
                paramIndex: p,
                value: nextVal.round(),
              );
              transport.send(editMsg);
            }
          }
        }
      }

      for (int clearedIdx = targetPatch.slots.length;
          clearedIdx < fromPatch.slots.length;
          clearedIdx++) {
        final clearMsg = protocol.buildEffectTypeMessage(clearedIdx, 0);
        if (clearMsg != null) {
          transport.send(clearMsg);
        }
        final bypassMsg = protocol.buildSlotBypassMessage(
          slotIndex: clearedIdx,
          isEnabled: false,
        );
        if (bypassMsg != null) {
          transport.send(bypassMsg);
        }
      }

      final focusMsg = protocol.buildSlotFocusMessage(_selectedSlotIndex);
      if (focusMsg != null) {
        transport.send(focusMsg);
      }
    } catch (e) {
      _errorMessage = 'Failed to sync patch transition to device: $e';
    } finally {
      _isSyncingStructure = false;
    }
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
    if (param.currentValue == newValue.toDouble()) {
      return;
    }

    final updatedParam = param.copyWith(currentValue: newValue.toDouble());
    final newParams = List<ParameterValue>.from(slot.parameters);
    newParams[paramIndex] = updatedParam;

    final updatedSlot = slot.copyWith(parameters: newParams);
    final newSlots = List<EffectSlot>.from(current.slots);
    newSlots[slotIndex] = updatedSlot;

    final previousDirty = _isDirty;
    _patch = current.copyWith(slots: newSlots);
    _isDirty = true;
    _recordUserEdit(
      previousPatch: current,
      previousSelectedSlot: _selectedSlotIndex,
      previousDirty: previousDirty,
      label: 'Adjust ${param.descriptor.name}',
      coalesceKey: 'param_${slotIndex}_$paramIndex',
    );
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

  /// Applies unsolicited incoming hardware events (parameter tweaks, bypass changes,
  /// patch dump, slot focus changes, or program change) directly to the local model state WITHOUT
  /// echoing the SysEx message back to hardware (preventing MIDI feedback loops).
  void applyExternalHardwareUpdate({
    int? slotIndex,
    int? paramIndex,
    int? value,
    int? programNumber,
    Patch? patch,
    bool? isEnabled,
  }) {
    // Echo / ACK Safeguard: Do not process echoed feedback during an in-flight structural burst
    if (_isSyncingStructure) return;

    if (patch != null) {
      final prog = patch.programNumber ??
          connectionController.activeHardwareSlotIndex ??
          _patch?.programNumber;
      final resolved = prog != null ? patch.copyWith(programNumber: prog) : patch;
      _patch = resolved;
      _isDirty = false;
      _selectedSlotIndex = 0;
      _errorMessage = null;
      _resetSessionBaseline(resolved);
      if (prog != null) {
        connectionController.setActiveHardwareSlotIndex(
          prog,
          syncEditorPatchProgramNumber: false,
        );
      }
      notifyListeners();
      return;
    }

    if (programNumber != null) {
      connectionController.setActiveHardwareSlotIndex(
        programNumber,
        syncEditorPatchProgramNumber: false,
      );
      if (connectionController.isConnected) {
        // Hardware-initiated patch change: notifyHardware MUST be false to avoid echo loops
        unawaited(loadPatchFromDeviceSlot(programNumber, notifyHardware: false));
      } else {
        if (_patch != null) {
          _patch = _patch!.copyWith(programNumber: programNumber);
        }
        notifyListeners();
      }
      return;
    }

    final current = _patch;
    if (current == null || slotIndex == null || slotIndex < 0 || slotIndex >= current.slots.length) {
      return;
    }

    _isHandlingIncoming = true;
    try {
      // Always track hardware effect slot focus (e.g. Left/Right pedal buttons or slot-specific tweaks)
      if (_selectedSlotIndex != slotIndex) {
        _selectedSlotIndex = slotIndex;
        notifyListeners();
      }

      final slot = current.slots[slotIndex];

      if (isEnabled != null && slot.isEnabled != isEnabled) {
        final updatedSlot = slot.copyWith(isEnabled: isEnabled);
        final newSlots = List<EffectSlot>.from(current.slots);
        newSlots[slotIndex] = updatedSlot;
        _patch = current.copyWith(slots: newSlots);
        notifyListeners();
      }

      if (paramIndex != null && value != null) {
        if (paramIndex >= 0 && paramIndex < slot.parameters.length) {
          final param = slot.parameters[paramIndex];
          final updatedParam = param.copyWith(currentValue: value.toDouble());
          final newParams = List<ParameterValue>.from(slot.parameters);
          newParams[paramIndex] = updatedParam;
          final updatedSlot = slot.copyWith(parameters: newParams);
          final newSlots = List<EffectSlot>.from(current.slots);
          newSlots[slotIndex] = updatedSlot;
          _patch = current.copyWith(slots: newSlots);
          notifyListeners();
        }
      }
    } finally {
      _isHandlingIncoming = false;
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    connectionController.setEditorController(null);
    _midiSubscription?.cancel();
    super.dispose();
  }
}

