import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/core/storage/custom_effect_repository.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

import '../core/zd2/flst_seq_parser_test.dart';
import '../core/zd2/zd2_parser_test.dart';

Uint8List _buildCustomZd2({
  int effectId = 0x04000999,
  String name = 'MY NAM',
  String version = '1.20',
  int targetMask = 0x00080000, // MS-60B+
}) {
  final prme = json.encode({
    'Parameters': [
      {'name': 'OnOff', 'mmax': 1, 'default': 1},
      {'name': 'Gain', 'mmax': 100, 'default': 65},
      {'name': 'Level', 'mmax': 100, 'default': 80},
    ],
  });
  return buildSyntheticZd2(
    targetMask: targetMask,
    version: version,
    groupByte: 0x04,
    effectId: effectId,
    name: name,
    groupName: 'AMP',
    sections: [
      (tag: 'INFO', payload: buildInfoPayload(54.0)),
      (tag: 'TXE1', payload: Uint8List.fromList(utf8.encode('Onboard Neural Amp'))),
      (tag: 'PRME', payload: Uint8List.fromList(utf8.encode(prme))),
    ],
  );
}

void main() {
  const ms60bPort = MidiPortDescriptor(
    id: 'zoom_ms60bp',
    name: 'ZOOM MS-60B+',
    manufacturer: 'Zoom Corporation',
    isInput: true,
    isOutput: true,
  );

  // Stock MS-60B+: DYN Comp (0x01000010)
  // Cross-model MS-50G+: TB MK1.5 (0x030000E0)
  // Custom .ZD2: MY NAM (0x04000999)
  // Uninstalled: 0x01000099
  late Uint8List flstBytes;
  late Uint8List myNamZd2;

  setUp(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();

    flstBytes = buildSyntheticFlstSeq(
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
            (
              filename: 'UNINST.ZD2',
              version: '1.00',
              effectId: 0x01000099,
              installed: false,
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
        (
          groupByte: 0x04,
          includeCloseMarker: true,
          entries: [
            (
              filename: 'MY_NAM.ZD2',
              version: '1.20',
              effectId: 0x04000999,
              installed: true,
            ),
          ],
        ),
      ],
    );

    myNamZd2 = _buildCustomZd2(
      effectId: 0x04000999,
      name: 'MY NAM',
      version: '1.20',
    );
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
  });

  group('End-to-End Read-Only Zoom Onboard Effect Discovery', () {
    test(
      'discovers stock + cross-model + custom .ZD2 on connect, downloads only uncached custom .ZD2, overlays cross-model until disconnect, and hits cache on reconnect',
      () async {
        final transport = MockMidiTransport(initialPorts: [ms60bPort]);
        transport.setVirtualZoomFiles({
          'FLST_SEQ.ZT2': flstBytes,
          'MY_NAM.ZD2': myNamZd2,
          // Even if stock/cross-model files exist on pedal, they must NOT be downloaded
          'COMP.ZD2': _buildCustomZd2(effectId: 0x01000010, name: 'STOCK'),
          'TB_MK15.ZD2': _buildCustomZd2(effectId: 0x030000E0, name: 'CROSS'),
        });

        // Respond to current patch request (64 13) with a patch containing the custom effect
        const proto = ZoomMsPlusProtocol(defaultFamily: DeviceFamily.zoomMs60bPlus);
        final hardwarePatch = const Patch(
          id: 'hw_0',
          name: 'Custom Rig',
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
                    id: 'p0',
                    name: 'Param 1',
                    min: 0,
                    max: 100,
                    defaultValue: 0,
                  ),
                  currentValue: 72,
                ),
                ParameterValue(
                  descriptor: ParameterDescriptor(
                    id: 'p1',
                    name: 'Param 2',
                    min: 0,
                    max: 100,
                    defaultValue: 0,
                  ),
                  currentValue: 85,
                ),
              ],
            ),
          ],
        );

        transport.registerResponder(
          (req) =>
              req.isSysEx &&
              req.data.length >= 6 &&
              req.data[1] == 0x52 &&
              req.data[4] == 0x64 &&
              req.data[5] == 0x13,
          (_) => proto.encodePatch(hardwarePatch),
        );

        final customRepo = InMemoryCustomEffectRepository();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          customEffectRepository: customRepo,
          enableHotPlugPolling: false,
          isTest: true,
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
          initialPatch: hardwarePatch,
        );
        editor.setCustomEffectRepository(customRepo);
        addTearDown(() async {
          editor.dispose();
          connection.dispose();
          await transport.dispose();
        });

        // Before connecting: cross-model MS-50G+ TB MK1.5 is NOT in MS-60B+ palette
        expect(
          EffectCatalogRegistry.getEffects(DeviceFamily.zoomMs60bPlus)
              .any((e) => e.effectId.toUpperCase() == '0X030000E0'),
          isFalse,
        );
        expect(connection.installedEffectIds, isNull);

        // 1. First Connect -> reads FLST_SEQ.ZT2 and downloads ONLY MY_NAM.ZD2
        await connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: true,
          autoSyncBank: false,
        );

        expect(connection.isConnected, isTrue);
        expect(
          transport.virtualZoomDownloadedFiles,
          equals(['FLST_SEQ.ZT2', 'MY_NAM.ZD2']),
        );

        // Authoritative inventory excludes uninstalled entry (0x01000099)
        expect(
          connection.installedEffectIds,
          equals({'0x01000010', '0x030000E0', '0x04000999'}),
        );
        expect(connection.discoveredStockIds, equals({'0x01000010'}));
        expect(connection.discoveredCrossModelIds, equals({'0x030000E0'}));
        expect(connection.discoveredCustomIds, equals({'0x04000999'}));
        expect(connection.lastEffectDiscoveryResult?.success, isTrue);
        expect(
          connection.lastEffectDiscoveryResult?.newlyCachedCustomIds,
          equals({'0x04000999'}),
        );
        expect(connection.lastEffectDiscoveryResult?.failedCustomFilenames, isEmpty);

        // Custom .ZD2 saved in CustomEffectRepository & registered in EffectCatalogRegistry
        final persisted = await customRepo.loadAll();
        expect(persisted.length, equals(1));
        expect(persisted.first.effectId, equals('0x04000999'));
        expect(persisted.first.name, equals('MY NAM'));
        expect(persisted.first.sourceFilename, equals('MY_NAM.ZD2'));

        final customDef = EffectCatalogRegistry.getDefinition(
          DeviceFamily.zoomMs60bPlus,
          '0x04000999',
        );
        expect(customDef.origin, equals(EffectOrigin.custom));
        expect(customDef.name, equals('MY NAM'));
        expect(customDef.parameters.map((p) => p.name), equals(['Gain', 'Level']));

        // Editor patch was immediately upgraded from Unknown to MY NAM with real knobs!
        expect(editor.patch!.slots.first.effectName, equals('MY NAM'));
        expect(
          editor.patch!.slots.first.parameters.map((p) => p.descriptor.name),
          equals(['Gain', 'Level']),
        );

        // Cross-model MS-50G+ effect is now selectable in MS-60B+ palette with crossModel origin!
        final paletteWhileConnected =
            EffectCatalogRegistry.getEffects(DeviceFamily.zoomMs60bPlus);
        final crossInPalette = paletteWhileConnected.firstWhere(
          (e) => e.effectId.toUpperCase() == '0X030000E0',
        );
        expect(crossInPalette.origin, equals(EffectOrigin.crossModel));
        expect(crossInPalette.sourceModelLabel, equals('MS-50G+'));

        // 2. Disconnect -> clears hardware inventory AND removes cross-model palette overlay!
        await connection.disconnect();
        expect(connection.installedEffectIds, isNull);
        expect(connection.installedFlstEntries, isEmpty);
        expect(
          EffectCatalogRegistry.getEffects(DeviceFamily.zoomMs60bPlus)
              .any((e) => e.effectId.toUpperCase() == '0X030000E0'),
          isFalse,
        );

        // 3. Second Connect -> hits CustomEffectRepository cache and skips re-downloading MY_NAM.ZD2!
        transport.clearVirtualZoomDownloadHistory();
        await connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: false,
          autoSyncBank: false,
        );

        expect(transport.virtualZoomDownloadedFiles, equals(['FLST_SEQ.ZT2']));
        expect(
          connection.installedEffectIds,
          equals({'0x01000010', '0x030000E0', '0x04000999'}),
        );
        expect(connection.lastEffectDiscoveryResult?.newlyCachedCustomIds, isEmpty);

        // Manual rescan with forceRedownloadCustom: true re-downloads MY_NAM.ZD2
        transport.clearVirtualZoomDownloadHistory();
        final forced = await connection.scanInstalledEffects(
          forceRedownloadCustom: true,
        );
        expect(forced.success, isTrue);
        expect(
          transport.virtualZoomDownloadedFiles,
          equals(['FLST_SEQ.ZT2', 'MY_NAM.ZD2']),
        );
      },
    );

    test(
      'continues scanning remaining custom .ZD2 files if one fails to download or parse',
      () async {
        final partialFlst = buildSyntheticFlstSeq(
          deviceName: 'MS-60B+',
          groups: const [
            (
              groupByte: 0x04,
              includeCloseMarker: true,
              entries: [
                (
                  filename: 'MISSING.ZD2',
                  version: '1.00',
                  effectId: 0x04000888,
                  installed: true,
                ),
                (
                  filename: 'MY_NAM.ZD2',
                  version: '1.20',
                  effectId: 0x04000999,
                  installed: true,
                ),
              ],
            ),
          ],
        );

        final transport = MockMidiTransport(initialPorts: [ms60bPort]);
        transport.setVirtualZoomFiles({
          'FLST_SEQ.ZT2': partialFlst,
          'MY_NAM.ZD2': myNamZd2,
          // MISSING.ZD2 intentionally omitted so it returns 0 bytes
        });

        final repo = InMemoryCustomEffectRepository();
        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          customEffectRepository: repo,
          enableHotPlugPolling: false,
          isTest: true,
        );
        addTearDown(() async {
          connection.dispose();
          await transport.dispose();
        });

        await connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: false,
          autoSyncBank: false,
        );

        expect(connection.lastEffectDiscoveryResult?.success, isTrue);
        expect(
          connection.lastEffectDiscoveryResult?.failedCustomFilenames,
          equals(['MISSING.ZD2']),
        );
        expect(
          connection.lastEffectDiscoveryResult?.failedCustomEffects.length,
          equals(1),
        );
        expect(
          connection.lastEffectDiscoveryResult?.failedCustomEffects.first.filename,
          equals('MISSING.ZD2'),
        );
        expect(
          connection.lastEffectDiscoveryResult?.failedCustomEffects.first.effectId,
          equals('0x04000888'),
        );
        expect(
          connection.lastEffectDiscoveryResult?.failedCustomEffects.first.reason,
          contains('code -1 / not readable'),
        );
        expect(
          connection.lastEffectDiscoveryResult?.newlyCachedCustomIds,
          equals({'0x04000999'}),
        );
        expect(connection.effectScanError, contains('MISSING.ZD2'));
        expect(connection.effectScanError, contains('0x04000888'));
        expect((await repo.loadAll()).length, equals(1));
      },
    );

    test(
      'failed/timed-out discovery leaves installedEffectIds == null without breaking connection or patch loading',
      () async {
        // Exercise 0x60 timeout recovery path on connect() with no virtual files
        final transport = MockMidiTransport(initialPorts: [ms60bPort])
          ..simulateZoomFileTransferTimeout = true;
        const proto = ZoomMsPlusProtocol(defaultFamily: DeviceFamily.zoomMs60bPlus);
        final fallbackPatch = const Patch(
          id: 'ok_patch',
          name: 'Still Works',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [],
        );
        transport.registerResponder(
          (req) =>
              req.isSysEx &&
              req.data.length >= 6 &&
              req.data[1] == 0x52 &&
              req.data[4] == 0x64 &&
              req.data[5] == 0x13,
          (_) => proto.encodePatch(fallbackPatch),
        );

        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          enableHotPlugPolling: false,
          isTest: true,
        );
        final editor = PatchEditorController(
          transport: transport,
          connectionController: connection,
        );
        addTearDown(() async {
          editor.dispose();
          connection.dispose();
          await transport.dispose();
        });

        await connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: true,
          autoSyncBank: false,
        );

        // Connection succeeded and initial patch loaded cleanly!
        expect(connection.isConnected, isTrue);
        expect(connection.errorMessage, isNull);
        expect(connection.installedEffectIds, isNull);
        expect(connection.lastEffectDiscoveryResult?.success, isFalse);
        expect(editor.patch?.name, equals('Still Works'));

        // Verify 0x53 -> 0x50 recovery ran before 64 13 current patch fetch
        final opcodes = transport.sentMessages
            .where((m) => m.isSysEx && m.data.length >= 5 && m.data[1] == 0x52)
            .map((m) => m.data[4])
            .toList();
        expect(opcodes, containsAllInOrder([0x52, 0x60, 0x53, 0x50, 0x64]));
      },
    );
  });
}
