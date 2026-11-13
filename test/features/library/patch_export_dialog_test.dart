@Timeout(Duration(seconds: 10))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_file_writer.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/export/export_payload.dart';
import 'package:signal_chain_flutter/core/storage/app_preferences_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/library/patch_export_dialog.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/patch.dart';

class _InMemoryExportFileWriter extends ExportFileWriter {
  final List<({ExportPayload payload, String? nameOverride, Directory? targetDir})> writes = [];

  @override
  Future<String> writePayload(
    ExportPayload payload, {
    Directory? targetDir,
    String? nameOverride,
  }) async {
    writes.add((payload: payload, nameOverride: nameOverride, targetDir: targetDir));
    final name = (nameOverride != null && nameOverride.trim().isNotEmpty)
        ? nameOverride.trim()
        : payload.suggestedName;
    final dirPath = targetDir?.path ?? '/memory/SignalChainExports';
    return '$dirPath/$name';
  }
}

void main() {
  const zoomPatch = Patch(
    id: 'zoom_ui_1',
    name: 'UI Slap',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
  );

  const line6Patch = Patch(
    id: 'line6_ui_1',
    name: 'UI SVT',
    deviceFamily: DeviceFamily.line6BassPodPro,
  );

  testWidgets('persists default export format when Set as default is checked', (tester) async {
    final prefs = InMemoryPreferencesRepository();
    final controller = PatchLibraryController(
      repository: InMemoryPatchLibraryRepository(initialPatches: [zoomPatch]),
      preferencesRepository: prefs,
      exportFileWriter: _InMemoryExportFileWriter(),
    );
    await controller.loadPreferences();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchExportDialog.patch(
            libraryController: controller,
            patch: zoomPatch,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('export_format_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('set_default_export_checkbox')), findsOneWidget);

    // Select Symbiosis ZPTC
    await tester.tap(find.byKey(const Key('export_format_dropdown')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(ExportFormat.symbiosisZptc.displayName).last);
    await tester.pump(const Duration(milliseconds: 100));

    // Check "Set as default format"
    await tester.tap(find.byKey(const Key('set_default_export_checkbox')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.defaultExportFormat, equals(ExportFormat.symbiosisZptc));
    expect(await prefs.getDefaultExportFormat(), equals(ExportFormat.symbiosisZptc));
  });

  testWidgets('shows warning banner when exporting mixed library to Zoom-only format', (tester) async {
    final controller = PatchLibraryController(
      repository: InMemoryPatchLibraryRepository(initialPatches: [zoomPatch, line6Patch]),
      preferencesRepository: InMemoryPreferencesRepository(
        initialDefaultExportFormat: ExportFormat.symbiosisZptc,
      ),
      exportFileWriter: _InMemoryExportFileWriter(),
    );
    await controller.loadPreferences();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchExportDialog.library(
            libraryController: controller,
            patches: const [zoomPatch, line6Patch],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('export_warning_banner')), findsOneWidget);
    expect(find.textContaining('Skipped 1 non-Zoom patch'), findsOneWidget);
  });

  testWidgets('saves exported file via ExportFileWriter on Save File tap', (tester) async {
    final fakeWriter = _InMemoryExportFileWriter();
    final controller = PatchLibraryController(
      repository: InMemoryPatchLibraryRepository(initialPatches: [zoomPatch]),
      preferencesRepository: InMemoryPreferencesRepository(),
      exportFileWriter: fakeWriter,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PatchExportDialog.patch(
                    libraryController: controller,
                    patch: zoomPatch,
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

    await tester.tap(find.byKey(const Key('export_save_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeWriter.writes.length, equals(1));
    expect(fakeWriter.writes.single.payload.format, equals(ExportFormat.nativeJson));
    expect(fakeWriter.writes.single.nameOverride, equals('UI_Slap.json'));
    expect(find.textContaining('Exported to /memory/SignalChainExports/UI_Slap.json'), findsOneWidget);
  });
}
