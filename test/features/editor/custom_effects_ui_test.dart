import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/custom_effect_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/custom_effects_dialog.dart';
import 'package:signal_chain_flutter/features/editor/effect_bank_palette_widget.dart';
import 'package:signal_chain_flutter/features/editor/effect_picker_dialog.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/features/editor/slot_inspector_widget.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

Uint8List _makeZd2Bytes({
  required int effectId,
  required String name,
  int targetMask = 0x00080000,
  String version = '1.00',
  String description = 'Custom effect description',
}) {
  final header = Uint8List(0x80);
  final bd = ByteData.sublistView(header);
  header.setRange(0, 4, ascii.encode('ZDLF'));
  bd.setUint32(0x04, 120, Endian.little);
  bd.setUint32(0x0C, targetMask, Endian.little);
  final ver = ascii.encode(version);
  header.setRange(0x59, 0x59 + ver.length.clamp(0, 4), ver);
  header[0x5F] = 0x04;
  bd.setUint32(0x60, effectId, Endian.little);
  final nameBytes = ascii.encode(name);
  header.setRange(0x64, 0x64 + nameBytes.length.clamp(0, 10), nameBytes);

  final txePayload = Uint8List.fromList(utf8.encode(description));
  final prmePayload = Uint8List.fromList(utf8.encode(json.encode({
    'Parameters': [
      {'name': 'Drive', 'mmax': 100, 'default': 50},
      {'name': 'Level', 'mmax': 100, 'default': 80},
    ],
  })));

  final b = BytesBuilder();
  b.add(header);
  for (final sec in [
    (tag: 'TXE1', payload: txePayload),
    (tag: 'PRME', payload: prmePayload),
  ]) {
    final h = Uint8List(8);
    h.setRange(0, 4, ascii.encode(sec.tag));
    ByteData.sublistView(h).setUint32(4, sec.payload.length, Endian.little);
    b.add(h);
    b.add(sec.payload);
  }
  return b.toBytes();
}

