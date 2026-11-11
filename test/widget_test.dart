import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/features/connection/connection_bar_widget.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/features/editor/slot_inspector_widget.dart';
import 'package:signal_chain_flutter/features/library/patch_library_drawer_or_panel.dart';
import 'package:signal_chain_flutter/main.dart';

void main() {
  testWidgets('SignalChainApp renders full studio UI on desktop wide screen', (WidgetTester tester) async {
    // Set a wide desktop screen size (1200 x 800)
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SignalChainApp());
    await tester.pumpAndSettle();

    // 1. Verify ConnectionBarWidget elements
    expect(find.byType(ConnectionBarWidget), findsOneWidget);
    expect(find.text('DISCONNECTED'), findsOneWidget);
    expect(find.byKey(const Key('midi_port_dropdown')), findsOneWidget);
    expect(find.text('Zoom MS-60B+'), findsWidgets);
    expect(find.byKey(const Key('pull_patch_button')), findsOneWidget);
    expect(find.byKey(const Key('push_patch_button')), findsOneWidget);
    expect(find.byKey(const Key('save_to_library_button')), findsOneWidget);

    // 2. Verify SignalChainStripWidget elements
    expect(find.byType(SignalChainStripWidget), findsOneWidget);
    expect(find.text('SIGNAL CHAIN (3 SLOTS)'), findsOneWidget);
    expect(find.byKey(const Key('effect_slot_0')), findsOneWidget);
    expect(find.byKey(const Key('effect_slot_1')), findsOneWidget);
    expect(find.byKey(const Key('effect_slot_2')), findsOneWidget);
    expect(find.text('DYN Comp'), findsWidgets);
    expect(find.text('Bass Preamp'), findsOneWidget);
    expect(find.text('Bass Drive'), findsOneWidget);

    // 3. Verify SlotInspectorWidget elements
    expect(find.byType(SlotInspectorWidget), findsOneWidget);
    expect(find.text('SLOT #1'), findsOneWidget);
    expect(find.text('Sense'), findsOneWidget);
    expect(find.text('Attack'), findsOneWidget);
    expect(find.text('Tone'), findsOneWidget);

    // 4. Verify PatchLibraryDrawerOrPanel side panel elements
    expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);
    expect(find.text('PRESET LIBRARY'), findsOneWidget);
    expect(find.byKey(const Key('library_search_input')), findsOneWidget);
    expect(find.text('Slap & Punch'), findsWidgets);
    expect(find.text('Classic SVT'), findsOneWidget);

    // 5. Test interaction: toggle slot bypass
    final toggleSlot0Button = find.byKey(const Key('toggle_slot_0_button'));
    expect(toggleSlot0Button, findsOneWidget);
    await tester.tap(toggleSlot0Button);
    await tester.pumpAndSettle();

    // Dirty badge should appear
    expect(find.text('UNSAVED'), findsOneWidget);

    // 6. Test interaction: select slot #2
    final slot1Card = find.byKey(const Key('effect_slot_1'));
    await tester.tap(slot1Card);
    await tester.pumpAndSettle();

    // Inspector should now show Slot #2 (Bass Preamp)
    expect(find.text('SLOT #2'), findsOneWidget);
    expect(find.text('Bass'), findsOneWidget);
    expect(find.text('Mid'), findsOneWidget);
    expect(find.text('Treble'), findsOneWidget);

    // 7. Test interaction: preset library search
    final searchField = find.byKey(const Key('library_search_input'));
    await tester.enterText(searchField, 'SVT');
    await tester.pumpAndSettle();

    expect(find.text('Classic SVT'), findsOneWidget);
    // 'Slap & Punch' in library list should now be filtered out (only in strip header if loaded)
    expect(find.byKey(const Key('preset_card_zoom_sample_slap_punch')), findsNothing);
    expect(find.byKey(const Key('preset_card_line6_sample_svt_classic')), findsOneWidget);
  });

  testWidgets('SignalChainApp adapts to compact screen with drawer', (WidgetTester tester) async {
    // Set a compact mobile screen size (600 x 900)
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SignalChainApp());
    await tester.pumpAndSettle();

    // Side panel should not be embedded directly in the row on compact screen
    // (it is available in the endDrawer)
    expect(find.byType(PatchLibraryDrawerOrPanel), findsNothing);

    // Tap toggle library icon in toolbar
    final toggleLibraryButton = find.byTooltip('Toggle Preset Library');
    expect(toggleLibraryButton, findsOneWidget);
    await tester.tap(toggleLibraryButton);
    await tester.pumpAndSettle();

    // Drawer should open and show PatchLibraryDrawerOrPanel
    expect(find.byType(PatchLibraryDrawerOrPanel), findsOneWidget);
    expect(find.text('PRESET LIBRARY'), findsOneWidget);
  });

  testWidgets('PatchLibraryDrawerOrPanel opens import and export dialogs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SignalChainApp());
    await tester.pumpAndSettle();

    // Test Export Dialog
    final exportButton = find.byKey(const Key('export_patch_zoom_sample_slap_punch_button'));
    expect(exportButton, findsOneWidget);
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    expect(find.text('Export: Slap & Punch'), findsOneWidget);
    expect(find.byKey(const Key('export_json_text')), findsOneWidget);
    expect(find.byKey(const Key('copy_json_button')), findsOneWidget);

    // Switch to SysEx tab
    await tester.tap(find.text('SysEx Hex Dump'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export_sysex_text')), findsOneWidget);
    expect(find.byKey(const Key('copy_sysex_button')), findsOneWidget);

    // Close export dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Test Import Dialog
    final importButton = find.byKey(const Key('import_preset_button'));
    expect(importButton, findsOneWidget);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    expect(find.text('Import Preset (JSON / SysEx)'), findsOneWidget);
    final inputField = find.byKey(const Key('import_text_field'));
    expect(inputField, findsOneWidget);

    // Enter JSON patch
    await tester.enterText(inputField, '''
{
  "id": "imported_test_preset",
  "name": "Imported Slap",
  "deviceFamily": "zoomMs60bPlus",
  "slots": []
}
''');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_import_button')));
    await tester.pumpAndSettle();

    expect(find.text('Imported Slap'), findsOneWidget);
  });
}
