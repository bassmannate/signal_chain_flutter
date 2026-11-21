@Timeout(Duration(seconds: 20))
library;

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/core/storage/setlist_repository.dart';
import 'package:signal_chain_flutter/features/connection/connection_bar_widget.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/unsaved_changes_dialog.dart';
import 'package:signal_chain_flutter/features/editor/write_to_slot_dialog.dart';
import 'package:signal_chain_flutter/features/library/bank_manager_dialog.dart';
import 'package:signal_chain_flutter/features/library/hardware_bank_browser_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_import_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_browser_widget.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_controller.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/main.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/models/setlist.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

class _FailingSavePatchRepository extends InMemoryPatchLibraryRepository {
  _FailingSavePatchRepository({super.initialPatches});

  @override
  Future<void> savePatch(Patch patch) async {
    throw StateError('Disk write error');
  }
}

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  const zoomPort = MidiPortDescriptor(
    id: 'sim_zoom',
    name: 'Zoom MS-60B+ (Simulated)',
    manufacturer: 'Zoom Corporation',
    isInput: true,
    isOutput: true,
  );

  Patch makePatch(
    String id,
    String name, {
    int? programNumber,
    double sense = 5.0,
  }) {
    return Patch(
      id: id,
      name: name,
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      programNumber: programNumber,
      slots: [
        EffectSlot(
          slotIndex: 0,
          effectId: '0x01000010',
          effectName: 'DYN Comp',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: const ParameterDescriptor(
                id: 'p0',
                name: 'Sense',
                min: 0,
                max: 10,
                defaultValue: 5,
              ),
              currentValue: sense,
            ),
          ],
        ),
      ],
      metadata: const {'tempo': 120},
    );
  }

  Future<({
    MockMidiTransport transport,
    DeviceConnectionController connection,
    PatchEditorController editor,
    PatchLibraryController library,
    InMemoryPatchLibraryRepository libRepo,
  })> createHarness({
    bool connect = false,
    Patch? initialPatch,
    List<Patch>? libraryPatches,
    InMemoryPatchLibraryRepository? repoOverride,
  }) async {
    final p1 = initialPatch ?? makePatch('p1', 'ActiveTone', programNumber: 3);
    final p2 = makePatch('p2', 'LibraryTone', programNumber: 4, sense: 8.0);
    final transport = MockMidiTransport(initialPorts: const [zoomPort]);
    final connection = DeviceConnectionController(
      transport: transport,
      defaultFamily: DeviceFamily.zoomMs60bPlus,
      enableHotPlugPolling: false,
      pacingDelayOverride: Duration.zero,
      isTest: true,
    );
    if (connect) {
      await connection.refreshPorts(autoConnect: false);
      await connection.connect(
        zoomPort,
        explicitFamily: DeviceFamily.zoomMs60bPlus,
        fetchCurrentPatch: false,
      );
    }

    final libRepo =
        repoOverride ?? InMemoryPatchLibraryRepository(initialPatches: libraryPatches ?? [p1, p2]);
    final library = PatchLibraryController(
      repository: libRepo,
      preferencesRepository: InMemoryPreferencesRepository(),
      importFileSystem: InMemoryImportFileSystem(),
    );
    await library.refresh();

    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: p1,
    )..setLibraryController(library);

    return (
      transport: transport,
      connection: connection,
      editor: editor,
      library: library,
      libRepo: libRepo,
    );
  }

  group('PatchEditorController & ConnectionBar dirty-state gaps', () {
    test('markSaved() clears isDirty and aligns Compare Slot A baseline', () async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      expect(h.editor.isDirty, isFalse);
      h.editor.updatePatchName('EditedName');
      expect(h.editor.isDirty, isTrue);

      h.editor.markSaved();
      expect(h.editor.isDirty, isFalse);
      expect(h.editor.comparePatchA?.name, equals('EditedName'));
    });

    test(
      'savePatchToDeviceSlot with external patch does not overwrite active _patch or clear _isDirty',
      () async {
        final h = await createHarness(connect: true);
        addTearDown(() {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          h.transport.dispose();
        });

        h.editor.updatePatchName('UnsavedAct');
        expect(h.editor.isDirty, isTrue);

        final externalPatch = makePatch('ext_1', 'ExternalPreset', sense: 9.0);
        await h.editor.savePatchToDeviceSlot(7, externalPatch);

        expect(h.editor.patch?.name, equals('UnsavedAct'));
        expect(h.editor.patch?.programNumber, equals(3));
        expect(h.editor.isDirty, isTrue);
        expect(h.connection.bankSlots[7].name, equals('ExternalPreset'));

        await h.editor.restoreBankSlots(
          patches: [makePatch('ext_2', 'BatchPreset')],
          startSlotIndex: 8,
          interSlotDelay: Duration.zero,
        );
        expect(h.editor.patch?.name, equals('UnsavedAct'));
        expect(h.editor.isDirty, isTrue);
        expect(h.connection.bankSlots[8].name, equals('BatchPreset'));
      },
    );

    testWidgets('ConnectionBar Save to Library clears isDirty via markSaved()', (tester) async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      h.editor.updatePatchName('DirtyBar');
      expect(h.editor.isDirty, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: ConnectionBarWidget(
              connectionController: h.connection,
              editorController: h.editor,
              libraryController: h.library,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('UNSAVED'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save_to_library_button')));
      await tester.pumpAndSettle();

      expect(h.editor.isDirty, isFalse);
      expect(find.text('UNSAVED'), findsNothing);
      expect(h.library.patches.any((p) => p.name == 'DirtyBar'), isTrue);
    });
  });

  group('confirmDiscardOrSaveUnsavedChanges dialog', () {
    testWidgets('returns true immediately when editor is clean without showing dialog', (tester) async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await confirmDiscardOrSaveUnsavedChanges(
                    context: context,
                    editorController: h.editor,
                    libraryController: h.library,
                    connectionController: h.connection,
                    actionDescription: 'test action',
                  );
                },
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger'));
      await tester.pump();

      expect(result, isTrue);
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsNothing);
    });

    testWidgets('Cancel returns false and preserves dirty state; Discard returns true', (tester) async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      h.editor.updatePatchName('ModifiedTone');
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await confirmDiscardOrSaveUnsavedChanges(
                    context: context,
                    editorController: h.editor,
                    libraryController: h.library,
                    connectionController: h.connection,
                    actionDescription: 'switch patches',
                  );
                },
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      // 1. Cancel
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);
      expect(find.byKey(const Key('unsaved_save_pedal_button')), findsNothing);

      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(h.editor.isDirty, isTrue);

      // 2. Discard
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('Save to Library saves patch, clears isDirty, and returns true', (tester) async {
      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      h.editor.updatePatchName('SavedPromp');
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await confirmDiscardOrSaveUnsavedChanges(
                    context: context,
                    editorController: h.editor,
                    libraryController: h.library,
                    connectionController: h.connection,
                  );
                },
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_save_library_button')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(h.editor.isDirty, isFalse);
      expect(h.library.patches.any((p) => p.name == 'SavedPromp'), isTrue);
    });

    testWidgets('Save to Library failure shows error SnackBar and returns false', (tester) async {
      final failingRepo = _FailingSavePatchRepository(
        initialPatches: [makePatch('p1', 'ActiveTone')],
      );
      final h = await createHarness(repoOverride: failingRepo);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      h.editor.updatePatchName('FailedSave');
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await confirmDiscardOrSaveUnsavedChanges(
                    context: context,
                    editorController: h.editor,
                    libraryController: h.library,
                    connectionController: h.connection,
                  );
                },
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_save_library_button')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(h.editor.isDirty, isTrue);
      expect(find.textContaining('Failed to save to library'), findsOneWidget);
    });

    testWidgets(
      'Save to Pedal button appears only when connected and writes directly when programNumber is known or opens WriteToSlotDialog when null',
      (tester) async {
        // Case A: Connected with known programNumber (3)
        final hKnown = await createHarness(
          connect: true,
          initialPatch: makePatch('p1', 'Slot3Patch', programNumber: 3),
        );
        addTearDown(() {
          hKnown.editor.dispose();
          hKnown.connection.dispose();
          hKnown.library.dispose();
          hKnown.transport.dispose();
        });

        hKnown.editor.updatePatchName('Slot3Edit');
        bool? resultA;

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    resultA = await confirmDiscardOrSaveUnsavedChanges(
                      context: context,
                      editorController: hKnown.editor,
                      libraryController: hKnown.library,
                      connectionController: hKnown.connection,
                    );
                  },
                  child: const Text('TriggerA'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('TriggerA'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsaved_save_pedal_button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('unsaved_save_pedal_button')));
        await tester.pumpAndSettle();

        expect(resultA, isTrue);
        expect(hKnown.editor.isDirty, isFalse);
        expect(hKnown.connection.bankSlots[3].name, equals('Slot3Edit'));

        // Case B: Connected with null programNumber -> opens WriteToSlotDialog
        final hUnknown = await createHarness(
          connect: true,
          initialPatch: makePatch('p_null', 'Unassigned', programNumber: null),
        );
        addTearDown(() {
          hUnknown.editor.dispose();
          hUnknown.connection.dispose();
          hUnknown.library.dispose();
          hUnknown.transport.dispose();
        });

        hUnknown.editor.updatePatchName('NoSlotEdit');
        bool? resultB;

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    resultB = await confirmDiscardOrSaveUnsavedChanges(
                      context: context,
                      editorController: hUnknown.editor,
                      libraryController: hUnknown.library,
                      connectionController: hUnknown.connection,
                    );
                  },
                  child: const Text('TriggerB'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('TriggerB'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('unsaved_save_pedal_button')));
        await tester.pumpAndSettle();

        expect(find.byType(WriteToSlotDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm_write_slot_button')));
        await tester.pumpAndSettle();

        expect(resultB, isTrue);
        expect(hUnknown.editor.isDirty, isFalse);
        expect(hUnknown.connection.bankSlots[0].name, equals('NoSlotEdit'));
      },
    );
  });

  group('Guarded in-app patch-replacing entry points', () {
    testWidgets('PatchLibraryDrawerOrPanel Load button guards dirty edits (Cancel, Discard, Save)', (tester) async {
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
            body: PatchLibraryDrawerOrPanel(
              libraryController: h.library,
              editorController: h.editor,
              isPanel: true,
            ),
          ),
        ),
      );
      await tester.pump();

      h.editor.updatePatchName('DirtyActiv');

      // 1. Cancel keeps active patch
      await tester.tap(find.byKey(const Key('load_patch_p2_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();

      expect(h.editor.patch?.name, equals('DirtyActiv'));
      expect(h.editor.isDirty, isTrue);

      // 2. Save to Library saves DirtyActiv then loads LibraryTone
      await tester.tap(find.byKey(const Key('load_patch_p2_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_save_library_button')));
      await tester.pumpAndSettle();

      expect(h.library.patches.any((p) => p.name == 'DirtyActiv'), isTrue);
      expect(h.editor.patch?.name, equals('LibraryTone'));
      expect(h.editor.isDirty, isFalse);

      // 3. Edit again and Discard loads DirtyActiv (p1)
      h.editor.updatePatchName('TempDirty');
      await tester.tap(find.byKey(const Key('load_patch_p1_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();

      expect(h.editor.patch?.name, equals('DirtyActiv'));
      expect(h.editor.isDirty, isFalse);
    });

    testWidgets('HardwareBankBrowserWidget and BankManagerDialog guard loading slots while dirty', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final h = await createHarness(connect: true);
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      h.connection.updateBankSlot(
        1,
        patchName: 'HwSlot1',
        patch: makePatch('hw1', 'HwSlot1', programNumber: 1),
      );
      h.connection.updateBankSlot(
        2,
        patchName: 'HwSlot2',
        patch: makePatch('hw2', 'HwSlot2', programNumber: 2),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: HardwareBankBrowserWidget(
              connectionController: h.connection,
              editorController: h.editor,
              libraryController: h.library,
            ),
          ),
        ),
      );
      await tester.pump();

      h.editor.updatePatchName('DirtyEdit');

      // 1. HardwareBankBrowserWidget Cancel vs Discard
      await tester.tap(find.byKey(const Key('bank_slot_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();
      expect(h.editor.patch?.name, equals('DirtyEdit'));

      await tester.tap(find.byKey(const Key('load_slot_1_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();
      expect(h.editor.patch?.name, equals('HwSlot1'));

      // 2. BankManagerDialog Load into Editor guard
      h.editor.updatePatchName('DirtyMgr');
      await tester.tap(find.byKey(const Key('open_bank_manager_from_hw_button')));
      await tester.pumpAndSettle();
      expect(find.byType(BankManagerDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('bank_manager_load_slot_2_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();
      expect(h.editor.patch?.name, equals('DirtyMgr'));

      await tester.tap(find.byKey(const Key('bank_manager_load_slot_2_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();
      expect(h.editor.patch?.name, equals('HwSlot2'));
    });

    testWidgets('PatchImportDialog guards Load into Editor and Add to Library with Also load into Editor', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fs = InMemoryImportFileSystem();
      final importedPatch = makePatch('imp_1', 'ImportedTone');
      final jsonBytes = ExportAdapterRegistry.standard()
          .adapterFor(ExportFormat.nativeJson)
          .exportPatch(importedPatch)
          .bytes;
      fs.addFile('/memory/Documents/SignalChainExports/imported.json', jsonBytes);

      final h = await createHarness();
      addTearDown(() {
        h.editor.dispose();
        h.connection.dispose();
        h.library.dispose();
        h.transport.dispose();
      });

      h.editor.updatePatchName('DirtyImp');

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => PatchImportDialog(
                      libraryController: h.library,
                      editorController: h.editor,
                      fileSystemOverride: fs,
                    ),
                  ),
                  child: const Text('OpenImport'),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Add to Library WITHOUT Also load into Editor -> no prompt
      await tester.tap(find.text('OpenImport'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_fs_entry_imported.json')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_add_library_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unsaved_changes_dialog')), findsNothing);
      expect(h.editor.patch?.name, equals('DirtyImp'));
      expect(h.editor.isDirty, isTrue);

      // 2. Add to Library WITH Also load into Editor -> prompts & Cancel aborts
      await tester.tap(find.text('OpenImport'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_fs_entry_imported.json')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_also_load_into_editor_checkbox')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_add_library_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();
      expect(h.editor.patch?.name, equals('DirtyImp'));
      expect(find.byType(PatchImportDialog), findsOneWidget);

      // 3. Load into Editor while dirty -> Discard loads ImportedTone
      await tester.tap(find.byKey(const Key('import_load_editor_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();
      expect(h.editor.patch?.name, equals('ImportedTone'));
      expect(h.editor.isDirty, isFalse);

      // Verify utf8 json sanity (avoid unused import warning if needed)
      expect(utf8.decode(jsonBytes), contains('ImportedTone'));
    });

    testWidgets(
      'SetlistBrowserWidget and Stage Mode entry guard dirty edits without blocking live Stage Mode stepping',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final p1 = makePatch('p1', 'SongOne');
        final p2 = makePatch('p2', 'SongTwo', sense: 9.0);
        final h = await createHarness(initialPatch: p1, libraryPatches: [p1, p2]);
        final setRepo = InMemorySetlistRepository(
          initialSetlists: const [
            Setlist(
              id: 's1',
              name: 'Gig Set',
              entries: [
                SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Song One'),
                SetlistEntry(id: 'e2', patchId: 'p2', songTitle: 'Song Two'),
              ],
            ),
          ],
        );
        final setlistController = SetlistController(
          repository: setRepo,
          libraryController: h.library,
          editorController: h.editor,
          connectionController: h.connection,
          transport: h.transport,
        );
        await setlistController.refresh();

        addTearDown(() {
          setlistController.dispose();
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: ListenableBuilder(
              listenable: setlistController,
              builder: (context, _) => Scaffold(
                body: Column(
                  children: [
                    ConnectionBarWidget(
                      connectionController: h.connection,
                      editorController: h.editor,
                      libraryController: h.library,
                      setlistController: setlistController,
                    ),
                    Expanded(
                      child: SetlistBrowserWidget(
                        setlistController: setlistController,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // 1. Tapping setlist entry while dirty prompts
        h.editor.updatePatchName('DirtySet');
        await tester.tap(find.byKey(const Key('setlist_entry_e2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
        await tester.pumpAndSettle();
        expect(h.editor.patch?.name, equals('DirtySet'));

        // 2. Tapping Perform Live while dirty prompts
        await tester.tap(find.byKey(const Key('launch_stage_mode_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
        await tester.pumpAndSettle();
        expect(setlistController.isPerformanceModeActive, isFalse);

        // 3. Tapping Stage Mode toggle in ConnectionBar while dirty prompts and Discard enters Stage Mode
        await tester.tap(find.byKey(const Key('toggle_performance_mode_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('unsaved_discard_button')));
        await tester.pumpAndSettle();
        expect(setlistController.isPerformanceModeActive, isTrue);

        // 4. Once inside Stage Mode, making live edits does NOT block PREV/NEXT or MIDI stepping
        h.editor.toggleSlotEnabled(0);
        expect(h.editor.isDirty, isTrue);

        await setlistController.nextEntry();
        await tester.pump();
        expect(find.byKey(const Key('unsaved_changes_dialog')), findsNothing);
        expect(setlistController.activeEntryIndex, equals(1));
        expect(h.editor.patch?.name, equals('SongTwo'));

        // MIDI PC stepping while dirty in Stage Mode is also unblocked
        h.editor.toggleSlotEnabled(0);
        expect(h.editor.isDirty, isTrue);
        setlistController.updateMidiConfig(
          const MidiFootControllerConfig(enableProgramChangeSelect: true),
        );
        h.transport.simulateIncomingMessage(
          MidiMessage.programChange(channel: 0, program: 0),
        );
        await tester.pump();
        expect(find.byKey(const Key('unsaved_changes_dialog')), findsNothing);
        expect(setlistController.activeEntryIndex, equals(0));
      },
    );
  });

  group('Exit guard (AppLifecycleListener.onExitRequested & PopScope)', () {
    Future<({
      MockMidiTransport transport,
      DeviceConnectionController connection,
      PatchEditorController editor,
      PatchLibraryController library,
      SetlistController setlist,
    })> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final p1 = makePatch('p1', 'MainStage');
      final p2 = makePatch('p2', 'BackupTone');
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(
        transport: transport,
        enableHotPlugPolling: false,
        isTest: true,
      );
      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: p1,
      );
      final libRepo = InMemoryPatchLibraryRepository(initialPatches: [p1, p2]);
      final library = PatchLibraryController(
        repository: libRepo,
        preferencesRepository: InMemoryPreferencesRepository(),
        importFileSystem: InMemoryImportFileSystem(),
      );
      final setRepo = InMemorySetlistRepository();
      final setlist = SetlistController(
        repository: setRepo,
        libraryController: library,
        editorController: editor,
        connectionController: connection,
        transport: transport,
      );

      addTearDown(() {
        setlist.dispose();
        library.dispose();
        editor.dispose();
        connection.dispose();
        transport.dispose();
      });

      await tester.pumpWidget(
        SignalChainApp(
          transport: transport,
          libraryRepository: libRepo,
          setlistRepository: setRepo,
          connectionController: connection,
          editorController: editor,
          libraryController: library,
          setlistController: setlist,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      return (
        transport: transport,
        connection: connection,
        editor: editor,
        library: library,
        setlist: setlist,
      );
    }

    testWidgets('onExitRequested exits immediately when clean', (tester) async {
      final h = await pumpApp(tester);
      expect(h.editor.isDirty, isFalse);

      final response = await tester.binding.handleRequestAppExit();
      await tester.pump();

      expect(response, equals(AppExitResponse.exit));
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsNothing);
    });

    testWidgets('onExitRequested prompts when dirty, prevents re-entrant dialogs, and handles Cancel/Discard/Save', (tester) async {
      final h = await pumpApp(tester);
      h.editor.updatePatchName('ExitDirty');
      await tester.pump();

      // 1. Trigger exit + re-entrant second exit click -> Cancel
      final exitFuture1 = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      final exitFuture2 = tester.binding.handleRequestAppExit();
      expect(await exitFuture2, equals(AppExitResponse.cancel));
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();
      expect(await exitFuture1, equals(AppExitResponse.cancel));
      expect(h.editor.isDirty, isTrue);

      // 2. Trigger exit -> Discard
      final exitDiscardFuture = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();
      expect(await exitDiscardFuture, equals(AppExitResponse.exit));

      // 3. Trigger exit -> Save to Library
      final exitSaveFuture = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_save_library_button')));
      await tester.pumpAndSettle();
      expect(await exitSaveFuture, equals(AppExitResponse.exit));
      expect(h.editor.isDirty, isFalse);
      expect(h.library.patches.any((p) => p.name == 'ExitDirty'), isTrue);
    });

    testWidgets('PopScope blocks Android back when dirty, prompts, and calls SystemNavigator.pop on Discard', (tester) async {
      final h = await pumpApp(tester);
      bool systemNavigatorPopped = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') {
          systemNavigatorPopped = true;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      h.editor.updatePatchName('AndroidBackDirty');
      await tester.pump();

      // 1. Back press -> blocked, shows dialog -> Cancel keeps app open
      final handled1 = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled1, isTrue);
      expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
      await tester.pumpAndSettle();
      expect(systemNavigatorPopped, isFalse);

      // 2. Back press -> Discard -> invokes SystemNavigator.pop()
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unsaved_discard_button')));
      await tester.pumpAndSettle();

      expect(systemNavigatorPopped, isTrue);
    });
  });
}
