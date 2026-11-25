import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/diagnostics/app_diagnostics_log.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';

import '../zd2/flst_seq_parser_test.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  tearDown(() {
    EffectCatalogRegistry.clearCustomEffects();
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
  });

  group('AppDiagnosticsLog unit tests', () {
    test('caps entries at 500 by default and evicts oldest first', () {
      final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
      for (int i = 0; i < 550; i++) {
        log.info('Test', 'entry-$i');
      }

      expect(log.length, 500);
      expect(log.entries.first.message, 'entry-50');
      expect(log.entries.last.message, 'entry-549');
    });

    test('formats timestamp, level, category, and plain-text export', () {
      final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
      final ts1 = DateTime(2026, 11, 23, 9, 5, 7, 42);
      final ts2 = DateTime(2026, 11, 23, 14, 30, 59, 9);

      log.add(
        'Connection',
        'Connected to pedal',
        level: DiagnosticLogLevel.info,
        timestamp: ts1,
      );
      log.add(
        'Writes',
        'Cross-generation write blocked',
        level: DiagnosticLogLevel.warn,
        timestamp: ts2,
      );
      log.add(
        'ZoomFileTransfer',
        'ERR timeout',
        level: DiagnosticLogLevel.error,
        timestamp: ts2,
      );

      final lines = log.formatPlainText().split('\n');
      expect(lines.length, 3);
      expect(lines[0], '[09:05:07.042] [INFO] [Connection] Connected to pedal');
      expect(
        lines[1],
        '[14:30:59.009] [WARN] [Writes] Cross-generation write blocked',
      );
      expect(lines[2], '[14:30:59.009] [ERROR] [ZoomFileTransfer] ERR timeout');

      final filtered = log.formatPlainText(
        where: (e) => e.level == DiagnosticLogLevel.warn,
      );
      expect(
        filtered,
        '[14:30:59.009] [WARN] [Writes] Cross-generation write blocked',
      );
    });

    test('clear empties entries and notifies listeners only when non-empty', () {
      final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
      int notifications = 0;
      log.addListener(() => notifications++);

      log.clear();
      expect(notifications, 0);

      log.info('Test', 'one');
      log.warn('Test', 'two');
      expect(notifications, 2);
      expect(log.isEmpty, isFalse);

      log.clear();
      expect(log.isEmpty, isTrue);
      expect(log.entries, isEmpty);
      expect(notifications, 3);
    });
  });

  group('Runtime controller integration with AppDiagnosticsLog', () {
    const ms60bPort = MidiPortDescriptor(
      id: 'zoom_ms60bp',
      name: 'ZOOM MS-60B+',
      manufacturer: 'Zoom Corporation',
      isInput: true,
      isOutput: true,
    );

    test(
      'DeviceConnectionController logs connect, discovery, ZoomFileTransfer control frames, and disconnect',
      () async {
        final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
        final transport = MockMidiTransport(initialPorts: [ms60bPort]);
        final flstBytes = buildSyntheticFlstSeq(
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
          ],
        );
        transport.setVirtualZoomFiles({'FLST_SEQ.ZT2': flstBytes});

        final connection = DeviceConnectionController(
          transport: transport,
          defaultFamily: DeviceFamily.zoomMs60bPlus,
          enableHotPlugPolling: false,
          diagnosticsLog: log,
          isTest: true,
        );
        addTearDown(connection.dispose);

        await connection.connect(ms60bPort, fetchCurrentPatch: false);
        await connection.disconnect();

        final text = log.formatPlainText();
        expect(text, contains('[Connection] Connected to "ZOOM MS-60B+"'));
        expect(text, contains('[ZoomFileTransfer] TX open("FLST_SEQ.ZT2")'));
        expect(text, contains('[Discovery] FLST_SEQ.ZT2'));
        expect(text, contains('[Discovery] Onboard discovery complete: 1 stock'));
        expect(text, contains('[Connection] Disconnected from "ZOOM MS-60B+"'));
      },
    );

    test(
      'PatchEditorController logs slot writes, bank restore summary, and skipped missing-effect warnings',
      () async {
        final log = AppDiagnosticsLog(mirrorToDebugPrint: false);
        final transport = MockMidiTransport(initialPorts: [ms60bPort]);
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
          diagnosticsLog: log,
        );
        addTearDown(() {
          editor.dispose();
          connection.dispose();
        });

        await connection.connect(
          ms60bPort,
          explicitFamily: DeviceFamily.zoomMs60bPlus,
          fetchCurrentPatch: false,
          autoDiscoverEffects: false,
        );

        const stockPatch = Patch(
          id: 'p1',
          name: 'Stock Rig',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
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
                  currentValue: 5,
                ),
              ],
            ),
          ],
        );

        editor.loadPatch(stockPatch);
        await editor.savePatchToDeviceSlot(4);
        await editor.restoreBankSlots(
          patches: [stockPatch, stockPatch.copyWith(id: 'p2', name: 'Rig 2')],
          startSlotIndex: 10,
          interSlotDelay: Duration.zero,
        );

        // Trigger skipped missing-effect warning during live sync by reordering a
        // patch containing an effect ID not present in the MS-60B+ stock catalog.
        const missingEffectPatch = Patch(
          id: 'p_missing',
          name: 'Missing FX',
          deviceFamily: DeviceFamily.zoomMs60bPlus,
          slots: [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x04000999',
              effectName: 'Custom Missing',
              isEnabled: true,
              parameters: [],
            ),
            EffectSlot(
              slotIndex: 1,
              effectId: '0x01000010',
              effectName: 'DYN Comp',
              isEnabled: true,
              parameters: [],
            ),
          ],
        );
        editor.loadPatch(missingEffectPatch);
        editor.swapEffectSlots(0, 1);

        final text = log.formatPlainText();
        expect(text, contains('[Writes] Saved "Stock Rig" to hardware slot'));
        expect(text, contains('[Writes] Restored 2/2 hardware slots'));
        expect(
          text,
          contains('[WARN] [Writes] Skipped 1 missing effect slot(s)'),
        );
      },
    );
  });
}

