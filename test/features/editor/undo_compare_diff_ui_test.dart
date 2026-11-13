@Timeout(Duration(seconds: 10))
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_diff_dialog.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_metadata_header_widget.dart';
import 'package:signal_chain_flutter/features/editor/write_to_slot_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_import_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/main.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  EffectCatalogRegistry.ensureInitialized();

  Patch buildTestPatch({String name = 'Slap & Punch', double sense = 5.0}) {
    return Patch(
      id: 'test_patch',
      name: name,
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      metadata: const {'tempo': 120},
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
    );
  }

  testWidgets('Undo/Redo buttons, A/B compare toggle, and PatchDiffDialog work across responsive viewports', (tester) async {
    final transport = MockMidiTransport();
    final connection = DeviceConnectionController(
      transport: transport,
      enableHotPlugPolling: false,
    );
    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: buildTestPatch(),
    );

    for (final size in const [
      Size(390, 844),
      Size(844, 390),
      Size(1200, 800),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatchMetadataHeaderWidget(controller: editor),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    // Perform an edit and verify Undo/Redo + A/B + Diff Dialog
    await tester.tap(find.byKey(const Key('tempo_increment_button')));
    await tester.pump();
    expect(editor.patch?.tempo, equals(121));
    expect(editor.canUndo, isTrue);

    await tester.tap(find.byKey(const Key('undo_button')));
    await tester.pump();
    expect(editor.patch?.tempo, equals(120));
    expect(editor.canRedo, isTrue);

    await tester.tap(find.byKey(const Key('redo_button')));
    await tester.pump();
    expect(editor.patch?.tempo, equals(121));

    // Toggle A/B back to baseline A (120 BPM)
    await tester.tap(find.byKey(const Key('compare_ab_toggle')));
    await tester.pump();
    expect(editor.patch?.tempo, equals(120));

    // Open PatchDiffDialog
    await tester.tap(find.byKey(const Key('compare_diff_button')));
    await tester.pump();
    expect(find.byKey(const Key('patch_diff_dialog')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PatchDiffDialog),
        matching: find.text('120 BPM'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PatchDiffDialog),
        matching: find.text('121 BPM'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('close_diff_dialog_button')));
    await tester.pump();
    expect(find.byKey(const Key('patch_diff_dialog')), findsNothing);

    tester.view.resetPhysicalSize();
    editor.dispose();
    connection.dispose();
    await transport.dispose();
  });

  testWidgets('WriteToSlotDialog shows diff banner and opens PatchDiffDialog for cached bank slot', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final transport = MockMidiTransport();
    final connection = DeviceConnectionController(
      transport: transport,
      enableHotPlugPolling: false,
    );
    connection.updateBankSlot(
      0,
      patchName: 'Old Slot',
      patch: buildTestPatch(name: 'Old Slot', sense: 2.0),
    );
    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: buildTestPatch(name: 'New Slot', sense: 8.0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WriteToSlotDialog(
            editorController: editor,
            connectionController: connection,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('write_slot_diff_banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('write_slot_view_diff_button')));
    await tester.pump();

    expect(find.byKey(const Key('patch_diff_dialog')), findsOneWidget);
    expect(find.text('Old Slot'), findsWidgets);
    expect(find.text('New Slot'), findsWidgets);

    editor.dispose();
    connection.dispose();
    await transport.dispose();
  });

  testWidgets('PatchImportDialog previews diff against active editor via InMemoryImportFileSystem', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final transport = MockMidiTransport();
    final connection = DeviceConnectionController(
      transport: transport,
      enableHotPlugPolling: false,
    );
    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: buildTestPatch(name: 'Editor Patch', sense: 5.0),
    );
    final fakeFs = InMemoryImportFileSystem();
    final library = PatchLibraryController(
      repository: InMemoryPatchLibraryRepository(),
      preferencesRepository: InMemoryPreferencesRepository(),
      importFileSystem: fakeFs,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchImportDialog(
            libraryController: library,
            editorController: editor,
            fileSystemOverride: fakeFs,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('import_tab_paste')));
    await tester.pump();

    const jsonText = '{"id":"imp1","name":"Imported Tone","deviceFamily":"zoomMs60bPlus","slots":[]}';
    await tester.enterText(find.byKey(const Key('import_paste_text_field')), jsonText);
    await tester.tap(find.text('Parse'));
    await tester.pump();

    expect(find.byKey(const Key('import_entry_diff_0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('import_entry_diff_0')));
    await tester.pump();

    expect(find.byKey(const Key('patch_diff_dialog')), findsOneWidget);
    expect(find.text('Imported Tone'), findsWidgets);

    library.dispose();
    editor.dispose();
    connection.dispose();
    await transport.dispose();
  });

  testWidgets('SignalChainApp supports Ctrl+Z and Ctrl+Y keyboard shortcuts when TextField is unfocused', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SignalChainApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Toggle slot 0 bypass -> marks dirty and pushes Undo
    await tester.tap(find.byKey(const Key('toggle_slot_0_button')));
    await tester.pump();
    expect(find.text('UNSAVED'), findsOneWidget);

    // Ctrl+Z -> Undoes bypass and clears UNSAVED
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('UNSAVED'), findsNothing);

    // Ctrl+Y -> Redoes bypass and restores UNSAVED
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('UNSAVED'), findsOneWidget);
  });
}

