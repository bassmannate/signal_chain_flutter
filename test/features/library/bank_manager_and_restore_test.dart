@Timeout(Duration(seconds: 10))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_metadata_header_widget.dart';
import 'package:signal_chain_flutter/features/library/bank_manager_dialog.dart';
import 'package:signal_chain_flutter/features/library/bank_restore_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  const zoomPort = MidiPortDescriptor(
    id: 'mock_zoom',
    name: 'ZOOM MS-60B+ MIDI',
    manufacturer: 'ZOOM',
    isInput: true,
    isOutput: true,
  );

  const zoomPatchA = Patch(
    id: 'lib_zoom_a',
    name: 'SlapFunk',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    tags: ['funk', 'slap'],
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [],
      ),
    ],
    metadata: {'tempo': 115},
  );

  const zoomPatchB = Patch(
    id: 'lib_zoom_b',
    name: 'WarmSVT',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    tags: ['rock'],
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [],
      ),
    ],
    metadata: {'tempo': 96},
  );

  const podPatch = Patch(
    id: 'lib_pod_1',
    name: 'PodDrive',
    deviceFamily: DeviceFamily.line6BassPodPro,
    tags: ['drive'],
    slots: [],
    metadata: {'tempo': 120},
  );

  const zoom50gPatch = Patch(
    id: 'lib_zoom_50g',
    name: 'Ms50Crunch',
    deviceFamily: DeviceFamily.zoomMs50gPlus,
    tags: ['guitar'],
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [],
      ),
    ],
    metadata: {'tempo': 110},
  );

  const hwSlotPatch0 = Patch(
    id: 'hw_slot_0',
    name: 'HwClean',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    programNumber: 0,
    tags: ['hardware'],
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
        parameters: [],
      ),
    ],
    metadata: {'tempo': 108},
  );

  Future<({
    MockMidiTransport transport,
    DeviceConnectionController connection,
    PatchEditorController editor,
    PatchLibraryController library,
  })> createHarness({
    List<Patch> initialLibrary = const [zoomPatchA, zoomPatchB, podPatch],
    bool populateSlot0 = true,
  }) async {
    final transport = MockMidiTransport(initialPorts: [zoomPort]);
    final connection = DeviceConnectionController(
      transport: transport,
      defaultFamily: DeviceFamily.zoomMs60bPlus,
      enableHotPlugPolling: false,
      pacingDelayOverride: Duration.zero,
    );
    await connection.refreshPorts(autoConnect: false);
    await connection.connect(
      zoomPort,
      explicitFamily: DeviceFamily.zoomMs60bPlus,
      fetchCurrentPatch: false,
    );

    if (populateSlot0) {
      connection.updateBankSlot(
        0,
        patchName: 'HwClean',
        patch: hwSlotPatch0,
      );
    }

    final repo = InMemoryPatchLibraryRepository(initialPatches: initialLibrary);
    final library = PatchLibraryController(repository: repo);
    await library.refresh();

    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: zoomPatchA,
    )..setLibraryController(library);

    return (
      transport: transport,
      connection: connection,
      editor: editor,
      library: library,
    );
  }

  group('Controller Unit Tests (Milestone 17)', () {
    test('PatchLibraryController.duplicatePatch creates a new copy without overwriting original', () async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      final copy = await h.library.duplicatePatch(zoomPatchA, newName: 'SlapFunk V2');
      expect(copy.id, isNot(equals(zoomPatchA.id)));
      expect(copy.name, equals('SlapFunk V2'));
      expect(copy.programNumber, isNull);
      expect(h.library.patches.any((p) => p.id == zoomPatchA.id && p.name == 'SlapFunk'), isTrue);
      expect(h.library.patches.any((p) => p.id == copy.id && p.name == 'SlapFunk V2'), isTrue);
    });

    test('PatchLibraryController.saveHardwareSlotToLibrary stores slot copy and updates tags', () async {
      final h = await createHarness(initialLibrary: [zoomPatchA]);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      final saved = await h.library.saveHardwareSlotToLibrary(hwSlotPatch0, slotIndex: 0);
      expect(saved.id, isNot(equals(hwSlotPatch0.id)));
      expect(saved.name, equals('HwClean'));
      expect(h.library.availableTags, contains('hardware'));
      expect(h.library.patches.length, equals(2));
    });

    test('PatchEditorController.saveCopyAs saves active patch copy to attached library', () async {
      final h = await createHarness(initialLibrary: [zoomPatchA]);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      final copy = await h.editor.saveCopyAs('ActiveCopy');
      expect(copy, isNotNull);
      expect(copy!.name, equals('ActiveCopy'));
      expect(h.library.patches.length, equals(2));
      expect(h.library.patches.any((p) => p.name == 'ActiveCopy'), isTrue);
    });

    test('PatchEditorController.restoreBankSlots writes sequentially and supports cancellation', () async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      final restoreFuture = h.editor.restoreBankSlots(
        patches: [zoomPatchA, zoomPatchB, zoomPatchA],
        startSlotIndex: 2,
        interSlotDelay: const Duration(milliseconds: 5),
      );

      // Cancel after first slot write begins
      await Future<void>.delayed(const Duration(milliseconds: 2));
      h.editor.cancelBankRestore();
      final written = await restoreFuture;

      expect(written, greaterThanOrEqualTo(1));
      expect(written, lessThan(3));
      expect(h.editor.isRestoringBank, isFalse);
      expect(h.connection.bankSlots[2].name, equals('SlapFunk'));
    });
  });

  group('Drag-and-Drop Bank Manager Widget Tests', () {
    testWidgets('dragging matching local preset onto hardware slot writes to device', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: BankManagerDialog(
              libraryController: h.library,
              editorController: h.editor,
              connectionController: h.connection,
            ),
          ),
        ),
      );
      await tester.pump();

      final sentBefore = h.transport.sentMessages.length;
      final sourceFinder = find.byKey(const Key('bank_manager_preset_card_lib_zoom_b'));
      final targetFinder = find.byKey(const Key('bank_manager_slot_1'));

      final gesture = await tester.startGesture(tester.getCenter(sourceFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(targetFinder));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(h.transport.sentMessages.length, greaterThan(sentBefore));
      expect(h.connection.bankSlots[1].name, equals('WarmSVT'));
      expect(find.textContaining('Wrote "WarmSVT" to hardware slot #01'), findsOneWidget);
    });

    testWidgets('dragging cross-generation preset shows hover warning and hard-blocks write without Write Anyway', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: BankManagerDialog(
              libraryController: h.library,
              editorController: h.editor,
              connectionController: h.connection,
            ),
          ),
        ),
      );
      await tester.pump();

      final sourceFinder = find.byKey(const Key('bank_manager_preset_card_lib_pod_1'));
      final targetFinder = find.byKey(const Key('bank_manager_slot_2'));

      final gesture = await tester.startGesture(tester.getCenter(sourceFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(targetFinder));
      await tester.pump();
      expect(find.byKey(const Key('slot_mismatch_warning_2')), findsOneWidget);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('generation_incompatible_dialog')), findsOneWidget);
      expect(find.byKey(const Key('device_mismatch_drop_dialog')), findsNothing);
      expect(find.byKey(const Key('mismatch_drop_confirm_button')), findsNothing);

      await tester.tap(find.byKey(const Key('generation_incompatible_ok_button')));
      await tester.pump();
      expect(h.connection.bankSlots[2].name, isNot(equals('PodDrive')));
    });

    testWidgets('dragging same-generation cross-model preset shows hover warning and confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final h = await createHarness(
        initialLibrary: const [zoomPatchA, zoom50gPatch, podPatch],
      );
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: BankManagerDialog(
              libraryController: h.library,
              editorController: h.editor,
              connectionController: h.connection,
            ),
          ),
        ),
      );
      await tester.pump();

      final sourceFinder = find.byKey(const Key('bank_manager_preset_card_lib_zoom_50g'));
      final targetFinder = find.byKey(const Key('bank_manager_slot_2'));

      // 1. Hover shows mismatch warning, cancel aborts write
      final gesture1 = await tester.startGesture(tester.getCenter(sourceFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture1.moveTo(tester.getCenter(targetFinder));
      await tester.pump();
      expect(find.byKey(const Key('slot_mismatch_warning_2')), findsOneWidget);

      await gesture1.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('device_mismatch_drop_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mismatch_drop_cancel_button')));
      await tester.pump();
      expect(h.connection.bankSlots[2].name, isNot(equals('Ms50Crunch')));

      // 2. Drop again and confirm writes to slot
      final gesture2 = await tester.startGesture(tester.getCenter(sourceFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture2.moveTo(tester.getCenter(targetFinder));
      await tester.pump();
      await gesture2.up();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const Key('mismatch_drop_confirm_button')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(h.connection.bankSlots[2].name, equals('Ms50Crunch'));
    });

    testWidgets('dragging populated hardware slot onto local library saves a copy', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final h = await createHarness(initialLibrary: [zoomPatchA]);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: BankManagerDialog(
              libraryController: h.library,
              editorController: h.editor,
              connectionController: h.connection,
            ),
          ),
        ),
      );
      await tester.pump();

      final initialCount = h.library.patches.length;
      final sourceFinder = find.byKey(const Key('bank_manager_slot_0'));
      final targetFinder = find.byKey(const Key('bank_manager_library_drop_zone'));

      final gesture = await tester.startGesture(tester.getCenter(sourceFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(targetFinder));
      await tester.pump();
      expect(find.byKey(const Key('library_drop_hover_banner')), findsOneWidget);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(h.library.patches.length, equals(initialCount + 1));
      expect(h.library.patches.any((p) => p.name == 'HwClean'), isTrue);
    });
  });

  group('Batch Bank Restore & Save Copy As Widget Tests', () {
    testWidgets('BankRestoreDialog restores selected presets sequentially and supports cancellation', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final h = await createHarness(initialLibrary: [zoomPatchA, zoomPatchB]);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: BankRestoreDialog(
              libraryController: h.library,
              editorController: h.editor,
              connectionController: h.connection,
              interSlotDelay: const Duration(milliseconds: 40),
            ),
          ),
        ),
      );
      await tester.pump();

      // Start restore (all matching zoom patches selected by default)
      await tester.tap(find.byKey(const Key('start_bank_restore_button')));
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const Key('bank_restore_progress_bar')), findsOneWidget);
      expect(find.byKey(const Key('cancel_bank_restore_button')), findsOneWidget);

      // Cancel mid-restore
      await tester.tap(find.byKey(const Key('cancel_bank_restore_button')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();

      expect(find.byKey(const Key('bank_restore_completion_text')), findsOneWidget);
      expect(h.editor.isRestoringBank, isFalse);

      // Run a full restore to completion
      await tester.tap(find.byKey(const Key('start_bank_restore_button')));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.textContaining('Restored 2/2 hardware slots'), findsOneWidget);
      expect(h.connection.bankSlots[0].name, equals('SlapFunk'));
      expect(h.connection.bankSlots[1].name, equals('WarmSVT'));
    });

    testWidgets('Save Copy As from PatchMetadataHeaderWidget and PatchLibraryDrawerOrPanel duplicates presets', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final h = await createHarness(initialLibrary: [zoomPatchA]);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: PatchMetadataHeaderWidget(controller: h.editor),
                ),
                SizedBox(
                  width: 340,
                  child: PatchLibraryDrawerOrPanel(
                    libraryController: h.library,
                    editorController: h.editor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Save Copy As from PatchMetadataHeaderWidget
      await tester.tap(find.byKey(const Key('save_copy_as_button')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('save_copy_as_name_input')), 'HeaderDup');
      await tester.tap(find.byKey(const Key('save_copy_as_confirm_button')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(h.library.patches.any((p) => p.name == 'HeaderDup'), isTrue);
      expect(h.library.patches.any((p) => p.id == 'lib_zoom_a' && p.name == 'SlapFunk'), isTrue);

      // 2. Duplicate from PatchLibraryDrawerOrPanel card action
      await tester.tap(find.byKey(const Key('duplicate_patch_lib_zoom_a_button')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('save_copy_as_name_input')), 'LibDup');
      await tester.tap(find.byKey(const Key('save_copy_as_confirm_button')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(h.library.patches.length, equals(3));
      expect(h.library.patches.any((p) => p.name == 'LibDup'), isTrue);
    });

    testWidgets('BankRestoreDialog restores directly from backup file on disk without duplicating local library', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fs = InMemoryImportFileSystem();
      final payload = ExportAdapterRegistry.standard()
          .adapterFor(ExportFormat.nativeJson)
          .exportLibrary([zoomPatchB, podPatch], libraryName: 'BackupBank');
      fs.addFile(
        '/memory/Documents/SignalChainExports/BackupBank.json',
        payload.bytes,
      );

      final h = await createHarness(initialLibrary: const [zoomPatchA]);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      expect(h.library.patches.length, equals(1));

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: BankRestoreDialog(
              libraryController: h.library,
              editorController: h.editor,
              connectionController: h.connection,
              interSlotDelay: const Duration(milliseconds: 5),
              fileSystemOverride: fs,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('restore_source_file_tab')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      await tester.tap(find.byKey(const Key('bank_restore_entry_BackupBank.json')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.byKey(const Key('bank_restore_file_diagnostic')), findsOneWidget);
      expect(find.textContaining('1 incompatible generation excluded'), findsOneWidget);

      await tester.tap(find.byKey(const Key('start_bank_restore_button')));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.textContaining('Restored 1/1 hardware slots'), findsOneWidget);
      expect(h.connection.bankSlots[0].name, equals('WarmSVT'));
      // Library count remains unchanged (zero duplicate presets created)
      expect(h.library.patches.length, equals(1));
    });
  });
}
