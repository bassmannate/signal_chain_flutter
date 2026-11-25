import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/connection/connection_bar_widget.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/main.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  const ms60bPort = MidiPortDescriptor(
    id: 'zoom_ms60bp',
    name: 'ZOOM MS-60B+',
    manufacturer: 'Zoom Corporation',
    isInput: true,
    isOutput: true,
  );

  Future<({
    MockMidiTransport transport,
    DeviceConnectionController connection,
    PatchEditorController editor,
    PatchLibraryController library,
  })> createOfflineHarness({
    DeviceFamily initialFamily = DeviceFamily.zoomMs60bPlus,
    Patch? initialPatch,
    List<Patch> initialLibrary = const [],
  }) async {
    final transport = MockMidiTransport(initialPorts: const [ms60bPort]);
    final connection = DeviceConnectionController(
      transport: transport,
      defaultFamily: initialFamily,
      enableHotPlugPolling: false,
      pacingDelayOverride: Duration.zero,
      isTest: true,
    );
    final repo = InMemoryPatchLibraryRepository(initialPatches: initialLibrary);
    final library = PatchLibraryController(
      repository: repo,
      preferencesRepository: InMemoryPreferencesRepository(),
      importFileSystem: InMemoryImportFileSystem(),
    );
    await library.refresh();

    final defaultSample = initialPatch ??
        Patch(
          id: 'zoom_sample_slap_punch',
          name: 'Slap & Punch',
          deviceFamily: initialFamily,
          slots: const [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x01000010',
              effectName: 'DYN Comp',
              isEnabled: true,
              parameters: [
                ParameterValue(
                  descriptor: ParameterDescriptor(
                    id: 'p0',
                    name: 'Sense',
                    min: 0,
                    max: 10,
                    defaultValue: 6,
                  ),
                  currentValue: 7.0,
                ),
              ],
            ),
          ],
          metadata: const {'tempo': 120},
        );

    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: defaultSample,
    )..setLibraryController(library);

    return (
      transport: transport,
      connection: connection,
      editor: editor,
      library: library,
    );
  }

  group('Offline DeviceFamily Lifecycle', () {
    testWidgets(
      'switching offline device dropdown to Zoom MS-50G+, adding MS-50G+ effect, and saving to library persists DeviceFamily.zoomMs50gPlus',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final h = await createOfflineHarness();

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  ConnectionBarWidget(
                    connectionController: h.connection,
                    editorController: h.editor,
                    libraryController: h.library,
                  ),
                  Expanded(
                    child: SignalChainStripWidget(controller: h.editor),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(h.connection.activeFamily, equals(DeviceFamily.zoomMs60bPlus));
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));

        // Switch offline device selector from MS-60B+ to MS-50G+ via dropdown
        await tester.tap(find.byKey(const Key('device_family_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zoom MS-50G+').last);
        await tester.pumpAndSettle();

        expect(h.connection.activeFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.slots, isEmpty);
        expect(h.editor.isDirty, isFalse);

        // SignalChainStripWidget must still render header & + Add Effect on empty Zoom patch
        expect(find.byKey(const Key('patch_name_textfield')), findsOneWidget);
        expect(find.byKey(const Key('add_effect_slot_button')), findsOneWidget);

        // Add MS-50G+ effect (TB MK1.5: 0x030000E0) and rename
        expect(h.editor.addEffectSlot(effectId: '0x030000E0'), isTrue);
        h.editor.updatePatchName('50G Fuzz');
        await tester.pumpAndSettle();

        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.slots.length, equals(1));
        expect(h.editor.patch?.slots.first.effectId, equals('0x030000E0'));

        // Save to library via toolbar button
        await tester.tap(find.byKey(const Key('save_to_library_button')));
        await tester.pumpAndSettle();

        final savedPatches = await h.library.repository.getAllPatches();
        expect(savedPatches, hasLength(1));
        expect(savedPatches.first.name, equals('50G Fuzz'));
        expect(
          savedPatches.first.deviceFamily,
          equals(DeviceFamily.zoomMs50gPlus),
        );
        expect(
          savedPatches.first.deviceFamily,
          isNot(equals(DeviceFamily.zoomMs60bPlus)),
        );
      },
    );

    test(
      'switching offline from MS-60B+ to MS-50G+ on a dirty unsaved draft adopts DeviceFamily.zoomMs50gPlus',
      () async {
        final h = await createOfflineHarness();

        // User edits the default blank/initial draft before remembering to switch device
        h.editor.updatePatchName('My Draft');
        expect(h.editor.isDirty, isTrue);
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));

        // Switching within same generation adopts MS-50G+ without dropping draft slots
        h.connection.selectDeviceFamily(DeviceFamily.zoomMs50gPlus);

        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.name, equals('My Draft'));
        expect(h.editor.patch?.slots, hasLength(1));

        await h.library.savePatch(h.editor.patch!);
        final saved = await h.library.repository.getAllPatches();
        expect(saved.single.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
      },
    );

    testWidgets(
      'creating a new patch offline on Zoom MS-70CDR+, Zoom B1X FOUR, and Line 6 Bass POD Pro sets matching deviceFamily and slot structure',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final h = await createOfflineHarness();

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  ConnectionBarWidget(
                    connectionController: h.connection,
                    editorController: h.editor,
                    libraryController: h.library,
                  ),
                  Expanded(
                    child: SignalChainStripWidget(controller: h.editor),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Zoom MS-70CDR+
        h.connection.selectDeviceFamily(DeviceFamily.zoomMs70cdrPlus);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('new_patch_button')));
        await tester.pumpAndSettle();
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs70cdrPlus));
        expect(h.editor.patch?.slots, isEmpty);
        expect(h.editor.patch?.programNumber, isNull);
        expect(h.editor.isDirty, isFalse);

        // 2. Zoom B1X FOUR
        h.connection.selectDeviceFamily(DeviceFamily.zoomB1xFour);
        await tester.pumpAndSettle();
        final b1xNew = h.editor.createNewPatch();
        await tester.pumpAndSettle();
        expect(b1xNew.deviceFamily, equals(DeviceFamily.zoomB1xFour));
        expect(b1xNew.slots, isEmpty);
        expect(b1xNew.programNumber, isNull);

        // 3. Line 6 Bass POD Pro -> 4 fixed Amp/Cab/Comp/FX slots
        h.connection.selectDeviceFamily(DeviceFamily.line6BassPodPro);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('new_patch_button')));
        await tester.pumpAndSettle();
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.line6BassPodPro));
        expect(h.editor.patch?.slots, hasLength(4));
        expect(h.editor.patch?.slots[0].effectId, startsWith('line6_amp_'));
        expect(h.editor.patch?.slots[1].effectId, startsWith('line6_cab_'));
        expect(h.editor.patch?.slots[2].effectId, equals('line6_comp'));
        expect(h.editor.patch?.slots[3].effectId, startsWith('line6_fx_'));
        expect(h.editor.patch?.programNumber, isNull);
      },
    );

    testWidgets(
      'cross-generation offline switch while dirty guards with confirmDiscardOrSaveUnsavedChanges',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final h = await createOfflineHarness(
          initialFamily: DeviceFamily.zoomMs50gPlus,
        );
        h.editor.updatePatchName('Unsaved50G');

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  ConnectionBarWidget(
                    connectionController: h.connection,
                    editorController: h.editor,
                    libraryController: h.library,
                  ),
                  Expanded(
                    child: SignalChainStripWidget(controller: h.editor),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Attempt cross-generation switch to Line 6 Bass POD Pro -> Cancel keeps MS-50G+
        await tester.tap(find.byKey(const Key('device_family_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Line 6 Bass Pod Pro').last);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('unsaved_changes_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('unsaved_cancel_button')));
        await tester.pumpAndSettle();

        expect(h.connection.activeFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.isDirty, isTrue);

        // Retry cross-generation switch -> Save to Library saves under MS-50G+, then switches to Line 6
        await tester.tap(find.byKey(const Key('device_family_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Line 6 Bass Pod Pro').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('unsaved_save_library_button')));
        await tester.pumpAndSettle();

        final saved = await h.library.repository.getAllPatches();
        expect(saved, hasLength(1));
        expect(saved.single.name, equals('Unsaved50G'));
        expect(saved.single.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));

        expect(h.connection.activeFamily, equals(DeviceFamily.line6BassPodPro));
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.line6BassPodPro));
        expect(h.editor.patch?.slots, hasLength(4));
        expect(h.editor.isDirty, isFalse);
      },
    );

    test(
      'loading a saved MS-50G+ patch while connected to MS-60B+ preserves MS-50G+ deviceFamily and triggers Phase 2C missing-effect detection',
      () async {
        final ms50gSavedPatch = const Patch(
          id: 'saved_50g_lead',
          name: '50G Fuzz Lead',
          deviceFamily: DeviceFamily.zoomMs50gPlus,
          slots: [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x030000E0', // TB MK1.5 (MS-50G+ exclusive)
              effectName: 'TB MK1.5',
              isEnabled: true,
              parameters: [
                ParameterValue(
                  descriptor: ParameterDescriptor(
                    id: 'p0',
                    name: 'Level',
                    min: 0,
                    max: 100,
                    defaultValue: 50,
                  ),
                  currentValue: 75,
                ),
              ],
            ),
          ],
          metadata: {'tempo': 120},
        );

        final h = await createOfflineHarness(
          initialFamily: DeviceFamily.zoomMs60bPlus,
          initialLibrary: [ms50gSavedPatch],
        );

        // Connect to MS-60B+
        await h.connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: false,
          autoSyncBank: false,
          autoDiscoverEffects: false,
        );

        // Load saved MS-50G+ patch from library
        h.library.loadIntoEditor(ms50gSavedPatch, h.editor);

        expect(h.connection.activeFamily, equals(DeviceFamily.zoomMs60bPlus));
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.slots.single.effectId, equals('0x030000E0'));

        // Phase 2C missing-effect detection triggers against connected MS-60B+
        final report = h.editor.activePatchCompatibilityReport;
        expect(report.hasMissingEffects, isTrue);
        expect(report.missingSlotIndices, contains(0));
        expect(report.missingSlots.single.formattedEffectId, equals('0x030000E0'));

        // Disconnecting and switching offline while a saved preset is loaded preserves its MS-50G+ origin
        await h.connection.disconnect();
        h.connection.selectDeviceFamily(DeviceFamily.zoomMs70cdrPlus);
        expect(h.editor.patch?.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
        expect(h.editor.patch?.slots.single.effectId, equals('0x030000E0'));
      },
    );

    testWidgets(
      'SignalChainApp starts offline and switching device to MS-50G+ saves new patch as zoomMs50gPlus',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final repo = InMemoryPatchLibraryRepository();
        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          enableHotPlugPolling: false,
          pacingDelayOverride: Duration.zero,
          isTest: true,
        );
        final library = PatchLibraryController(
          repository: repo,
          preferencesRepository: InMemoryPreferencesRepository(),
          importFileSystem: InMemoryImportFileSystem(),
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: PatchEditorController.createBlankPatch(
            DeviceFamily.zoomMs60bPlus,
          ),
        )..setLibraryController(library);

        await tester.pumpWidget(
          SignalChainApp(
            transport: transport,
            libraryRepository: repo,
            connectionController: connection,
            editorController: editor,
            libraryController: library,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('device_family_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zoom MS-50G+').last);
        await tester.pumpAndSettle();

        expect(editor.addEffectSlot(effectId: '0x030000E0'), isTrue);
        editor.updatePatchName('App50G');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('save_to_library_button')));
        await tester.pumpAndSettle();

        final saved = await repo.getAllPatches();
        expect(saved, hasLength(1));
        expect(saved.single.deviceFamily, equals(DeviceFamily.zoomMs50gPlus));
      },
    );
  });
}
