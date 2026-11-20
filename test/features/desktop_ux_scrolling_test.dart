import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/effect_bank_palette_widget.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/features/theme/horizontal_mouse_scroll_view.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('AppScrollBehavior & HorizontalMouseScrollView', () {
    test('AppScrollBehavior includes mouse, touch, stylus, and trackpad dragDevices', () {
      const behavior = AppScrollBehavior();
      expect(
        behavior.dragDevices,
        containsAll(const [
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        ]),
      );
    });

    testWidgets(
      'HorizontalMouseScrollView reserves bottom scrollbarGutter and converts vertical mouse-wheel PointerScrollEvent into clamped horizontal scroll',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 70,
                child: HorizontalMouseScrollView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: List.generate(
                      10,
                      (i) => SizedBox(
                        width: 100,
                        height: 40,
                        child: Center(child: Text('Item $i')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        expect(
          scrollView.padding,
          equals(const EdgeInsets.fromLTRB(8, 4, 8, 18)),
        );

        final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
        expect(scrollbar.interactive, isTrue);
        expect(controller.offset, equals(0.0));
        expect(controller.position.maxScrollExtent, greaterThan(0.0));

        final center = tester.getCenter(find.byType(HorizontalMouseScrollView));

        // Scroll down on mouse wheel -> scroll right horizontally
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, equals(120.0));

        // Overshoot right -> clamped to maxScrollExtent
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, 5000),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, equals(controller.position.maxScrollExtent));

        // Scroll up on mouse wheel beyond 0 -> clamped to minScrollExtent (0.0)
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, -5000),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, equals(0.0));
      },
    );

    testWidgets(
      'SignalChainStripWidget and Library device chips support horizontal mouse-wheel scrolling without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
        );
        const testPatch = Patch(
          id: 'scroll_patch',
          name: 'ScrollTest',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          tags: ['slap', 'funk', 'modern'],
          slots: [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x01000010',
              effectName: 'DYN Comp',
              isEnabled: true,
              parameters: [],
            ),
            EffectSlot(
              slotIndex: 1,
              effectId: '0x02000010',
              effectName: 'Bass Preamp',
              isEnabled: true,
              parameters: [],
            ),
            EffectSlot(
              slotIndex: 2,
              effectId: '0x03000010',
              effectName: 'Bass Drive',
              isEnabled: true,
              parameters: [],
            ),
            EffectSlot(
              slotIndex: 3,
              effectId: '0x08000010',
              effectName: 'Delay',
              isEnabled: true,
              parameters: [],
            ),
          ],
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: testPatch,
        );
        final libraryRepo = InMemoryPatchLibraryRepository(
          initialPatches: const [testPatch],
        );
        final library = PatchLibraryController(repository: libraryRepo);
        await library.refresh();

        addTearDown(() {
          library.dispose();
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 420,
                    child: SignalChainStripWidget(controller: editor),
                  ),
                  SizedBox(
                    width: 260,
                    height: 390,
                    child: PatchLibraryDrawerOrPanel(
                      libraryController: library,
                      editorController: editor,
                      isPanel: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Effects Chain horizontal scroll with reserved bottom gutter
        final chainScrollFinder = find.descendant(
          of: find.byKey(const Key('signal_chain_horizontal_scroll')),
          matching: find.byType(SingleChildScrollView),
        );
        final chainScroll = tester.widget<SingleChildScrollView>(chainScrollFinder);
        expect(chainScroll.controller!.offset, equals(0.0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(chainScrollFinder),
            scrollDelta: const Offset(0, 140),
          ),
        );
        await tester.pumpAndSettle();
        expect(chainScroll.controller!.offset, greaterThan(0.0));

        // 2. Preset Library device family chips horizontal scroll on narrow width
        final libraryScrollFinder = find.descendant(
          of: find.byKey(const Key('library_filters_horizontal_scroll')),
          matching: find.byType(SingleChildScrollView),
        );
        final libraryScroll = tester.widget<SingleChildScrollView>(libraryScrollFinder);
        expect(libraryScroll.controller!.offset, equals(0.0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(libraryScrollFinder),
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.pumpAndSettle();
        expect(libraryScroll.controller!.offset, greaterThan(0.0));
      },
    );

    testWidgets(
      'EffectBankPaletteWidget filters effects via compact category dropdown',
      (tester) async {
        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
        );
        const testPatch = Patch(
          id: 'palette_patch',
          name: 'PaletteTest',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x01000010',
              effectName: 'DYN Comp',
              isEnabled: true,
              parameters: [],
            ),
          ],
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: testPatch,
        );

        addTearDown(() {
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 500,
                child: EffectBankPaletteWidget(controller: editor),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final allCount = EffectCatalogRegistry.getEffectsForFamily(
          DeviceFamily.zoomMs60bPlus,
        ).length;
        expect(find.text('$allCount EFFECTS'), findsOneWidget);

        // Select 'Delay' from category dropdown
        await tester.tap(find.byKey(const Key('palette_category_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('palette_category_item_Delay')).last);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('palette_category_dropdown')),
            matching: find.text('Delay'),
          ),
          findsOneWidget,
        );
        expect(find.text('$allCount EFFECTS'), findsNothing);

        // Reset back to 'All'
        await tester.tap(find.byKey(const Key('palette_category_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('palette_category_item_All')).last);
        await tester.pumpAndSettle();
        expect(find.text('$allCount EFFECTS'), findsOneWidget);
      },
    );

    testWidgets(
      'PatchLibraryDrawerOrPanel supports multi-select checkbox tag dropdown with AND filtering, summary counts, and Clear tags',
      (tester) async {
        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
        );
        const p1 = Patch(
          id: 'p_slap_funk',
          name: 'Slap Funk',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          tags: ['slap', 'funk'],
          slots: [],
        );
        const p2 = Patch(
          id: 'p_slap_only',
          name: 'Slap Clean',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          tags: ['slap', 'clean'],
          slots: [],
        );
        const p3 = Patch(
          id: 'p_ambient',
          name: 'Ambient Space',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          tags: ['ambient'],
          slots: [],
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: p1,
        );
        final libraryRepo = InMemoryPatchLibraryRepository(
          initialPatches: const [p1, p2, p3],
        );
        final library = PatchLibraryController(repository: libraryRepo);
        await library.refresh();

        addTearDown(() {
          library.dispose();
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 600,
                child: PatchLibraryDrawerOrPanel(
                  libraryController: library,
                  editorController: editor,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially shows "All Tags" and all 3 presets
        expect(find.text('All Tags'), findsOneWidget);
        expect(find.byKey(const Key('library_clear_tags_button')), findsNothing);
        expect(find.byKey(const Key('preset_card_p_slap_funk')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_slap_only')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_ambient')), findsOneWidget);

        // Open multi-select checkbox tag dropdown
        await tester.tap(find.byKey(const Key('library_tags_dropdown_button')));
        await tester.pumpAndSettle();

        // Select 1st tag ('slap') -> menu stays open, summary shows 'slap', 2 presets match
        await tester.tap(
          find.descendant(
            of: find.byType(CheckboxMenuButton),
            matching: find.text('#slap'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<CheckboxMenuButton>(
                find.ancestor(
                  of: find.text('#slap'),
                  matching: find.byType(CheckboxMenuButton),
                ),
              )
              .value,
          isTrue,
        );
        expect(
          find.descendant(
            of: find.byType(CheckboxMenuButton),
            matching: find.text('#funk'),
          ),
          findsOneWidget,
        );
        expect(find.text('slap'), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_slap_funk')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_slap_only')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_ambient')), findsNothing);

        // Select 2nd tag ('funk') without re-opening menu -> summary shows 'Tags (2)', AND-filtered to 1 preset
        await tester.tap(
          find.descendant(
            of: find.byType(CheckboxMenuButton),
            matching: find.text('#funk'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tags (2)'), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_slap_funk')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_slap_only')), findsNothing);
        expect(find.byKey(const Key('preset_card_p_ambient')), findsNothing);

        // Select 3rd tag ('ambient') -> no patch has slap + funk + ambient -> empty state
        await tester.tap(
          find.descendant(
            of: find.byType(CheckboxMenuButton),
            matching: find.text('#ambient'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tags (3)'), findsOneWidget);
        expect(find.text('No presets matching filters'), findsOneWidget);

        // Use "Clear tags" action inside menu -> resets to "All Tags" and restores all 3 presets
        await tester.tap(find.byKey(const Key('library_clear_tags_menu_item')));
        await tester.pumpAndSettle();

        expect(find.text('All Tags'), findsOneWidget);
        expect(library.selectedTags, isEmpty);
        expect(
          tester
              .widget<CheckboxMenuButton>(
                find.ancestor(
                  of: find.text('#slap'),
                  matching: find.byType(CheckboxMenuButton),
                ),
              )
              .value,
          isFalse,
        );
        expect(find.byKey(const Key('preset_card_p_slap_funk')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_slap_only')), findsOneWidget);
        expect(find.byKey(const Key('preset_card_p_ambient')), findsOneWidget);
      },
    );

    testWidgets(
      'Mouse drag-and-drop effect reordering still works cleanly inside SignalChainStripWidget with AppScrollBehavior',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
        );
        const testPatch = Patch(
          id: 'dnd_patch',
          name: 'DnDTest',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x01000010',
              effectName: 'DYN Comp',
              isEnabled: true,
              parameters: [],
            ),
            EffectSlot(
              slotIndex: 1,
              effectId: '0x02000010',
              effectName: 'Bass Preamp',
              isEnabled: true,
              parameters: [],
            ),
            EffectSlot(
              slotIndex: 2,
              effectId: '0x08000010',
              effectName: 'Delay',
              isEnabled: true,
              parameters: [],
            ),
          ],
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: testPatch,
        );

        addTearDown(() {
          editor.dispose();
          connection.dispose();
          transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: SignalChainStripWidget(controller: editor),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final startPos = tester.getCenter(find.byKey(const Key('slot_draggable_0')));
        final targetPos = tester.getCenter(find.byKey(const Key('slot_drag_target_2')));

        final gesture = await tester.startGesture(
          startPos,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(targetPos);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(editor.patch!.slots[0].effectName, equals('Delay'));
        expect(editor.patch!.slots[2].effectName, equals('DYN Comp'));
      },
    );
  });
}
