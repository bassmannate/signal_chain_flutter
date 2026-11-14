@Timeout(Duration(seconds: 10))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_import_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  final exportRegistry = ExportAdapterRegistry.standard();

  const zoom60bPatch = Patch(
    id: 'ui_zoom_60b',
    name: 'UI 60B Slap',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    programNumber: 2,
    slots: [
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
              defaultValue: 5,
            ),
            currentValue: 8.0,
          ),
        ],
      ),
    ],
  );

  const zoom70cdrPatch = Patch(
    id: 'ui_zoom_70cdr',
    name: 'UI 70CDR Lush',
    deviceFamily: DeviceFamily.zoomMs70cdrPlus,
    programNumber: 5,
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: '0x01000010',
        effectName: 'DYN Comp',
        isEnabled: true,
      ),
    ],
  );

  const line6Patch = Patch(
    id: 'ui_line6_1',
    name: 'UI Bass POD',
    deviceFamily: DeviceFamily.line6BassPodPro,
    programNumber: 1,
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: 'line6_amp_8',
        effectName: 'Rock Classic',
        isEnabled: true,
      ),
    ],
  );

  ({
    PatchLibraryController libraryController,
    PatchEditorController editorController,
    DeviceConnectionController connectionController,
    MockMidiTransport transport,
    InMemoryPatchLibraryRepository repo,
  }) createControllers({
    DeviceFamily initialFamily = DeviceFamily.zoomMs60bPlus,
    InMemoryImportFileSystem? fs,
  }) {
    final transport = MockMidiTransport();
    final connection = DeviceConnectionController(
      transport: transport,
      defaultFamily: initialFamily,
      enableHotPlugPolling: false,
      isTest: true,
    );
    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
    );
    final repo = InMemoryPatchLibraryRepository();
    final library = PatchLibraryController(
      repository: repo,
      preferencesRepository: InMemoryPreferencesRepository(),
      importFileSystem: fs ?? InMemoryImportFileSystem(),
    );
    return (
      libraryController: library,
      editorController: editor,
      connectionController: connection,
      transport: transport,
      repo: repo,
    );
  }

  testWidgets('browses folders, navigates up, and previews selected .zptc file',
      (tester) async {
    final fs = InMemoryImportFileSystem();
    final bytes = exportRegistry
        .adapterFor(ExportFormat.symbiosisZptc)
        .exportPatch(zoom60bPatch)
        .bytes;
    fs.addFile('/memory/Documents/SignalChainExports/BassBank/02_UI_60B_Slap.60bp.zptc', bytes);
    fs.addFile('/memory/Documents/SignalChainExports/ignored.txt', Uint8List.fromList([1, 2]));

    final ctx = createControllers(fs: fs);
    addTearDown(() {
      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchImportDialog(
            libraryController: ctx.libraryController,
            editorController: ctx.editorController,
            fileSystemOverride: fs,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Only supported files + directories appear by default
    expect(find.byKey(const Key('import_fs_entry_BassBank')), findsOneWidget);
    expect(find.byKey(const Key('import_fs_entry_ignored.txt')), findsNothing);

    // Enter subfolder
    await tester.tap(find.byKey(const Key('import_fs_entry_BassBank')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const Key('import_fs_entry_02_UI_60B_Slap.60bp.zptc')),
      findsOneWidget,
    );

    // Select file to preview
    await tester.tap(
      find.byKey(const Key('import_fs_entry_02_UI_60B_Slap.60bp.zptc')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('import_preview_pane')), findsOneWidget);
    expect(find.text('UI 60B Slap'), findsOneWidget);
    expect(find.text('Symbiosis ZPTC (.<model>.zptc)'), findsOneWidget);

    // Navigate back up
    await tester.tap(find.byKey(const Key('import_up_dir_button')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('import_fs_entry_BassBank')), findsOneWidget);
  });

  testWidgets('batch Import Folder supports selective Add to Library', (tester) async {
    final fs = InMemoryImportFileSystem();
    final symPayload = exportRegistry
        .adapterFor(ExportFormat.symbiosisZptc)
        .exportLibrary([zoom60bPatch, zoom70cdrPatch], libraryName: 'Batch');
    for (final entry in symPayload.folderEntries) {
      fs.addFile('/memory/Documents/SignalChainExports/Batch/${entry.fileName}', entry.bytes);
    }

    final ctx = createControllers(fs: fs);
    addTearDown(() {
      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PatchImportDialog(
                    libraryController: ctx.libraryController,
                    editorController: ctx.editorController,
                    fileSystemOverride: fs,
                    initialDirectoryOverride:
                        '/memory/Documents/SignalChainExports/Batch',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('import_folder_button')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('UI 60B Slap'), findsOneWidget);
    expect(find.text('UI 70CDR Lush'), findsOneWidget);

    // "Load into Editor" must be disabled when 2 patches are selected
    final loadButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('import_load_editor_button')),
    );
    expect(loadButton.onPressed, isNull);

    // Deselect second patch
    await tester.ensureVisible(find.byKey(const Key('import_entry_checkbox_1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import_entry_checkbox_1')));
    await tester.pump(const Duration(milliseconds: 100));

    // Now Load into Editor is enabled, and Add to Library adds 1 patch
    await tester.tap(find.byKey(const Key('import_add_library_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(ctx.libraryController.patches.length, equals(1));
    expect(ctx.libraryController.patches.single.name, equals('UI 60B Slap'));
  });

  testWidgets('Paste JSON tab parses bundle and handles malformed input',
      (tester) async {
    final ctx = createControllers();
    addTearDown(() {
      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchImportDialog(
            libraryController: ctx.libraryController,
            editorController: ctx.editorController,
            fileSystemOverride: InMemoryImportFileSystem(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('import_tab_paste')));
    await tester.pump(const Duration(milliseconds: 100));

    // Malformed JSON shows error banner
    await tester.enterText(
      find.byKey(const Key('import_paste_text_field')),
      '{bad json',
    );
    await tester.tap(find.byKey(const Key('import_parse_text_button')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('import_error_banner')), findsOneWidget);

    // Valid JSON single patch
    final jsonText = utf8.decode(
      exportRegistry.adapterFor(ExportFormat.nativeJson).exportPatch(line6Patch).bytes,
    );
    await tester.enterText(
      find.byKey(const Key('import_paste_text_field')),
      jsonText,
    );
    await tester.tap(find.byKey(const Key('import_parse_text_button')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('import_error_banner')), findsNothing);
    expect(find.byKey(const Key('import_warning_banner')), findsOneWidget);
    expect(find.text('UI Bass POD'), findsOneWidget);
  });

  testWidgets(
      'Load into Editor switches offline device profile on mismatch when disconnected',
      (tester) async {
    final ctx = createControllers(initialFamily: DeviceFamily.zoomMs60bPlus);
    addTearDown(() {
      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
    });

    final fs = InMemoryImportFileSystem();
    final line6Bytes = exportRegistry
        .adapterFor(ExportFormat.rawSysEx)
        .exportPatch(line6Patch)
        .bytes;
    fs.addFile('/memory/Documents/SignalChainExports/pod.syx', line6Bytes);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PatchImportDialog(
                    libraryController: ctx.libraryController,
                    editorController: ctx.editorController,
                    fileSystemOverride: fs,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('import_fs_entry_pod.syx')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('import_warning_banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import_load_editor_button')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(ctx.editorController.patch?.name, equals('UI Bass POD'));
    expect(
      ctx.connectionController.activeFamily,
      equals(DeviceFamily.line6BassPodPro),
    );
  });

  testWidgets('renders cleanly across phone, short landscape, and tablet viewports',
      (tester) async {
    final viewports = [
      const Size(390, 844),
      const Size(844, 390),
      const Size(1024, 600),
    ];

    for (final size in viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      final ctx = createControllers();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatchImportDialog(
              libraryController: ctx.libraryController,
              editorController: ctx.editorController,
              fileSystemOverride: InMemoryImportFileSystem(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('import_tab_browse')), findsOneWidget);
      expect(find.byKey(const Key('import_tab_paste')), findsOneWidget);
      expect(tester.takeException(), isNull);

      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
      tester.view.resetPhysicalSize();
    }
  });

  testWidgets('multi-file selection batch decodes and Import to Library bypasses active editor patch',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fs = InMemoryImportFileSystem();
    final slapBytes = exportRegistry
        .adapterFor(ExportFormat.nativeJson)
        .exportPatch(zoom60bPatch)
        .bytes;
    final lushBytes = exportRegistry
        .adapterFor(ExportFormat.symbiosisZptc)
        .exportPatch(zoom70cdrPatch)
        .bytes;
    fs.addFile('/memory/Documents/SignalChainExports/Batch/slap.json', slapBytes);
    fs.addFile('/memory/Documents/SignalChainExports/Batch/lush.70cdrp.zptc', lushBytes);

    final ctx = createControllers(fs: fs);
    addTearDown(() {
      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
    });

    const activePatch = Patch(
      id: 'active_editor_patch',
      name: 'Active Stage Patch',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
    );
    ctx.editorController.loadPatch(activePatch);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PatchImportDialog(
                    libraryController: ctx.libraryController,
                    editorController: ctx.editorController,
                    fileSystemOverride: fs,
                    initialDirectoryOverride:
                        '/memory/Documents/SignalChainExports/Batch',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('import_browser_select_all_files_button')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('import_browser_decode_selected_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import_browser_decode_selected_button')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('UI 60B Slap'), findsOneWidget);
    expect(find.text('UI 70CDR Lush'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import_add_library_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(ctx.libraryController.patches.length, equals(2));
    expect(ctx.editorController.patch?.name, equals('Active Stage Patch'));
  });

  testWidgets('single-patch Import to Library bypasses editor by default and honors Also load into Editor checkbox',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fs = InMemoryImportFileSystem();
    final slapBytes = exportRegistry
        .adapterFor(ExportFormat.nativeJson)
        .exportPatch(zoom60bPatch)
        .bytes;
    fs.addFile('/memory/Documents/SignalChainExports/slap.json', slapBytes);

    final ctx = createControllers(fs: fs);
    addTearDown(() {
      ctx.editorController.dispose();
      ctx.connectionController.dispose();
      ctx.libraryController.dispose();
    });

    const activePatch = Patch(
      id: 'active_editor_patch',
      name: 'Active Stage Patch',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
    );
    ctx.editorController.loadPatch(activePatch);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PatchImportDialog(
                    libraryController: ctx.libraryController,
                    editorController: ctx.editorController,
                    fileSystemOverride: fs,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    // 1. Default behavior: Import to Library without touching editor
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('import_fs_entry_slap.json')));
    await tester.pump(const Duration(milliseconds: 100));

    final alsoLoadCheckbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('import_also_load_into_editor_checkbox')),
    );
    expect(alsoLoadCheckbox.value, isFalse);

    await tester.tap(find.byKey(const Key('import_add_library_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(ctx.libraryController.patches.length, equals(1));
    expect(ctx.editorController.patch?.name, equals('Active Stage Patch'));

    // 2. Opt-in: check "Also load into Editor" -> imports AND loads into editor
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('import_fs_entry_slap.json')));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.ensureVisible(
      find.byKey(const Key('import_also_load_into_editor_checkbox')),
    );
    await tester.tap(
      find.byKey(const Key('import_also_load_into_editor_checkbox')),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('import_add_library_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(ctx.libraryController.patches.length, equals(2));
    expect(ctx.editorController.patch?.name, equals('UI 60B Slap'));
  });
}