void main() {
  setUp(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
  });

  ({
    MockMidiTransport transport,
    DeviceConnectionController connection,
    PatchEditorController editor,
    InMemoryCustomEffectRepository customRepo,
  }) createHarness({
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
    Patch? initialPatch,
  }) {
    final transport = MockMidiTransport();
    final connection = DeviceConnectionController(
      transport: transport,
      defaultFamily: family,
      enableHotPlugPolling: false,
      isTest: true,
    );
    final customRepo = InMemoryCustomEffectRepository();
    final editor = PatchEditorController(
      transport: transport,
      connectionController: connection,
      initialPatch: initialPatch ??
          Patch(
            id: 'ui_test_patch',
            name: 'Badge Test',
            deviceFamily: family,
            slots: const [
              // Slot 0: Stock MS-60B+ DYN Comp
              EffectSlot(
                slotIndex: 0,
                effectId: '0x01000010',
                effectName: 'DYN Comp',
                isEnabled: true,
              ),
              // Slot 1: Cross-model MS-50G+ TB MK1.5
              EffectSlot(
                slotIndex: 1,
                effectId: '0x030000E0',
                effectName: 'TB MK1.5',
                isEnabled: true,
              ),
              // Slot 2: Custom .ZD2 effect
              EffectSlot(
                slotIndex: 2,
                effectId: '0x04000999',
                effectName: 'MY NAM',
                isEnabled: true,
              ),
            ],
          ),
    );
    editor.setCustomEffectRepository(customRepo);
    return (
      transport: transport,
      connection: connection,
      editor: editor,
      customRepo: customRepo,
    );
  }

  group('Origin Badges across Editor UI', () {
    testWidgets(
      'SignalChainStripWidget and SlotInspectorWidget show MS-50G+ and CUSTOM badges while keeping stock clean',
      (tester) async {
        EffectCatalogRegistry.registerCustomEffect(
          const EffectDefinition(
            effectId: '0x04000999',
            name: 'MY NAM',
            category: 'Custom',
            deviceFamily: DeviceFamily.zoomMs60bPlus,
            origin: EffectOrigin.custom,
            sourceModelLabel: 'Custom',
            sourceFilename: 'MY_NAM.ZD2',
            parameters: [
              ParameterDescriptor(id: 'gain_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
            ],
          ),
          generation: DeviceGeneration.zoomMsPlus,
        );

        final h = createHarness();
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          await h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: Column(
                  children: [
                    SignalChainStripWidget(controller: h.editor),
                    Expanded(child: SlotInspectorWidget(controller: h.editor)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Strip shows MS-50G+ for slot 1 and CUSTOM for slot 2, NO origin badge for stock slot 0
        expect(find.byKey(const Key('origin_badge_stock_0x01000010')), findsNothing);
        expect(find.byKey(const Key('origin_badge_crossModel_0x030000E0')), findsOneWidget);
        expect(find.text('MS-50G+'), findsOneWidget);
        expect(find.byKey(const Key('origin_badge_custom_0x04000999')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('origin_badge_custom_0x04000999')),
            matching: find.text('CUSTOM'),
          ),
          findsOneWidget,
        );

        // Selecting slot 1 shows MS-50G+ badge in SlotInspectorWidget as well
        h.editor.selectSlot(1);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('origin_badge_crossModel_0x030000E0')), findsNWidgets(2));

        // Selecting slot 2 shows CUSTOM badge in SlotInspectorWidget as well
        h.editor.selectSlot(2);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('origin_badge_custom_0x04000999')), findsNWidgets(2));
      },
    );

    testWidgets(
      'EffectBankPaletteWidget shows Custom (.ZD2) button for Zoom families with count badge and hides it for Line 6',
      (tester) async {
        final h = createHarness(family: DeviceFamily.zoomMs60bPlus);
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          await h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 600,
                child: EffectBankPaletteWidget(controller: h.editor),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Visible for Zoom MS-60B+, no count pill yet
        expect(find.byKey(const Key('palette_custom_effects_button')), findsOneWidget);
        expect(find.byKey(const Key('palette_custom_effects_count')), findsNothing);

        // Register a custom effect -> palette updates reactively via catalogRevision!
        EffectCatalogRegistry.registerCustomEffect(
          const EffectDefinition(
            effectId: '0x04000999',
            name: 'MY NAM',
            category: 'Custom',
            deviceFamily: DeviceFamily.zoomMs60bPlus,
            origin: EffectOrigin.custom,
          ),
          generation: DeviceGeneration.zoomMsPlus,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('palette_custom_effects_count')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('palette_custom_effects_count')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        // Switch to Line 6 Bass POD Pro -> button is hidden!
        h.connection.selectDeviceFamily(DeviceFamily.line6BassPodPro);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('palette_custom_effects_button')), findsNothing);
      },
    );

    testWidgets('EffectPickerDialog renders CUSTOM badge on registered custom effect', (tester) async {
      EffectCatalogRegistry.registerCustomEffect(
        const EffectDefinition(
          effectId: '0x04000999',
          name: 'MY NAM',
          category: 'Custom',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          origin: EffectOrigin.custom,
        ),
        generation: DeviceGeneration.zoomMsPlus,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: const Scaffold(
            body: EffectPickerDialog(deviceFamily: DeviceFamily.zoomMs60bPlus),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('effect_picker_search_input')), 'MY NAM');
      await tester.pumpAndSettle();

      final itemFinder = find.byKey(const Key('effect_picker_item_0x04000999'));
      expect(itemFinder, findsOneWidget);
      expect(
        find.descendant(of: itemFinder, matching: find.text('MY NAM')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: itemFinder,
          matching: find.byKey(const Key('origin_badge_custom_0x04000999')),
        ),
        findsOneWidget,
      );
    });
  });

  group('CustomEffectsDialog Import, List, Delete & Undo', () {
    testWidgets(
      'imports .ZD2 files via InMemoryImportFileSystem, re-hydrates open patch, deletes and undoes cleanly',
      (tester) async {
        final fs = InMemoryImportFileSystem(
          initialFiles: {
            '/memory/Documents/SignalChainExports/MY_NAM.ZD2': _makeZd2Bytes(
              effectId: 0x04000999,
              name: 'MY NAM',
              version: '1.50',
              description: 'Custom neural amp model',
            ),
            '/memory/Documents/SignalChainExports/BROKEN.ZD2':
                Uint8List.fromList([1, 2, 3, 4]),
          },
        );

        final openPatch = const Patch(
          id: 'open_1',
          name: 'Test Rig',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x04000999',
              effectName: 'Unknown Effect (0x04000999)',
              isEnabled: true,
              parameters: [
                ParameterValue(
                  descriptor: ParameterDescriptor(
                    id: 'param_0',
                    name: 'Param 1',
                    min: 0,
                    max: 100,
                    defaultValue: 0,
                  ),
                  currentValue: 64,
                ),
              ],
            ),
          ],
        );

        final h = createHarness(initialPatch: openPatch);
        addTearDown(() async {
          h.editor.dispose();
          h.connection.dispose();
          await h.transport.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: StudioTheme.darkTheme,
            home: Scaffold(
              body: CustomEffectsDialog(
                editorController: h.editor,
                repository: h.customRepo,
                fileSystemOverride: fs,
                initialDirectoryOverride: '/memory/Documents/SignalChainExports',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Initially empty
        expect(find.byKey(const Key('custom_effects_empty_state')), findsOneWidget);

        // Open embedded .ZD2 file browser
        await tester.tap(find.byKey(const Key('custom_effects_import_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('zd2_file_browser_pane')), findsOneWidget);

        // Import valid MY_NAM.ZD2
        await tester.tap(find.byKey(const Key('zd2_import_single_MY_NAM.ZD2')));
        await tester.pumpAndSettle();

        // Registered in dialog list, repository, registry, AND open patch upgraded!
        expect(find.byKey(const Key('custom_effect_item_0x04000999')), findsOneWidget);
        expect(find.text('MY NAM'), findsOneWidget);
        expect(find.textContaining('0x04000999'), findsWidgets);
        expect(find.textContaining('v1.50'), findsOneWidget);
        expect(find.text('Custom neural amp model'), findsOneWidget);
        expect((await h.customRepo.loadAll()).length, equals(1));
        expect(h.editor.patch!.slots.first.effectName, equals('MY NAM'));
        expect(h.editor.patch!.slots.first.parameters.first.descriptor.name, equals('Drive'));
        expect(h.editor.patch!.slots.first.parameters.first.currentValue, equals(64));

        // Attempting to import corrupt BROKEN.ZD2 shows clear error without crashing
        await tester.tap(find.byKey(const Key('zd2_import_single_BROKEN.ZD2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('zd2_import_outcomes')), findsOneWidget);
        expect(find.textContaining('BROKEN.ZD2'), findsWidgets);

        // Hide file browser so the list and delete button are comfortably visible
        await tester.tap(find.byKey(const Key('custom_effects_import_button')));
        await tester.pumpAndSettle();

        // Delete MY NAM -> removed from list, repo, and registry, showing Undo banner
        await tester.tap(find.byKey(const Key('delete_custom_effect_0x04000999')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('custom_effect_item_0x04000999')), findsNothing);
        expect(find.byKey(const Key('custom_effects_undo_banner')), findsOneWidget);
        expect(await h.customRepo.loadAll(), isEmpty);
        expect(
          EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x04000999').origin,
          equals(EffectOrigin.unknown),
        );

        // Click UNDO -> restored cleanly!
        await tester.tap(find.byKey(const Key('undo_delete_custom_effect_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('custom_effect_item_0x04000999')), findsOneWidget);
        expect((await h.customRepo.loadAll()).length, equals(1));
        expect(
          EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x04000999').origin,
          equals(EffectOrigin.custom),
        );
      },
    );
  });
}

