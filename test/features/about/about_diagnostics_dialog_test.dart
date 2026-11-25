import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/app_info.dart';
import 'package:signal_chain_flutter/core/diagnostics/app_diagnostics_log.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/file_system_custom_effect_repository.dart';
import 'package:signal_chain_flutter/core/storage/file_system_patch_library_repository.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/about/about_diagnostics_dialog.dart';
import 'package:signal_chain_flutter/features/connection/connection_bar_widget.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

import '../../core/zd2/flst_seq_parser_test.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
  });

  Widget wrapWithApp(Widget child) {
    return MaterialApp(
      theme: StudioTheme.darkTheme,
      home: Scaffold(body: child),
    );
  }

  group('AboutDiagnosticsDialog widget tests', () {
    testWidgets(
      'displays version, metadata, hardware summary, storage paths, and onboard counts',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('sc_about_test_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
        const port = MidiPortDescriptor(
          id: 'zoom_ms60bp',
          name: 'ZOOM MS-60B+',
          manufacturer: 'Zoom Corporation',
          isInput: true,
          isOutput: true,
        );
        final transport = MockMidiTransport(initialPorts: [port]);
        transport.setVirtualZoomFiles({
          'FLST_SEQ.ZT2': buildSyntheticFlstSeq(
            deviceName: 'MS-60B+',
            groups: const [
              (
                groupByte: 0x01,
                includeCloseMarker: true,
                entries: [
                  (
                    filename: 'COMP.ZD2',
                    version: '1.00',
                    effectId: 0x01000010,
                    installed: true,
                  ),
                ],
              ),
              (
                groupByte: 0x03,
                includeCloseMarker: true,
                entries: [
                  (
                    filename: 'TB_MK15.ZD2',
                    version: '1.00',
                    effectId: 0x030000E0,
                    installed: true,
                  ),
                ],
              ),
            ],
          ),
        });

        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          enableHotPlugPolling: false,
          diagnosticsLog: log,
          isTest: true,
        );
        addTearDown(connection.dispose);
        await tester.runAsync(
          () => connection.connect(
            port,
            explicitFamily: DeviceFamily.zoomMs60bPlus,
            fetchCurrentPatch: false,
          ),
        );

        final presetsDir = Directory('${tempDir.path}/presets')..createSync();
        final customDir = Directory('${tempDir.path}/custom_effects')
          ..createSync();
        final libraryRepo = FileSystemPatchLibraryRepository(
          storageDir: presetsDir,
        );
        final libraryController = PatchLibraryController(
          repository: libraryRepo,
        );
        addTearDown(libraryController.dispose);
        final customRepo = FileSystemCustomEffectRepository.inDirectory(
          customDir,
        );

        await tester.pumpWidget(
          wrapWithApp(
            AboutDiagnosticsDialog(
              connectionController: connection,
              libraryController: libraryController,
              customEffectRepository: customRepo,
              diagnosticsLog: log,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppInfo.appName), findsOneWidget);
        expect(find.text('v${AppInfo.version}'), findsAtLeastNWidgets(1));
        expect(find.text('${AppInfo.license} License'), findsOneWidget);
        expect(find.text(AppInfo.repositoryUrl), findsOneWidget);
        expect(
          find.byKey(const Key('environment_hardware_summary_card')),
          findsOneWidget,
        );
        expect(find.textContaining('ZOOM MS-60B+'), findsAtLeastNWidgets(1));
        expect(
          find.text('1 stock, 1 cross-model, 0 custom'),
          findsOneWidget,
        );
        expect(find.text(presetsDir.path), findsOneWidget);
        expect(find.text(customRepo.storageFile.path), findsOneWidget);
      },
    );

    testWidgets(
      'renders logged entries, filters by category, copies to clipboard, and clears log',
      (tester) async {
        final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
        log.info('Connection', 'Connected to simulated pedal');
        log.warn('Writes', 'Skipped 1 missing effect slot');
        log.error('ZoomFileTransfer', 'ERR timeout reading custom file');

        final transport = MockMidiTransport();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          enableHotPlugPolling: false,
          diagnosticsLog: log,
          isTest: true,
        );
        addTearDown(connection.dispose);

        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                final args = call.arguments as Map<dynamic, dynamic>;
                copiedClipboardText = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(
          wrapWithApp(
            AboutDiagnosticsDialog(
              connectionController: connection,
              diagnosticsLog: log,
              initialTabIndex: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Connected to simulated pedal'), findsOneWidget);
        expect(find.textContaining('Skipped 1 missing effect slot'), findsOneWidget);
        expect(
          find.textContaining('ERR timeout reading custom file'),
          findsOneWidget,
        );

        // Filter to Writes only
        await tester.tap(find.byKey(const Key('log_filter_writes')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Skipped 1 missing effect slot'), findsOneWidget);
        expect(find.textContaining('Connected to simulated pedal'), findsNothing);

        // Reset filter to All
        await tester.tap(find.byKey(const Key('log_filter_all')));
        await tester.pumpAndSettle();

        // Copy Log populates clipboard with environment header + entries
        await tester.tap(find.byKey(const Key('diagnostics_copy_log_button')));
        await tester.pumpAndSettle();
        expect(copiedClipboardText, isNotNull);
        expect(
          copiedClipboardText,
          contains('${AppInfo.appName} v${AppInfo.version}'),
        );
        expect(copiedClipboardText, contains('Connected to simulated pedal'));
        expect(copiedClipboardText, contains('ERR timeout reading custom file'));
        expect(
          find.text('Copied environment summary and diagnostics log to clipboard.'),
          findsOneWidget,
        );

        // Clear Log empties the list
        await tester.tap(find.byKey(const Key('diagnostics_clear_log_button')));
        await tester.pumpAndSettle();
        expect(log.isEmpty, isTrue);
        expect(find.text('No diagnostic log entries.'), findsOneWidget);
      },
    );

    testWidgets(
      'top-bar Info button opens AboutDiagnosticsDialog on desktop and compact viewports',
      (tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        for (final size in [const Size(1200, 800), const Size(390, 844)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
          final transport = MockMidiTransport();
          final connection = DeviceConnectionController(
            transport: transport,
            defaultFamily: DeviceFamily.zoomMs60bPlus,
            enableHotPlugPolling: false,
            diagnosticsLog: log,
            isTest: true,
          );
          final editor = PatchEditorController(
            transport: transport,
            connectionController: connection,
          );
          final library = PatchLibraryController(
            repository: InMemoryPatchLibraryRepository(),
          );

          await tester.pumpWidget(
            wrapWithApp(
              ConnectionBarWidget(
                connectionController: connection,
                editorController: editor,
                libraryController: library,
                onToggleLibrary: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final infoBtn = find.byKey(const Key('about_diagnostics_button'));
          expect(infoBtn, findsOneWidget);
          await tester.tap(infoBtn);
          await tester.pumpAndSettle();

          expect(find.text('About & Diagnostics Log'), findsOneWidget);
          expect(find.text('v${AppInfo.version}'), findsAtLeastNWidgets(1));

          await tester.tap(
            find.byKey(const Key('about_diagnostics_close_button')),
          );
          await tester.pumpAndSettle();
          expect(find.text('About & Diagnostics Log'), findsNothing);

          editor.dispose();
          connection.dispose();
          library.dispose();
        }
      },
    );
  });
}

