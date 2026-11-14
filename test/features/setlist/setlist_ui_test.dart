@Timeout(Duration(seconds: 10))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/core/storage/setlist_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_controller.dart';
import 'package:signal_chain_flutter/features/setlist/setlist_performance_view.dart';
import 'package:signal_chain_flutter/main.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/models/setlist.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  Patch makePatch(String id, String name, {double val = 50}) {
    return Patch(
      id: id,
      name: name,
      deviceFamily: DeviceFamily.zoomMs60bPlus,
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
                max: 100,
                defaultValue: 50,
              ),
              currentValue: val,
            ),
          ],
        ),
      ],
      metadata: const {'tempo': 120},
    );
  }

  Future<void> pumpViewport(
    WidgetTester tester,
    Size size, {
    required SetlistController setlistController,
    required DeviceConnectionController connectionController,
    required PatchEditorController editorController,
    required PatchLibraryController libraryController,
    required MockMidiTransport transport,
    required InMemoryPatchLibraryRepository libRepo,
    required InMemorySetlistRepository setRepo,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      SignalChainApp(
        transport: transport,
        libraryRepository: libRepo,
        setlistRepository: setRepo,
        connectionController: connectionController,
        editorController: editorController,
        libraryController: libraryController,
        setlistController: setlistController,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Setlist & Stage Mode UI', () {
    testWidgets('manages setlists in Setlists tab and steps through Stage Mode at 1440x900', (tester) async {
      final p1 = makePatch('p1', 'Opener Clean', val: 35);
      final p2 = makePatch('p2', 'Heavy Chorus', val: 85);

      final transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_zoom',
            name: 'Zoom MS-60B+ (Simulated)',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      final connection = DeviceConnectionController(
        transport: transport,
        enableHotPlugPolling: false,
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
      );
      final setRepo = InMemorySetlistRepository(
        initialSetlists: const [
          Setlist(
            id: 's1',
            name: 'Live Gig',
            entries: [
              SetlistEntry(
                id: 'e1',
                patchId: 'p1',
                songTitle: 'Intro Song',
                performanceNotes: 'Fingerstyle',
              ),
              SetlistEntry(
                id: 'e2',
                patchId: 'p2',
                songTitle: 'Main Riff',
                tempoOverride: 138,
              ),
            ],
          ),
        ],
      );
      final setlistController = SetlistController(
        repository: setRepo,
        libraryController: library,
        editorController: editor,
        connectionController: connection,
        transport: transport,
      );

      addTearDown(() {
        setlistController.dispose();
        library.dispose();
        editor.dispose();
        connection.dispose();
        transport.dispose();
      });

      await pumpViewport(
        tester,
        const Size(1440, 900),
        setlistController: setlistController,
        connectionController: connection,
        editorController: editor,
        libraryController: library,
        transport: transport,
        libRepo: libRepo,
        setRepo: setRepo,
      );

      // Switch to Setlists tab in docked panel
      await tester.tap(find.byKey(const Key('library_tab_setlists')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('setlist_entries_list')), findsOneWidget);

      // Enter Stage Mode
      await tester.tap(find.byKey(const Key('toggle_performance_mode_button')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('stage_index_badge')), findsOneWidget);
      expect(find.text('01 / 02'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('stage_song_title'))).data,
        equals('Intro Song'),
      );

      // Step to Next entry
      await tester.tap(find.byKey(const Key('setlist_next_button')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('02 / 02'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('stage_song_title'))).data,
        equals('Main Riff'),
      );
      expect(find.text('138 BPM'), findsOneWidget);

      // Toggle live stompbox bypass in Stage Mode
      await tester.tap(find.byKey(const Key('stage_stomp_slot_0')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(editor.patch?.slots.first.isEnabled, isFalse);

      // Step back to Previous entry
      await tester.tap(find.byKey(const Key('setlist_prev_button')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('01 / 02'), findsOneWidget);

      // Exit Stage Mode back to Studio Editor
      await tester.tap(find.byKey(const Key('exit_stage_mode_button')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('stage_index_badge')), findsNothing);
    });

    for (final viewport in [const Size(390, 844), const Size(1024, 600)]) {
      testWidgets('Stage Mode renders cleanly without overflow at ${viewport.width.toInt()}x${viewport.height.toInt()}', (tester) async {
        final p1 = makePatch('p1', 'Stage Patch');
        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          enableHotPlugPolling: false,
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: p1,
        );
        final libRepo = InMemoryPatchLibraryRepository(initialPatches: [p1]);
        final library = PatchLibraryController(
          repository: libRepo,
          preferencesRepository: InMemoryPreferencesRepository(),
        );
        final setRepo = InMemorySetlistRepository(
          initialSetlists: const [
            Setlist(
              id: 's1',
              name: 'Compact Set',
              entries: [
                SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Track One'),
              ],
            ),
          ],
        );
        final setlistController = SetlistController(
          repository: setRepo,
          libraryController: library,
          editorController: editor,
          connectionController: connection,
          transport: transport,
        );

        addTearDown(() {
          setlistController.dispose();
          library.dispose();
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await pumpViewport(
          tester,
          viewport,
          setlistController: setlistController,
          connectionController: connection,
          editorController: editor,
          libraryController: library,
          transport: transport,
          libRepo: libRepo,
          setRepo: setRepo,
        );

        await tester.tap(find.byKey(const Key('toggle_performance_mode_button')));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const Key('stage_song_title')), findsOneWidget);
        expect(find.byKey(const Key('setlist_prev_button')), findsOneWidget);
        expect(find.byKey(const Key('setlist_next_button')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'hides docked library panel for full-width Stage Mode and switches setlists at 1280x800',
      (tester) async {
        final p1 = makePatch('p1', 'Set A Clean');
        final p2 = makePatch('p2', 'Set B Drive');
        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          enableHotPlugPolling: false,
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
        );
        final setRepo = InMemorySetlistRepository(
          initialSetlists: const [
            Setlist(
              id: 's1',
              name: 'Club Set',
              entries: [
                SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Opening Tune'),
              ],
            ),
            Setlist(
              id: 's2',
              name: 'Encore Set',
              entries: [
                SetlistEntry(id: 'e2', patchId: 'p2', songTitle: 'Encore Song'),
              ],
            ),
          ],
        );
        final setlistController = SetlistController(
          repository: setRepo,
          libraryController: library,
          editorController: editor,
          connectionController: connection,
          transport: transport,
        );

        addTearDown(() {
          setlistController.dispose();
          library.dispose();
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await pumpViewport(
          tester,
          const Size(1280, 800),
          setlistController: setlistController,
          connectionController: connection,
          editorController: editor,
          libraryController: library,
          transport: transport,
          libRepo: libRepo,
          setRepo: setRepo,
        );

        // Before Stage Mode: docked library panel is visible on 1280x800
        expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);
        expect(find.byType(SetlistPerformanceView), findsNothing);

        // Enter Stage Mode
        await tester.tap(find.byKey(const Key('toggle_performance_mode_button')));
        await tester.pump(const Duration(milliseconds: 50));

        // Docked library panel is hidden and SetlistPerformanceView spans full 1280px width
        expect(find.byType(PatchLibraryDrawerOrPanel), findsNothing);
        expect(find.byType(SetlistPerformanceView), findsOneWidget);
        final stageSize = tester.getSize(find.byType(SetlistPerformanceView));
        expect(stageSize.width, equals(1280.0));

        // Switch setlist directly from Stage Mode header dropdown
        expect(
          tester.widget<Text>(find.byKey(const Key('stage_song_title'))).data,
          equals('Opening Tune'),
        );
        await tester.tap(find.byKey(const Key('stage_setlist_selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Encore Set (1)').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const Key('stage_song_title'))).data,
          equals('Encore Song'),
        );

        // Exit Stage Mode: docked library panel is restored
        await tester.tap(find.byKey(const Key('exit_stage_mode_button')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(SetlistPerformanceView), findsNothing);
        expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);
      },
    );

    testWidgets(
      'landscape Stage Mode renders ~22% left scrollable setlist, ~78% giant effect stompboxes, and toggles tuner & bypass',
      (tester) async {
        Patch makeMultiSlotPatch(String id, String name) {
          return Patch(
            id: id,
            name: name,
            deviceFamily: DeviceFamily.zoomMs60bPlus,
            slots: const [
              EffectSlot(
                slotIndex: 0,
                effectId: '0x01000010',
                effectName: 'DYN Comp',
                isEnabled: true,
              ),
              EffectSlot(
                slotIndex: 1,
                effectId: '0x02000010',
                effectName: 'Bass Drive',
                isEnabled: true,
              ),
              EffectSlot(
                slotIndex: 2,
                effectId: '0x04000010',
                effectName: 'Super Cho',
                isEnabled: false,
              ),
            ],
            metadata: const {'tempo': 120},
          );
        }

        final patches = List.generate(
          12,
          (i) => makeMultiSlotPatch('p$i', 'Patch ${i + 1}'),
        );
        final entries = List.generate(
          12,
          (i) => SetlistEntry(
            id: 'e$i',
            patchId: 'p$i',
            songTitle: 'Song ${i + 1}',
          ),
        );

        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          enableHotPlugPolling: false,
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: patches.first,
        );
        final libRepo = InMemoryPatchLibraryRepository(initialPatches: patches);
        final library = PatchLibraryController(
          repository: libRepo,
          preferencesRepository: InMemoryPreferencesRepository(),
        );
        final setRepo = InMemorySetlistRepository(
          initialSetlists: [
            Setlist(id: 's1', name: 'Full Gig Set', entries: entries),
          ],
        );
        final setlistController = SetlistController(
          repository: setRepo,
          libraryController: library,
          editorController: editor,
          connectionController: connection,
          transport: transport,
        );

        addTearDown(() {
          setlistController.dispose();
          library.dispose();
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await pumpViewport(
          tester,
          const Size(1280, 800),
          setlistController: setlistController,
          connectionController: connection,
          editorController: editor,
          libraryController: library,
          transport: transport,
          libRepo: libRepo,
          setRepo: setRepo,
        );

        // Toggle tuner from top toolbar
        expect(find.byKey(const Key('toolbar_tuner_toggle_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('toolbar_tuner_toggle_button')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(connection.isTunerActive, isTrue);

        // Enter Stage Mode
        await tester.tap(find.byKey(const Key('toggle_performance_mode_button')));
        await tester.pump(const Duration(milliseconds: 50));

        // Verify landscape dashboard widgets
        expect(find.byKey(const Key('stage_landscape_left_panel')), findsOneWidget);
        expect(find.byKey(const Key('stage_landscape_patch_box')), findsOneWidget);
        expect(find.byKey(const Key('stage_setlist_patch_list')), findsOneWidget);
        expect(find.byKey(const Key('stage_landscape_effects_panel')), findsOneWidget);
        expect(find.byKey(const Key('stage_tuner_toggle_button')), findsOneWidget);

        // Left panel is ~22% width (~281.6px at 1280px width), right panel is ~78% (~998.4px)
        final leftPanelRect =
            tester.getRect(find.byKey(const Key('stage_landscape_left_panel')));
        final rightPanelRect =
            tester.getRect(find.byKey(const Key('stage_landscape_effects_panel')));
        expect(leftPanelRect.width, closeTo(281.6, 5.0));
        expect(rightPanelRect.width, closeTo(998.4, 5.0));

        // Scrollable setlist patch list sits inside the left panel
        final listRect =
            tester.getRect(find.byKey(const Key('stage_setlist_patch_list')));
        expect(listRect.left, greaterThanOrEqualTo(leftPanelRect.left));
        expect(listRect.right, lessThanOrEqualTo(leftPanelRect.right + 1.0));

        // Right panel displays ONLY the current patch's large effect stompbox tiles
        expect(find.byKey(const Key('stage_stomp_slot_0')), findsOneWidget);
        expect(find.byKey(const Key('stage_stomp_slot_1')), findsOneWidget);
        expect(find.byKey(const Key('stage_stomp_slot_2')), findsOneWidget);
        final slot0Rect =
            tester.getRect(find.byKey(const Key('stage_stomp_slot_0')));
        expect(slot0Rect.left, greaterThanOrEqualTo(rightPanelRect.left));
        expect(slot0Rect.width, greaterThan(300.0));
        expect(slot0Rect.height, greaterThan(200.0));

        // Tapping a stompbox tile in the right panel toggles its bypass state
        expect(editor.patch?.slots[0].isEnabled, isTrue);
        await tester.tap(find.byKey(const Key('stage_stomp_slot_0')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(editor.patch?.slots[0].isEnabled, isFalse);

        // Tapping a setlist tile in the left list activates that patch and resets tuner
        await tester.tap(find.byKey(const Key('stage_setlist_entry_tile_3')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(setlistController.activeEntryIndex, equals(3));
        expect(connection.isTunerActive, isFalse);
        expect(
          tester.widget<Text>(find.byKey(const Key('stage_song_title'))).data,
          equals('Song 4'),
        );

        // Toggle tuner from Stage Mode button
        await tester.tap(find.byKey(const Key('stage_tuner_toggle_button')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(setlistController.isTunerActive, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'portrait Stage Mode at 390x844 preserves vertical layout and includes tuner toggle',
      (tester) async {
        final p1 = makePatch('p1', 'Portrait Patch');
        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          enableHotPlugPolling: false,
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: p1,
        );
        final libRepo = InMemoryPatchLibraryRepository(initialPatches: [p1]);
        final library = PatchLibraryController(
          repository: libRepo,
          preferencesRepository: InMemoryPreferencesRepository(),
        );
        final setRepo = InMemorySetlistRepository(
          initialSetlists: const [
            Setlist(
              id: 's1',
              name: 'Portrait Set',
              entries: [
                SetlistEntry(id: 'e1', patchId: 'p1', songTitle: 'Portrait Song'),
              ],
            ),
          ],
        );
        final setlistController = SetlistController(
          repository: setRepo,
          libraryController: library,
          editorController: editor,
          connectionController: connection,
          transport: transport,
        );

        addTearDown(() {
          setlistController.dispose();
          library.dispose();
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await pumpViewport(
          tester,
          const Size(390, 844),
          setlistController: setlistController,
          connectionController: connection,
          editorController: editor,
          libraryController: library,
          transport: transport,
          libRepo: libRepo,
          setRepo: setRepo,
        );

        await tester.tap(find.byKey(const Key('toggle_performance_mode_button')));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const Key('stage_landscape_patch_box')), findsNothing);
        expect(find.byKey(const Key('stage_setlist_patch_list')), findsNothing);
        expect(find.byKey(const Key('stage_landscape_effects_panel')), findsNothing);
        expect(find.byKey(const Key('stage_tuner_toggle_button')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

