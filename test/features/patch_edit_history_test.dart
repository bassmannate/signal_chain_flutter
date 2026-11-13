import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/features/editor/patch_edit_history.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/patch.dart';

void main() {
  Patch makePatch(String name) => Patch(
        id: 'p_$name',
        name: name,
        deviceFamily: DeviceFamily.zoomMs60bPlus,
      );

  group('PatchEditHistory', () {
    test('pushes, undoes, redoes, and clears redo stack on new edit', () {
      final history = PatchEditHistory();
      final p0 = makePatch('Zero');
      final p1 = makePatch('One');
      final p2 = makePatch('Two');

      history.recordEdit(
        previousPatch: p0,
        previousSelectedSlot: 0,
        previousDirty: false,
        label: 'Edit 1',
      );
      history.recordEdit(
        previousPatch: p1,
        previousSelectedSlot: 1,
        previousDirty: true,
        label: 'Edit 2',
      );

      expect(history.canUndo, isTrue);
      expect(history.undoCount, equals(2));

      final undo1 = history.undo(
        currentPatch: p2,
        currentSelectedSlot: 2,
        currentDirty: true,
      );
      expect(undo1?.patch.name, equals('One'));
      expect(undo1?.selectedSlotIndex, equals(1));
      expect(undo1?.isDirty, isTrue);
      expect(history.canRedo, isTrue);

      final undo2 = history.undo(
        currentPatch: p1,
        currentSelectedSlot: 1,
        currentDirty: true,
      );
      expect(undo2?.patch.name, equals('Zero'));
      expect(undo2?.isDirty, isFalse);
      expect(history.canUndo, isFalse);

      final redo1 = history.redo(
        currentPatch: p0,
        currentSelectedSlot: 0,
        currentDirty: false,
      );
      expect(redo1?.patch.name, equals('One'));

      // New edit clears redo stack
      history.recordEdit(
        previousPatch: p1,
        previousSelectedSlot: 1,
        previousDirty: true,
        label: 'Branch',
      );
      expect(history.canRedo, isFalse);
    });

    test('coalesces rapid edits with same coalesceKey inside window', () {
      var currentTime = DateTime(2026, 11, 12, 12, 0, 0);
      final history = PatchEditHistory(
        coalesceWindow: const Duration(milliseconds: 600),
        now: () => currentTime,
      );

      final p0 = makePatch('Start');
      final p1 = makePatch('Tick1');
      final p2 = makePatch('Tick2');

      history.recordEdit(
        previousPatch: p0,
        previousSelectedSlot: 0,
        previousDirty: false,
        label: 'Adjust Gain',
        coalesceKey: 'param_0_0',
      );

      currentTime = currentTime.add(const Duration(milliseconds: 200));
      history.recordEdit(
        previousPatch: p1,
        previousSelectedSlot: 0,
        previousDirty: true,
        label: 'Adjust Gain',
        coalesceKey: 'param_0_0',
      );

      expect(history.undoCount, equals(1));
      final undone = history.undo(
        currentPatch: p2,
        currentSelectedSlot: 0,
        currentDirty: true,
      );
      expect(undone?.patch.name, equals('Start'));

      // Outside coalesce window starts a new entry
      currentTime = currentTime.add(const Duration(milliseconds: 800));
      history.recordEdit(
        previousPatch: p0,
        previousSelectedSlot: 0,
        previousDirty: false,
        label: 'Adjust Gain',
        coalesceKey: 'param_0_0',
      );
      currentTime = currentTime.add(const Duration(milliseconds: 800));
      history.recordEdit(
        previousPatch: p1,
        previousSelectedSlot: 0,
        previousDirty: true,
        label: 'Adjust Gain',
        coalesceKey: 'param_0_0',
      );
      expect(history.undoCount, equals(2));
    });

    test('explicit gesture collapses intermediate edits and skips no-op gestures', () {
      final history = PatchEditHistory();
      final p0 = makePatch('PreDrag');
      final p1 = makePatch('MidDrag');
      final p2 = makePatch('PostDrag');

      history.beginGesture(
        preGesturePatch: p0,
        selectedSlotIndex: 0,
        isDirty: false,
        label: 'Drag Knob',
      );
      history.recordEdit(
        previousPatch: p0,
        previousSelectedSlot: 0,
        previousDirty: false,
        label: 'Ignored',
      );
      history.recordEdit(
        previousPatch: p1,
        previousSelectedSlot: 0,
        previousDirty: true,
        label: 'Ignored',
      );
      expect(history.undoCount, equals(0));

      expect(history.commitGesture(p2), isTrue);
      expect(history.undoCount, equals(1));

      // No-op gesture does not push
      history.beginGesture(
        preGesturePatch: p2,
        selectedSlotIndex: 0,
        isDirty: true,
        label: 'NoOp',
      );
      expect(history.commitGesture(p2), isFalse);
      expect(history.undoCount, equals(1));
    });

    test('enforces maxEntries bound by evicting oldest entries', () {
      final history = PatchEditHistory(maxEntries: 3);
      for (int i = 0; i < 5; i++) {
        history.recordEdit(
          previousPatch: makePatch('P$i'),
          previousSelectedSlot: 0,
          previousDirty: true,
          label: 'Edit $i',
        );
      }
      expect(history.undoCount, equals(3));
      final top = history.undo(
        currentPatch: makePatch('Final'),
        currentSelectedSlot: 0,
        currentDirty: true,
      );
      expect(top?.patch.name, equals('P4'));
    });
  });
}

