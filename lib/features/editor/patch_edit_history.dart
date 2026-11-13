import '../../models/patch.dart';

/// Active slot in A/B tone comparison mode.
enum CompareSlot { a, b }

/// Immutable snapshot stored in the editor Undo/Redo history stack.
class PatchHistoryEntry {
  final Patch patch;
  final int selectedSlotIndex;
  final bool isDirty;
  final String label;
  final String? coalesceKey;
  final DateTime timestamp;

  const PatchHistoryEntry({
    required this.patch,
    required this.selectedSlotIndex,
    required this.isDirty,
    required this.label,
    this.coalesceKey,
    required this.timestamp,
  });

  PatchHistoryEntry withTimestamp(DateTime newTimestamp, {String? newLabel}) {
    return PatchHistoryEntry(
      patch: patch,
      selectedSlotIndex: selectedSlotIndex,
      isDirty: isDirty,
      label: newLabel ?? label,
      coalesceKey: coalesceKey,
      timestamp: newTimestamp,
    );
  }
}

class _PendingGesture {
  final Patch preGesturePatch;
  final int preGestureSlotIndex;
  final bool preGestureDirty;
  final String label;

  const _PendingGesture({
    required this.preGesturePatch,
    required this.preGestureSlotIndex,
    required this.preGestureDirty,
    required this.label,
  });
}

/// Bounded Undo/Redo snapshot history supporting both explicit gesture
/// transactions (e.g. rotary knob drags) and time-window coalescing
/// (e.g. scroll wheel sweeps, tempo slider, or patch name typing).
class PatchEditHistory {
  static const int defaultMaxEntries = 50;
  static const Duration defaultCoalesceWindow = Duration(milliseconds: 600);

  final int maxEntries;
  final Duration coalesceWindow;
  final DateTime Function() _now;

  final List<PatchHistoryEntry> _undoStack = [];
  final List<PatchHistoryEntry> _redoStack = [];
  _PendingGesture? _pendingGesture;

  PatchEditHistory({
    this.maxEntries = defaultMaxEntries,
    this.coalesceWindow = defaultCoalesceWindow,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;
  bool get isGestureActive => _pendingGesture != null;

  String? get undoLabel => _undoStack.isNotEmpty ? _undoStack.last.label : null;
  String? get redoLabel => _redoStack.isNotEmpty ? _redoStack.last.label : null;

  /// Starts an explicit edit gesture (such as a continuous rotary knob drag),
  /// capturing [preGesturePatch] once so intermediate drag ticks do not
  /// flood the undo stack.
  void beginGesture({
    required Patch preGesturePatch,
    required int selectedSlotIndex,
    required bool isDirty,
    required String label,
  }) {
    _pendingGesture = _PendingGesture(
      preGesturePatch: preGesturePatch,
      preGestureSlotIndex: selectedSlotIndex,
      preGestureDirty: isDirty,
      label: label,
    );
  }

  /// Completes an active gesture, pushing a single undo entry if [finalPatch]
  /// differs from the pre-gesture snapshot.
  bool commitGesture(Patch? finalPatch) {
    final pending = _pendingGesture;
    _pendingGesture = null;
    if (pending == null || finalPatch == null) return false;
    if (finalPatch == pending.preGesturePatch) return false;

    _pushUndoEntry(
      PatchHistoryEntry(
        patch: pending.preGesturePatch,
        selectedSlotIndex: pending.preGestureSlotIndex,
        isDirty: pending.preGestureDirty,
        label: pending.label,
        timestamp: _now(),
      ),
    );
    return true;
  }

  /// Cancels any pending gesture without recording an undo entry.
  void cancelGesture() {
    _pendingGesture = null;
  }

  /// Records an edit transition from [previousPatch].
  ///
  /// When an explicit gesture is active, intermediate updates are skipped
  /// because [commitGesture] records the whole gesture on completion.
  void recordEdit({
    required Patch previousPatch,
    required int previousSelectedSlot,
    required bool previousDirty,
    required String label,
    String? coalesceKey,
  }) {
    if (_pendingGesture != null) {
      return;
    }

    final timestamp = _now();
    _redoStack.clear();

    if (coalesceKey != null && _undoStack.isNotEmpty) {
      final top = _undoStack.last;
      if (top.coalesceKey == coalesceKey &&
          timestamp.difference(top.timestamp) <= coalesceWindow) {
        _undoStack[_undoStack.length - 1] = top.withTimestamp(
          timestamp,
          newLabel: label,
        );
        return;
      }
    }

    _pushUndoEntry(
      PatchHistoryEntry(
        patch: previousPatch,
        selectedSlotIndex: previousSelectedSlot,
        isDirty: previousDirty,
        label: label,
        coalesceKey: coalesceKey,
        timestamp: timestamp,
      ),
    );
  }

  void _pushUndoEntry(PatchHistoryEntry entry) {
    _redoStack.clear();
    _undoStack.add(entry);
    while (_undoStack.length > maxEntries) {
      _undoStack.removeAt(0);
    }
  }

  /// Pops the most recent undo entry and pushes the current state to redo.
  PatchHistoryEntry? undo({
    required Patch currentPatch,
    required int currentSelectedSlot,
    required bool currentDirty,
  }) {
    _pendingGesture = null;
    if (_undoStack.isEmpty) return null;

    final entry = _undoStack.removeLast();
    _redoStack.add(
      PatchHistoryEntry(
        patch: currentPatch,
        selectedSlotIndex: currentSelectedSlot,
        isDirty: currentDirty,
        label: entry.label,
        timestamp: _now(),
      ),
    );
    return entry;
  }

  /// Pops the most recent redo entry and pushes the current state to undo.
  PatchHistoryEntry? redo({
    required Patch currentPatch,
    required int currentSelectedSlot,
    required bool currentDirty,
  }) {
    _pendingGesture = null;
    if (_redoStack.isEmpty) return null;

    final entry = _redoStack.removeLast();
    _undoStack.add(
      PatchHistoryEntry(
        patch: currentPatch,
        selectedSlotIndex: currentSelectedSlot,
        isDirty: currentDirty,
        label: entry.label,
        timestamp: _now(),
      ),
    );
    return entry;
  }

  /// Clears all undo/redo entries and any pending gesture.
  void reset() {
    _undoStack.clear();
    _redoStack.clear();
    _pendingGesture = null;
  }
}

