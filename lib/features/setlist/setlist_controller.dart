import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/midi/midi_message.dart';
import '../../core/midi/midi_transport.dart';
import '../../core/storage/setlist_repository.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../models/setlist.dart';
import '../connection/device_connection_controller.dart';
import '../editor/patch_editor_controller.dart';
import '../library/patch_library_controller.dart';

/// Optional incoming MIDI foot-controller trigger settings for Stage Mode.
@immutable
class MidiFootControllerConfig {
  final bool enableProgramChangeSelect;
  final int? nextStepCcNumber;
  final int? prevStepCcNumber;

  const MidiFootControllerConfig({
    this.enableProgramChangeSelect = false,
    this.nextStepCcNumber,
    this.prevStepCcNumber,
  });

  MidiFootControllerConfig copyWith({
    bool? enableProgramChangeSelect,
    int? nextStepCcNumber,
    bool clearNextStepCc = false,
    int? prevStepCcNumber,
    bool clearPrevStepCc = false,
  }) {
    return MidiFootControllerConfig(
      enableProgramChangeSelect:
          enableProgramChangeSelect ?? this.enableProgramChangeSelect,
      nextStepCcNumber:
          clearNextStepCc ? null : (nextStepCcNumber ?? this.nextStepCcNumber),
      prevStepCcNumber:
          clearPrevStepCc ? null : (prevStepCcNumber ?? this.prevStepCcNumber),
    );
  }
}

/// Controller managing ordered live performance [Setlist]s, stage-mode stepping,
/// immediate hardware patch activation, and optional MIDI foot-controller triggers.
class SetlistController extends ChangeNotifier {
  final SetlistRepository repository;
  final PatchLibraryController libraryController;
  final PatchEditorController editorController;
  final DeviceConnectionController connectionController;
  final MidiTransport transport;
  final DateTime Function() _nowProvider;

  List<Setlist> _setlists = [];
  String? _activeSetlistId;
  int _activeEntryIndex = 0;
  bool _isPerformanceModeActive = false;
  bool _wrapAroundNavigation = false;
  bool _isLoading = false;
  String? _warningMessage;
  String? _errorMessage;
  MidiFootControllerConfig _midiConfig = const MidiFootControllerConfig();

  StreamSubscription<MidiMessage>? _midiSubscription;
  DateTime? _lastFootTriggerAt;
  static const Duration _footTriggerDebounce = Duration(milliseconds: 200);

  SetlistController({
    required this.repository,
    required this.libraryController,
    required this.editorController,
    required this.connectionController,
    required this.transport,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now {
    _midiSubscription = transport.onMessageReceived.listen(_handleIncomingMidi);
  }

  List<Setlist> get setlists => List.unmodifiable(_setlists);
  String? get activeSetlistId => _activeSetlistId;
  int get activeEntryIndex => _activeEntryIndex;
  bool get isPerformanceModeActive => _isPerformanceModeActive;
  bool get wrapAroundNavigation => _wrapAroundNavigation;
  bool get isLoading => _isLoading;
  String? get warningMessage => _warningMessage;
  String? get errorMessage => _errorMessage;
  MidiFootControllerConfig get midiConfig => _midiConfig;

  Setlist? get activeSetlist {
    if (_activeSetlistId == null) return null;
    for (final s in _setlists) {
      if (s.id == _activeSetlistId) return s;
    }
    return null;
  }

  SetlistEntry? get activeEntry {
    final current = activeSetlist;
    if (current == null ||
        _activeEntryIndex < 0 ||
        _activeEntryIndex >= current.entries.length) {
      return null;
    }
    return current.entries[_activeEntryIndex];
  }

  SetlistEntry? get nextPreviewEntry {
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) return null;
    final nextIdx = _activeEntryIndex + 1;
    if (nextIdx < current.entries.length) {
      return current.entries[nextIdx];
    }
    if (_wrapAroundNavigation && current.entries.length > 1) {
      return current.entries.first;
    }
    return null;
  }

  bool get canStepPrevious {
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) return false;
    return _wrapAroundNavigation || _activeEntryIndex > 0;
  }

