@Timeout(Duration(seconds: 20))
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/compatibility/patch_effect_compatibility.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/core/storage/setlist_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/effect_picker_dialog.dart';
import 'package:signal_chain_flutter/features/editor/missing_effects_dialog.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/features/editor/slot_inspector_widget.dart';
import 'package:signal_chain_flutter/features/editor/unsaved_changes_dialog.dart';
import 'package:signal_chain_flutter/features/editor/write_to_slot_dialog.dart';
import 'package:signal_chain_flutter/features/library/bank_manager_dialog.dart';
import 'package:signal_chain_flutter/features/library/bank_restore_dialog.dart';
import 'package:signal_chain_flutter/features/library/hardware_bank_browser_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_import_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_browser_widget.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_controller.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_performance_view.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/models/setlist.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

import '../../core/zd2/flst_seq_parser_test.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
  });

  const ms60bPort = MidiPortDescriptor(
    id: 'zoom_ms60bp',
    name: 'ZOOM MS-60B+',
    manufacturer: 'Zoom Corporation',
    isInput: true,
    isOutput: true,
  );

  // Stock MS-60B+: 0x01000010 (DYN Comp), 0x02000010 (Bass Preamp)
  // Cross-model MS-50G+: 0x030000E0 (TB MK1.5)
  // Custom .ZD2: 0x04000999
  EffectSlot makeStockCompSlot(int index, {double sense = 5}) => EffectSlot(
        slotIndex: index,
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
      );

  EffectSlot makeStockPreampSlot(int index) => EffectSlot(
        slotIndex: index,
        effectId: '0x02000010',
        effectName: 'Bass Preamp',
        isEnabled: true,
        parameters: const [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'p0',
              name: 'Bass',
              min: 0,
              max: 100,
              defaultValue: 50,
            ),
            currentValue: 50,
          ),
        ],
      );

  EffectSlot makeMissingCrossSlot(int index) => EffectSlot(
        slotIndex: index,
        effectId: '0x030000E0',
        effectName: 'TB MK1.5',
        isEnabled: true,
        parameters: const [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'p0',
              name: 'Level',
              min: 0,
              max: 100,
              defaultValue: 50,
            ),
            currentValue: 65,
          ),
        ],
      );

  Uint8List makeFlstWithInstalledIds(List<int> installedIds) {
    return buildSyntheticFlstSeq(
      deviceName: 'MS-60B+',
      groups: [
        (
          groupByte: 0x01,
          includeCloseMarker: true,
          entries: [
            for (final id in installedIds)
              (
                filename: 'FX_${id.toRadixString(16)}.ZD2',
                version: '1.00',
                effectId: id,
                installed: true,
              ),
          ],
        ),
      ],
    );
  }

  Future<({
    MockMidiTransport transport,
    DeviceConnectionController connection,
    PatchEditorController editor,
    PatchLibraryController library,
  })> createHarness({
    bool connect = true,
    List<int>? scannedInstalledIds,
    Patch? initialPatch,
    List<Patch>? libraryPatches,
  }) async {
    final transport = MockMidiTransport(initialPorts: const [ms60bPort]);
    if (scannedInstalledIds != null) {
      transport.setVirtualZoomFiles({
        'FLST_SEQ.ZT2': makeFlstWithInstalledIds(scannedInstalledIds),
      });
    }

    final connection = DeviceConnectionController(
      transport: transport,
      defaultFamily: DeviceFamily.zoomMs60bPlus,
      enableHotPlugPolling: false,
      pacingDelayOverride: Duration.zero,
      isTest: true,
    );

    if (connect) {
      await connection.connect(
        ms60bPort,
        explicitFamily: DeviceFamily.zoomMs60bPlus,
        fetchCurrentPatch: false,
        autoSyncBank: false,
        autoDiscoverEffects: scannedInstalledIds != null,
      );
    }

    final patch = initialPatch ??
        Patch(
          id: 'p_init',
          name: 'MixedRig',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          programNumber: 2,
          rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3 (after slot 1)
          slots: [
            makeMissingCrossSlot(0),
            makeStockCompSlot(1),
            makeStockPreampSlot(2),
          ],
          metadata: const {'tempo': 120},
        );

    final libRepo = InMemoryPatchLibraryRepository(
      initialPatches: libraryPatches ?? [patch],
    );
    final library = PatchLibraryController(
      repository: libRepo,
      preferencesRepository: InMemoryPreferencesRepository(),
      importFileSystem: InMemoryImportFileSystem(),
    );
    await library.refresh();

    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: patch,
    )..setLibraryController(library);

    transport.clearSentMessages();

    return (
      transport: transport,
      connection: connection,
      editor: editor,
      library: library,
    );
  }

  int? extractEffectIdFromTypeMsg(dynamic msg) {
    final data = msg.data as List<int>;
    if (data.length < 15 ||
        data[1] != ZoomMsPlusProtocol.manufacturerId ||
        data[3] != ZoomMsPlusProtocol.familyIdByte ||
        data[4] != 0x64 ||
        data[5] != ZoomMsPlusProtocol.cmdParameterEdit ||
        data[6] != 0x00 ||
        data[7] == 0x64 ||
        data[8] != 0x01) {
      return null;
    }
    return (data[9] & 0x7F) |
        ((data[10] & 0x7F) << 7) |
        ((data[11] & 0x7F) << 14) |
        ((data[12] & 0x7F) << 21) |
        ((data[13] & 0x7F) << 28);
  }

  group('Editor Non-Blocking Warnings & Quick Actions', () {
    testWidgets(
      'SignalChainStripWidget shows MISSING badge & tooltip only when connected with missing effects',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final h = await createHarness(
          connect: false,
          scannedInstalledIds: const [0x01000010, 0x02000010],
        );
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SignalChainStripWidget(controller: h.editor),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Disconnected: NO MISSING badge
        expect(find.byKey(const Key('missing_effect_badge_0')), findsNothing);
        expect(find.byKey(const Key('missing_effect_badge_1')), findsNothing);

        // Connect with scanned onboard inventory (missing 0x030000E0 at slot 0)
        await h.connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: false,
          autoSyncBank: false,
          autoDiscoverEffects: true,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('missing_effect_badge_0')), findsOneWidget);
        expect(find.byKey(const Key('missing_effect_badge_1')), findsNothing);
        expect(find.byKey(const Key('missing_effect_badge_2')), findsNothing);
        expect(find.text('MISSING'), findsOneWidget);

        final tooltipFinder = find.ancestor(
          of: find.byKey(const Key('missing_effect_badge_0')),
          matching: find.byType(Tooltip),
        );
        expect(tooltipFinder, findsOneWidget);
        final tooltip = tester.widget<Tooltip>(tooltipFinder);
        expect(tooltip.message, contains('Not installed on connected MS-60B+'));
      },
    );

    testWidgets(
      'SlotInspectorWidget displays warning banner with origin label and supports Replace Effect and Remove Slot',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
        );
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SlotInspectorWidget(controller: h.editor),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Slot 0 is selected initially and is missing MS-50G+ TB MK1.5
        expect(
          find.byKey(const Key('slot_inspector_missing_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('MS-50G+ effect — not installed on connected MS-60B+'),
          findsOneWidget,
        );

        // 1. Replace Effect... opens EffectPickerDialog and replaces slot 0
        await tester.tap(
          find.byKey(const Key('slot_inspector_replace_missing_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EffectPickerDialog), findsOneWidget);

        await tester.tap(find.byKey(const Key('select_effect_btn_0x01000010')));
        await tester.pumpAndSettle();

        expect(h.editor.patch!.slots[0].effectId, equals('0x01000010'));
        expect(
          find.byKey(const Key('slot_inspector_missing_banner')),
          findsNothing,
        );

        // 2. Undo brings back missing slot 0 -> test Remove Slot preserving R-Out and undo stack
        expect(h.editor.undo(), isTrue);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('slot_inspector_missing_banner')),
          findsOneWidget,
        );
        expect(h.editor.patch!.rightOutputTapCode, equals(3));

        await tester.tap(
          find.byKey(const Key('slot_inspector_remove_missing_button')),
        );
        await tester.pumpAndSettle();

        expect(h.editor.patch!.slots.length, equals(2));
        expect(h.editor.patch!.slots[0].effectId, equals('0x01000010'));
        // Slot 0 was before tapped slot 1 -> R-Out shifted 3 -> 2
        expect(h.editor.patch!.rightOutputTapCode, equals(2));
        expect(h.editor.canUndo, isTrue);
        expect(
          find.byKey(const Key('slot_inspector_missing_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'PatchImportDialog shows non-blocking amber warning line when connected with missing effects while still allowing import',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
        );
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        final patchToImport = Patch(
          id: 'imp_missing',
          name: 'CrossModelImport',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [
            makeStockCompSlot(0),
            makeMissingCrossSlot(1),
          ],
        );
        final jsonBytes = ExportAdapterRegistry.standard()
            .adapterFor(ExportFormat.nativeJson)
            .exportPatch(patchToImport)
            .bytes;
        final fs = InMemoryImportFileSystem();
        fs.addFile('/memory/Documents/SignalChainExports/cross.json', jsonBytes);

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: PatchImportDialog(
                libraryController: h.library,
                editorController: h.editor,
                fileSystemOverride: fs,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('import_fs_entry_cross.json')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('import_entry_missing_effects_0')),
          findsOneWidget,
        );
        expect(
          find.textContaining('1 effect not on MS-60B+'),
          findsOneWidget,
        );

        // Non-blocking: Import to Library remains enabled and works
        await tester.tap(find.byKey(const Key('import_add_library_button')));
        await tester.pumpAndSettle();
        expect(
          h.library.patches.any((p) => p.name == 'CrossModelImport'),
          isTrue,
        );
      },
    );
  });

  group('Shared MissingEffectsDialog Helpers & Write Guards', () {
    testWidgets(
      'resolveMissingEffectsForSingleWrite returns Cancel, Strip & Write, and Write Anyway accurately',
      (tester) async {
        final patch = Patch(
          id: 'single_dlg',
          name: 'SingleDlg',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3 -> shifts to 2
          slots: [
            makeMissingCrossSlot(0),
            makeStockCompSlot(1),
            makeStockPreampSlot(2),
          ],
        );
        final report = PatchEffectCompatibility.analyze(
          patch,
          DeviceFamily.zoomMs60bPlus,
          const {'0x01000010', '0x02000010'},
        );

        MissingEffectAction? capturedAction;
        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    capturedAction = await resolveMissingEffectsForSingleWrite(
                      context: context,
                      patch: patch,
                      targetFamily: DeviceFamily.zoomMs60bPlus,
                      report: report,
                    );
                  },
                  child: const Text('Prompt'),
                ),
              ),
            ),
          ),
        );

        // 1. Cancel
        await tester.tap(find.text('Prompt'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('missing_effects_single_dialog')), findsOneWidget);
        expect(find.textContaining('Verified by onboard pedal scan'), findsOneWidget);
        expect(find.textContaining('Slot #1: TB MK1.5 (0x030000E0)'), findsOneWidget);
        expect(find.textContaining('R-Out routing tap'), findsOneWidget);

        await tester.tap(find.byKey(const Key('missing_effects_cancel_button')));
        await tester.pumpAndSettle();
        expect(capturedAction, equals(MissingEffectAction.cancel));

        // 2. Write Anyway
        await tester.tap(find.text('Prompt'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('missing_effects_write_anyway_button')));
        await tester.pumpAndSettle();
        expect(capturedAction, equals(MissingEffectAction.sendAnyway));

        // 3. Strip Missing & Write
        await tester.tap(find.text('Prompt'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('missing_effects_strip_and_write_button')));
        await tester.pumpAndSettle();
        expect(capturedAction, equals(MissingEffectAction.stripAndProceed));
      },
    );

    testWidgets(
      'resolveMissingEffectsForBatchRestore returns all 4 actions accurately',
      (tester) async {
        final patchMissing = Patch(
          id: 'b_miss',
          name: 'BadRig',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [makeMissingCrossSlot(0), makeStockCompSlot(1)],
        );
        final report = PatchEffectCompatibility.analyze(
          patchMissing,
          DeviceFamily.zoomMs60bPlus,
        );

        BatchMissingEffectAction? capturedAction;
        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    capturedAction = await resolveMissingEffectsForBatchRestore(
                      context: context,
                      totalPatchCount: 3,
                      affectedPatches: [
                        AffectedBatchPatch(
                          index: 1,
                          patch: patchMissing,
                          report: report,
                        ),
                      ],
                      targetFamily: DeviceFamily.zoomMs60bPlus,
                      isVerifiedByHardwareScan: false,
                    );
                  },
                  child: const Text('PromptBatch'),
                ),
              ),
            ),
          ),
        );

        for (final pair in const [
          ('batch_missing_cancel_button', BatchMissingEffectAction.cancel),
          ('batch_missing_restore_anyway_button', BatchMissingEffectAction.restoreAnyway),
          ('batch_missing_skip_affected_button', BatchMissingEffectAction.skipAffected),
          ('batch_missing_strip_all_button', BatchMissingEffectAction.stripAndRestoreAll),
        ]) {
          await tester.tap(find.text('PromptBatch'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('missing_effects_batch_dialog')), findsOneWidget);
          expect(
            find.textContaining('Checked against stock MS-60B+ catalog'),
            findsOneWidget,
          );
          expect(find.textContaining('1 of 3 patches contain effects'), findsOneWidget);
          await tester.tap(find.byKey(Key(pair.$1)));
          await tester.pumpAndSettle();
          expect(capturedAction, equals(pair.$2));
        }
      },
    );

    testWidgets(
      'WriteToSlotDialog, resolveUnsavedChanges Save to Pedal, Quick Write, and Drop-to-Slot guard missing effects',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final libMissing = Patch(
          id: 'lib_missing',
          name: 'LibCross',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3 -> shifts to 2
          slots: [
            makeMissingCrossSlot(0),
            makeStockCompSlot(1),
            makeStockPreampSlot(2),
          ],
        );

        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
          libraryPatches: [libMissing],
        );
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        const proto = ZoomMsPlusProtocol(defaultFamily: DeviceFamily.zoomMs60bPlus);

        // 1. WriteToSlotDialog Cancel aborts without MIDI send
        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      key: const Key('open_write_dialog_btn'),
                      onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => WriteToSlotDialog(
                          editorController: h.editor,
                          connectionController: h.connection,
                        ),
                      ),
                      child: const Text('OpenWrite'),
                    ),
                    ElevatedButton(
                      key: const Key('trigger_unsaved_btn'),
                      onPressed: () => resolveUnsavedChanges(
                        context: context,
                        editorController: h.editor,
                        libraryController: h.library,
                        connectionController: h.connection,
                        actionDescription: 'switch patches',
                      ),
                      child: const Text('TriggerUnsaved'),
                    ),
                    ElevatedButton(
                      key: const Key('trigger_drop_btn'),
                      onPressed: () => handleLibraryPatchDropToSlot(
                        context,
                        payload: LibraryPatchDragPayload(libMissing),
                        slotIndex: 5,
                        connectionController: h.connection,
                        editorController: h.editor,
                      ),
                      child: const Text('TriggerDrop'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('open_write_dialog_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_write_slot_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('missing_effects_single_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('missing_effects_cancel_button')));
        await tester.pumpAndSettle();
        expect(h.transport.sentMessages, isEmpty);
        expect(find.byType(WriteToSlotDialog), findsOneWidget);

        // Close WriteToSlotDialog cleanly
        await tester.tap(find.byKey(const Key('cancel_write_slot_button')));
        await tester.pumpAndSettle();

        // 2. handleLibraryPatchDropToSlot with Strip Missing & Write preserves library patch untouched
        await tester.tap(find.byKey(const Key('trigger_drop_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('missing_effects_single_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('missing_effects_strip_and_write_button')));
        await tester.pumpAndSettle();

        expect(h.transport.sentMessages.length, equals(1));
        final droppedDecoded = proto.decodePatch(h.transport.sentMessages.single);
        expect(droppedDecoded.slots.length, equals(2));
        expect(droppedDecoded.slots.any((s) => s.effectId == '0x030000E0'), isFalse);
        expect(droppedDecoded.rightOutputTapCode, equals(2));
        // Original library patch was NOT mutated
        expect(libMissing.slots.length, equals(3));
        expect(libMissing.rightOutputTapCode, equals(3));

        // 3. resolveUnsavedChanges direct Save to Pedal -> Strip Missing & Write clears isDirty
        h.editor.updatePatchName('DirtyMix');
        expect(h.editor.isDirty, isTrue);
        h.transport.clearSentMessages();

        await tester.tap(find.byKey(const Key('trigger_unsaved_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('unsaved_save_pedal_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('missing_effects_single_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('missing_effects_strip_and_write_button')));
        await tester.pumpAndSettle();

        expect(h.editor.isDirty, isFalse);
        expect(h.editor.patch!.slots.length, equals(2));
        expect(h.editor.patch!.rightOutputTapCode, equals(2));
        expect(h.transport.sentMessages.length, equals(1));
        final savedActive = proto.decodePatch(h.transport.sentMessages.single);
        expect(savedActive.slots.length, equals(2));
        expect(savedActive.rightOutputTapCode, equals(2));

        // Undo can even restore the unstripped active patch if desired
        expect(h.editor.undo(), isTrue);
        expect(h.editor.patch!.slots.length, equals(3));

        // 4. HardwareBankBrowserWidget._quickWriteToSlot guards missing effects
        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 350,
                height: 700,
                child: HardwareBankBrowserWidget(
                  connectionController: h.connection,
                  editorController: h.editor,
                  libraryController: h.library,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        h.transport.clearSentMessages();

        await tester.tap(find.byKey(const Key('write_slot_0_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Overwrite'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('missing_effects_single_dialog')), findsOneWidget);

        await tester.tap(find.byKey(const Key('missing_effects_strip_and_write_button')));
        await tester.pumpAndSettle();
        expect(h.editor.patch!.slots.length, equals(2));
        expect(h.connection.bankSlots[0].patch!.slots.length, equals(2));
      },
    );

    testWidgets(
      'BankRestoreDialog runs upfront missing-effects check (Cancel, Skip Affected, Strip Missing & Restore All, Restore Anyway)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final cleanPatch = Patch(
          id: 'p_clean',
          name: 'CleanOne',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [makeStockCompSlot(0)],
        );
        final dirtyMissingPatch = Patch(
          id: 'p_missing',
          name: 'HasCross',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3 -> shifts to 0 when slot 1 becomes final
          slots: [makeMissingCrossSlot(0), makeStockCompSlot(1)],
        );

        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
          libraryPatches: [cleanPatch, dirtyMissingPatch],
        );
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: BankRestoreDialog(
                libraryController: h.library,
                editorController: h.editor,
                connectionController: h.connection,
                interSlotDelay: Duration.zero,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Cancel aborts without writing
        h.transport.clearSentMessages();
        await tester.tap(find.byKey(const Key('start_bank_restore_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('missing_effects_batch_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('batch_missing_cancel_button')));
        await tester.pumpAndSettle();
        expect(h.transport.sentMessages, isEmpty);

        // 2. Skip Affected -> writes only CleanOne and reports skipped count
        await tester.tap(find.byKey(const Key('start_bank_restore_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('batch_missing_skip_affected_button')));
        await tester.pumpAndSettle();
        expect(h.transport.sentMessages.length, equals(1));
        expect(
          find.textContaining('1 skipped due to missing effects'),
          findsOneWidget,
        );

        // 3. Strip Missing & Restore All -> writes 2 patches, HasCross stripped to 1 slot, library untouched
        h.transport.clearSentMessages();
        await tester.tap(find.byKey(const Key('start_bank_restore_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('batch_missing_strip_all_button')));
        await tester.pumpAndSettle();
        expect(h.transport.sentMessages.length, equals(2));
        expect(h.connection.bankSlots[1].patch!.slots.length, equals(1));
        expect(h.connection.bankSlots[1].patch!.slots.single.effectId, equals('0x01000010'));
        expect(dirtyMissingPatch.slots.length, equals(2));

        // 4. Restore Anyway -> sends all unmodified
        h.transport.clearSentMessages();
        await tester.tap(find.byKey(const Key('start_bank_restore_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('batch_missing_restore_anyway_button')));
        await tester.pumpAndSettle();
        expect(h.transport.sentMessages.length, equals(2));
        expect(h.connection.bankSlots[1].patch!.slots.length, equals(2));
      },
    );
  });

  group('Live Sync & Stage Mode Missing-Effect Guards', () {
    test(
      'updatePatchName, updatePatchTempo, _syncStructureToDevice, and _syncPatchTransitionToDevice never send buildEffectTypeMessage for uninstalled FXIDs',
      () async {
        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
        );
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        // Initial patch has uninstalled 0x030000E0 in slot 0, stock in slots 1 & 2.
        h.transport.clearSentMessages();
        h.editor.updatePatchName('CleanName');
        h.editor.updatePatchTempo(136);
        for (final msg in h.transport.sentMessages) {
          expect(extractEffectIdFromTypeMsg(msg), isNull);
        }

        // Structural edit affecting all slots (move slot 1 -> 2) & transition (undo)
        h.transport.clearSentMessages();
        expect(h.editor.moveEffectSlot(1, 2), isTrue);
        for (final msg in h.transport.sentMessages) {
          final fxId = extractEffectIdFromTypeMsg(msg);
          expect(fxId, isNot(equals(0x030000E0)));
        }

        h.transport.clearSentMessages();
        expect(h.editor.undo(), isTrue);
        for (final msg in h.transport.sentMessages) {
          final fxId = extractEffectIdFromTypeMsg(msg);
          expect(fxId, isNot(equals(0x030000E0)));
        }

        // A/B Compare transition also skips uninstalled 0x030000E0
        h.transport.clearSentMessages();
        h.editor.toggleCompareSlot();
        for (final msg in h.transport.sentMessages) {
          final fxId = extractEffectIdFromTypeMsg(msg);
          expect(fxId, isNot(equals(0x030000E0)));
        }
      },
    );

    test(
      'SetlistController.selectEntryAt never blocks, strips missing effects for hardware sync, populates liveCompatibilityWarning, and clears on clean patch or disconnect',
      () async {
        final cleanPatch = Patch(
          id: 'stage_clean',
          name: 'StageClean',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [makeStockCompSlot(0)],
        );
        final missingPatch = Patch(
          id: 'stage_miss',
          name: 'StageCross',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          rightOutputTapCode: RightOutputTap.afterSlot(1), // code 3 -> shifts to 2
          slots: [
            makeMissingCrossSlot(0),
            makeStockCompSlot(1),
            makeStockPreampSlot(2),
          ],
        );

        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
          initialPatch: cleanPatch,
          libraryPatches: [cleanPatch, missingPatch],
        );
        final setRepo = InMemorySetlistRepository(
          initialSetlists: const [
            Setlist(
              id: 'gig_1',
              name: 'Stage Set',
              entries: [
                SetlistEntry(id: 'e0', patchId: 'stage_clean', songTitle: 'Clean Song'),
                SetlistEntry(id: 'e1', patchId: 'stage_miss', songTitle: 'Cross Song'),
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

        addTearDown(() async {
          setlistController.dispose();
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        // Step to entry with missing effect -> completes immediately, strips missing slot on hardware
        h.transport.clearSentMessages();
        await setlistController.selectEntryAt(1);

        expect(setlistController.activeEntryIndex, equals(1));
        expect(setlistController.liveCompatibilityWarning, contains('Skipped 1 effect'));
        expect(setlistController.liveCompatibilityWarning, contains('MS-60B+'));
        expect(setlistController.liveCompatibilityWarning, contains('TB MK1.5'));
        expect(setlistController.skippedLiveSlots.length, equals(1));
        expect(setlistController.skippedLiveSlots.first.slotIndex, equals(0));

        // Active live patch received stripped chain (2 valid slots + shifted R-Out 2)
        expect(h.editor.patch!.slots.length, equals(2));
        expect(h.editor.patch!.rightOutputTapCode, equals(2));
        // Original library patch remains intact
        expect(missingPatch.slots.length, equals(3));

        // Verify uninstalled FXID 0x030000E0 was NEVER transmitted to pedal
        for (final msg in h.transport.sentMessages) {
          final fxId = extractEffectIdFromTypeMsg(msg);
          expect(fxId, isNot(equals(0x030000E0)));
        }

        // Stepping to clean patch clears liveCompatibilityWarning
        await setlistController.selectEntryAt(0);
        expect(setlistController.liveCompatibilityWarning, isNull);
        expect(setlistController.skippedLiveSlots, isEmpty);

        // Step back to missing entry, then disconnect -> clears liveCompatibilityWarning
        await setlistController.selectEntryAt(1);
        expect(setlistController.liveCompatibilityWarning, isNotNull);
        await h.connection.disconnect();
        expect(setlistController.liveCompatibilityWarning, isNull);
        expect(setlistController.skippedLiveSlots, isEmpty);
      },
    );

    testWidgets(
      'SetlistPerformanceView & SetlistBrowserWidget show non-blocking missing-effect warning banner and entry icons',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final cleanPatch = Patch(
          id: 'ui_clean',
          name: 'UIClean',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [makeStockCompSlot(0)],
        );
        final missingPatch = Patch(
          id: 'ui_miss',
          name: 'UICross',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [makeMissingCrossSlot(0), makeStockCompSlot(1)],
        );

        final h = await createHarness(
          connect: true,
          scannedInstalledIds: const [0x01000010, 0x02000010],
          initialPatch: cleanPatch,
          libraryPatches: [cleanPatch, missingPatch],
        );
        final setRepo = InMemorySetlistRepository(
          initialSetlists: const [
            Setlist(
              id: 'gig_ui',
              name: 'UI Set',
              entries: [
                SetlistEntry(id: 'e0', patchId: 'ui_clean', songTitle: 'Song One'),
                SetlistEntry(id: 'e1', patchId: 'ui_miss', songTitle: 'Song Two'),
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

        addTearDown(() async {
          setlistController.dispose();
          h.editor.dispose();
          h.connection.dispose();
          h.library.dispose();
          await h.transport.dispose();
        });

        // 1. SetlistBrowserWidget flags Song Two before entering Stage Mode
        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 340,
                height: 700,
                child: SetlistBrowserWidget(setlistController: setlistController),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('setlist_browser_entry_missing_icon_e0')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('setlist_browser_entry_missing_icon_e1')),
          findsOneWidget,
        );

        // 2. SetlistPerformanceView shows entry warning icon & non-blocking live banner on step
        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SetlistPerformanceView(
                setlistController: setlistController,
                editorController: h.editor,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('stage_setlist_entry_missing_icon_0')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('stage_setlist_entry_missing_icon_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('stage_live_compatibility_warning_banner')),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('setlist_next_button')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.byKey(const Key('stage_live_compatibility_warning_banner')),
          findsOneWidget,
        );
        expect(find.textContaining('Skipped 1 effect'), findsOneWidget);
      },
    );
  });
}

