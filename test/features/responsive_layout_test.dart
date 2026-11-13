import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/features/editor/effect_bank_palette_widget.dart';
import 'package:signal_chain_flutter/features/editor/slot_inspector_widget.dart';
import 'package:signal_chain_flutter/features/library/hardware_bank_browser_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/main.dart';

void main() {
  Future<List<FlutterErrorDetails>> pumpAppAtViewport(
    WidgetTester tester,
    Size size, {
    TargetPlatform? platformOverride,
  }) async {
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previousOnError?.call(details);
    };

    if (platformOverride != null) {
      debugDefaultTargetPlatformOverride = platformOverride;
    }

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      FlutterError.onError = previousOnError;
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(const SignalChainApp());
    await tester.pumpAndSettle();
    return errors;
  }

  void expectFitsHorizontally(WidgetTester tester, Finder finder, double maxWidth) {
    expect(finder, findsOneWidget);
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(-0.5));
    expect(rect.right, lessThanOrEqualTo(maxWidth + 0.5));
  }

  group('Milestone 11 Responsive & Adaptive Layout Tests', () {
    testWidgets('Compact phone portrait (390x844): zero overflow and all controls reachable',
        (WidgetTester tester) async {
      const size = Size(390, 844);
      final errors = await pumpAppAtViewport(tester, size);
      expect(errors, isEmpty);

      // 1. Toolbar controls fit within 390px without horizontal clipping
      expectFitsHorizontally(tester, find.byKey(const Key('midi_port_dropdown')), size.width);
      expectFitsHorizontally(tester, find.byKey(const Key('pull_patch_button')), size.width);
      expectFitsHorizontally(tester, find.byKey(const Key('push_patch_button')), size.width);
      expectFitsHorizontally(tester, find.byKey(const Key('save_to_library_button')), size.width);
      expectFitsHorizontally(tester, find.byKey(const Key('toggle_library_button')), size.width);

      // 2. Patch metadata header wraps cleanly within 390px
      expectFitsHorizontally(tester, find.byKey(const Key('patch_name_textfield')), size.width);
      expectFitsHorizontally(tester, find.byKey(const Key('patch_tempo_slider')), size.width);
      expectFitsHorizontally(
        tester,
        find.byKey(const Key('write_to_hardware_slot_button')),
        size.width,
      );

      // 3. Scroll horizontally to Slot 0 in RTL strip and test nudge & bypass controls
      await tester.ensureVisible(find.byKey(const Key('toggle_slot_0_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle_slot_0_button')));
      await tester.pumpAndSettle();
      expect(find.text('UNSAVED'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('move_slot_left_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move_slot_left_0')));
      await tester.pumpAndSettle();

      // 4. Tab toggle switches between Inspector and Effect Palette
      expect(find.byType(SlotInspectorWidget), findsOneWidget);
      expect(find.byType(EffectBankPaletteWidget), findsNothing);

      await tester.tap(find.byKey(const Key('editor_tab_palette')));
      await tester.pumpAndSettle();
      expect(find.byType(EffectBankPaletteWidget), findsOneWidget);
      expect(find.byType(SlotInspectorWidget), findsNothing);

      await tester.tap(find.byKey(const Key('editor_tab_inspector')));
      await tester.pumpAndSettle();

      // 5. EffectPickerDialog opens and searches cleanly at 390x844
      await tester.tap(find.byKey(const Key('open_effect_picker_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('effect_picker_search_input')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // 6. WriteToSlotDialog opens cleanly at 390x844
      await tester.tap(find.byKey(const Key('write_to_hardware_slot_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('write_slot_dropdown')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_write_slot_button')));
      await tester.pumpAndSettle();

      // 7. Library & Hardware Bank endDrawer + Import/Export dialogs open cleanly
      await tester.tap(find.byKey(const Key('toggle_library_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_tab_hardware')));
      await tester.pumpAndSettle();
      expect(find.byType(HardwareBankBrowserWidget), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_tab_local')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export_patch_zoom_sample_slap_punch_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export_json_text')), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_preset_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import_text_field')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
    });

    testWidgets('Short landscape phone (844x390): unified scroll prevents overflow',
        (WidgetTester tester) async {
      const size = Size(844, 390);
      final errors = await pumpAppAtViewport(tester, size);
      expect(errors, isEmpty);

      // Uses page-level vertical scroll for short viewport
      final scrollFinder = find.byKey(const Key('short_viewport_editor_scroll'));
      expect(scrollFinder, findsOneWidget);

      // Scroll down to interact with Inspector and Effect Palette tabs
      await tester.ensureVisible(find.byKey(const Key('editor_tab_palette')));
      await tester.pumpAndSettle();
      expect(find.byType(SlotInspectorWidget), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor_tab_palette')));
      await tester.pumpAndSettle();
      expect(find.byType(EffectBankPaletteWidget), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor_tab_inspector')));
      await tester.pumpAndSettle();

      // Open EffectPickerDialog and WriteToSlotDialog in 844x390 landscape
      await tester.ensureVisible(find.byKey(const Key('open_effect_picker_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_effect_picker_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('effect_picker_search_input')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('write_to_hardware_slot_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('write_to_hardware_slot_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('write_slot_dropdown')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_write_slot_button')));
      await tester.pumpAndSettle();

      // Open Export dialog in 844x390 landscape (previously hardcoded height 380 overflowed)
      await tester.tap(find.byKey(const Key('toggle_library_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export_patch_zoom_sample_slap_punch_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export_json_text')), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
    });

    testWidgets('Keyboard-resized short viewports (390x420 and 844x240): zero overflow',
        (WidgetTester tester) async {
      final portraitErrors = await pumpAppAtViewport(tester, const Size(390, 420));
      expect(portraitErrors, isEmpty);
      expect(find.byKey(const Key('short_viewport_editor_scroll')), findsOneWidget);

      // Resize even shorter (landscape + open keyboard) and open EffectPickerDialog
      tester.view.physicalSize = const Size(844, 240);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('open_effect_picker_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_effect_picker_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('effect_picker_search_input')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(portraitErrors, isEmpty);
    });

    testWidgets('Fire HD 10 tablet (1024x600): side-by-side inspector & palette, library in drawer',
        (WidgetTester tester) async {
      final errors = await pumpAppAtViewport(tester, const Size(1024, 600));
      expect(errors, isEmpty);

      // Inspector and Effect Palette are both visible side-by-side
      expect(find.byType(SlotInspectorWidget), findsOneWidget);
      expect(find.byType(EffectBankPaletteWidget), findsOneWidget);

      // Library/Hardware Bank starts in endDrawer
      expect(find.byType(PatchLibraryDrawerOrPanel), findsNothing);
      await tester.tap(find.byKey(const Key('toggle_library_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);

      expect(errors, isEmpty);
    });

    testWidgets('Desktop (1440x900) and resized desktop windows (720x540, 500x450): zero overflow',
        (WidgetTester tester) async {
      final errors = await pumpAppAtViewport(tester, const Size(1440, 900));
      expect(errors, isEmpty);

      // Full 3-column desktop studio
      expect(find.byType(SlotInspectorWidget), findsOneWidget);
      expect(find.byType(EffectBankPaletteWidget), findsOneWidget);
      expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);
      expect(find.byKey(const Key('toggle_library_button')), findsNothing);

      // Resized medium desktop window (720x540)
      tester.view.physicalSize = const Size(720, 540);
      await tester.pumpAndSettle();
      expect(find.byType(PatchLibraryDrawerOrPanel), findsNothing);
      expect(find.byKey(const Key('toggle_library_button')), findsOneWidget);

      // Resized compact desktop window (500x450)
      tester.view.physicalSize = const Size(500, 450);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('short_viewport_editor_scroll')), findsOneWidget);

      expect(errors, isEmpty);
    });

    testWidgets('Touch platforms use LongPressDraggable while desktop uses immediate Draggable',
        (WidgetTester tester) async {
      // Android uses LongPressDraggable so touch scrolling is never hijacked
      try {
        final androidErrors = await pumpAppAtViewport(
          tester,
          const Size(1024, 600),
          platformOverride: TargetPlatform.android,
        );
        expect(androidErrors, isEmpty);
        expect(find.byType(LongPressDraggable<SlotReorderPayload>), findsWidgets);
        expect(find.byType(LongPressDraggable<EffectDragPayload>), findsWidgets);
        expect(find.byType(Draggable<SlotReorderPayload>), findsNothing);
        expect(find.byType(Draggable<EffectDragPayload>), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Linux desktop uses immediate Draggable for mouse drag-and-drop',
        (WidgetTester tester) async {
      try {
        final linuxErrors = await pumpAppAtViewport(
          tester,
          const Size(1440, 900),
          platformOverride: TargetPlatform.linux,
        );
        expect(linuxErrors, isEmpty);
        expect(find.byType(Draggable<SlotReorderPayload>), findsWidgets);
        expect(find.byType(Draggable<EffectDragPayload>), findsWidgets);
        expect(find.byType(LongPressDraggable<SlotReorderPayload>), findsNothing);
        expect(find.byType(LongPressDraggable<EffectDragPayload>), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