  bool get canStepNext {
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) return false;
    return _wrapAroundNavigation ||
        _activeEntryIndex < current.entries.length - 1;
  }

  /// Resolves a [Patch] from [libraryController] by [patchId], or null if deleted.
  Patch? resolvePatchForEntry(SetlistEntry entry) {
    for (final p in libraryController.patches) {
      if (p.id == entry.patchId) return p;
    }
    return null;
  }

  /// Loads all persisted setlists from [repository].
  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _setlists = await repository.getAllSetlists();
      if (_activeSetlistId == null && _setlists.isNotEmpty) {
        _activeSetlistId = _setlists.first.id;
      } else if (_activeSetlistId != null && activeSetlist == null) {
        _activeSetlistId = _setlists.isNotEmpty ? _setlists.first.id : null;
      }
      _clampEntryIndex();
    } catch (e) {
      _errorMessage = 'Failed to load setlists: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Setlist> createSetlist(String name, {String? notes}) async {
    final trimmed = name.trim().isEmpty ? 'New Setlist' : name.trim();
    final now = _nowProvider();
    final setlist = Setlist(
      id: 'setlist_${now.microsecondsSinceEpoch}',
      name: trimmed,
      notes: notes,
      updatedAt: now,
    );
    await repository.saveSetlist(setlist);
    await refresh();
    _activeSetlistId = setlist.id;
    _activeEntryIndex = 0;
    notifyListeners();
    return setlist;
  }

  Future<void> renameSetlist(String setlistId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final target = _findSetlistById(setlistId);
    if (target == null) return;
    await repository.saveSetlist(
      target.copyWith(name: trimmed, updatedAt: _nowProvider()),
    );
    await refresh();
  }

  Future<void> deleteSetlist(String setlistId) async {
    await repository.deleteSetlist(setlistId);
    if (_activeSetlistId == setlistId) {
      _activeSetlistId = null;
      _activeEntryIndex = 0;
    }
    await refresh();
  }

  void selectSetlist(String setlistId) {
    if (_findSetlistById(setlistId) == null) return;
    _activeSetlistId = setlistId;
    _activeEntryIndex = 0;
    _warningMessage = null;
    notifyListeners();
  }

  Future<void> addPatchToSetlist(
    String setlistId,
    Patch patch, {
    String? songTitle,
    String? performanceNotes,
    int? tempoOverride,
  }) async {
    final target = _findSetlistById(setlistId);
    if (target == null) return;

    final now = _nowProvider();
    final entry = SetlistEntry(
      id: 'entry_${now.microsecondsSinceEpoch}_${target.entries.length}',
      patchId: patch.id,
      songTitle: songTitle,
      performanceNotes: performanceNotes,
      tempoOverride: tempoOverride?.clamp(40, 250),
    );
    final updated = target.copyWith(
      entries: [...target.entries, entry],
      updatedAt: now,
    );
    await repository.saveSetlist(updated);
    await refresh();
  }

  Future<void> updateEntry(String setlistId, SetlistEntry updatedEntry) async {
    final target = _findSetlistById(setlistId);
    if (target == null) return;
    final nextEntries = target.entries
        .map((e) => e.id == updatedEntry.id ? updatedEntry : e)
        .toList();
    await repository.saveSetlist(
      target.copyWith(entries: nextEntries, updatedAt: _nowProvider()),
    );
    await refresh();
  }

  Future<void> removeEntry(String setlistId, int index) async {
    final target = _findSetlistById(setlistId);
    if (target == null || index < 0 || index >= target.entries.length) return;
    final nextEntries = List<SetlistEntry>.from(target.entries)..removeAt(index);
    await repository.saveSetlist(
      target.copyWith(entries: nextEntries, updatedAt: _nowProvider()),
    );
    if (_activeSetlistId == setlistId && _activeEntryIndex >= nextEntries.length) {
      _activeEntryIndex = nextEntries.isEmpty ? 0 : nextEntries.length - 1;
    }
    await refresh();
  }

  Future<void> reorderEntries(
    String setlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final target = _findSetlistById(setlistId);
    if (target == null ||
        oldIndex < 0 ||
        oldIndex >= target.entries.length ||
        newIndex < 0 ||
        newIndex >= target.entries.length ||
        oldIndex == newIndex) {
      return;
    }
    final nextEntries = List<SetlistEntry>.from(target.entries);
    final moved = nextEntries.removeAt(oldIndex);
    nextEntries.insert(newIndex, moved);
    await repository.saveSetlist(
      target.copyWith(entries: nextEntries, updatedAt: _nowProvider()),
    );
    if (_activeSetlistId == setlistId) {
      if (_activeEntryIndex == oldIndex) {
        _activeEntryIndex = newIndex;
      } else if (oldIndex < _activeEntryIndex && newIndex >= _activeEntryIndex) {
        _activeEntryIndex--;
      } else if (oldIndex > _activeEntryIndex && newIndex <= _activeEntryIndex) {
        _activeEntryIndex++;
      }
    }
    await refresh();
  }

  void setPerformanceModeActive(bool active) {
    if (_isPerformanceModeActive == active) return;
    _isPerformanceModeActive = active;
    if (active && activeSetlist != null && activeSetlist!.entries.isNotEmpty) {
      selectEntryAt(_activeEntryIndex);
    } else {
      notifyListeners();
    }
  }

  void togglePerformanceMode() =>
      setPerformanceModeActive(!_isPerformanceModeActive);

  void setWrapAroundNavigation(bool wrap) {
    if (_wrapAroundNavigation != wrap) {
      _wrapAroundNavigation = wrap;
      notifyListeners();
    }
  }

  void updateMidiConfig(MidiFootControllerConfig config) {
    _midiConfig = config;
    notifyListeners();
  }

  void clearWarning() {
    if (_warningMessage != null) {
      _warningMessage = null;
      notifyListeners();
    }
  }

  /// Selects entry [index] in [activeSetlist] and dispatches live hardware update.
  Future<void> selectEntryAt(int index) async {
    final current = activeSetlist;
    if (current == null ||
        current.entries.isEmpty ||
        index < 0 ||
        index >= current.entries.length) {
      return;
    }

    _activeEntryIndex = index;
    _warningMessage = null;
    final entry = current.entries[index];
    final basePatch = resolvePatchForEntry(entry);

    if (basePatch == null) {
      _warningMessage =
          'Missing preset "${entry.songTitle ?? entry.patchId}" — skipped hardware update.';
      notifyListeners();
      return;
    }

    var targetPatch = basePatch;
    if (entry.tempoOverride != null) {
      final meta = Map<String, dynamic>.from(basePatch.metadata);
      meta['tempo'] = entry.tempoOverride!.clamp(40, 250);
      targetPatch = basePatch.copyWith(metadata: meta);
    }

    final connectedFamily = connectionController.activeFamily;
    final isConnected = transport.isConnected;
    final isCompatible = _isCompatibleDevice(targetPatch.deviceFamily, connectedFamily);

    if (isConnected && !isCompatible) {
      _warningMessage =
          'Device mismatch (${targetPatch.deviceFamily.displayName} vs ${connectedFamily.displayName}) — hardware send skipped.';
      editorController.activatePatchLive(targetPatch, syncHardware: false);
    } else {
      if (!isConnected && targetPatch.deviceFamily != DeviceFamily.unknown) {
        connectionController.selectDeviceFamily(targetPatch.deviceFamily);
      }
      editorController.activatePatchLive(targetPatch, syncHardware: true);
    }
    notifyListeners();
  }

  Future<void> nextEntry() async {
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) return;
    if (_activeEntryIndex + 1 < current.entries.length) {
      await selectEntryAt(_activeEntryIndex + 1);
    } else if (_wrapAroundNavigation) {
      await selectEntryAt(0);
    }
  }

  Future<void> previousEntry() async {
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) return;
    if (_activeEntryIndex - 1 >= 0) {
      await selectEntryAt(_activeEntryIndex - 1);
    } else if (_wrapAroundNavigation) {
      await selectEntryAt(current.entries.length - 1);
    }
  }

  void _handleIncomingMidi(MidiMessage message) {
    if (!_isPerformanceModeActive) return;
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) return;

    final now = _nowProvider();
    if (_lastFootTriggerAt != null &&
        now.difference(_lastFootTriggerAt!) < _footTriggerDebounce) {
      return;
    }

    if (_midiConfig.enableProgramChangeSelect &&
        message.isProgramChange &&
        message.data.length >= 2) {
      final pc = message.data[1] & 0x7F;
      if (pc < current.entries.length) {
        _lastFootTriggerAt = now;
        unawaited(selectEntryAt(pc));
      }
      return;
    }

    if (message.isControlChange && message.data.length >= 3) {
      final ccNum = message.data[1] & 0x7F;
      final ccVal = message.data[2] & 0x7F;
      if (ccVal < 64) return;
      if (_midiConfig.nextStepCcNumber != null &&
          ccNum == _midiConfig.nextStepCcNumber) {
        _lastFootTriggerAt = now;
        unawaited(nextEntry());
      } else if (_midiConfig.prevStepCcNumber != null &&
          ccNum == _midiConfig.prevStepCcNumber) {
        _lastFootTriggerAt = now;
        unawaited(previousEntry());
      }
    }
  }

  static bool _isCompatibleDevice(DeviceFamily patchFamily, DeviceFamily active) {
    if (patchFamily == active) return true;
    if (patchFamily.isZoomMsPlus && active.isZoomMsPlus) return true;
    return false;
  }

  Setlist? _findSetlistById(String id) {
    for (final s in _setlists) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _clampEntryIndex() {
    final current = activeSetlist;
    if (current == null || current.entries.isEmpty) {
      _activeEntryIndex = 0;
    } else if (_activeEntryIndex >= current.entries.length) {
      _activeEntryIndex = current.entries.length - 1;
    }
  }

  @override
  void dispose() {
    _midiSubscription?.cancel();
    super.dispose();
  }
}

