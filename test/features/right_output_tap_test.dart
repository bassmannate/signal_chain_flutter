import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/adapters/raw_sysex_import_adapter.dart';
import 'package:signal_chain_flutter/core/import/patch_importer.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_diff_dialog.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/signal_chain_strip_widget.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/models/patch_diff.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  List<EffectSlot> buildSlots(int count) {
    const ids = [
      ('0x01000010', 'DYN Comp'),
      ('0x02000010', 'Bass Preamp'),
      ('0x05000020', 'AMPG SVT'),
      ('0x06000010', 'Bass Chorus'),
      ('0x08000010', 'Delay'),
      ('0x09000010', 'Hall Reverb'),
    ];
    return [
      for (int i = 0; i < count; i++)
        EffectSlot(
          slotIndex: i,
          effectId: ids[i].$1,
          effectName: ids[i].$2,
          isEnabled: true,
          parameters: const [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p0',
                name: 'Level',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: 50,
            ),
          ],
        ),
    ];
  }

  Patch buildMsPlusPatch({
    DeviceFamily family = DeviceFamily.zoomMs60bPlus,
    int slotCount = 3,
    int rightOutputTapCode = 0,
  }) {
    return Patch(
      id: 'ms_plus_rout_test',
      name: 'R-Out Test',
      deviceFamily: family,
      slots: buildSlots(slotCount),
      rightOutputTapCode: rightOutputTapCode,
      metadata: const {'tempo': 120},
    );
  }

  int findPrm2Offset(Uint8List ptcf) {
    for (int i = 0; i <= ptcf.length - 8; i++) {
      if (ptcf[i] == 0x50 &&
          ptcf[i + 1] == 0x52 &&
          ptcf[i + 2] == 0x4D &&
          ptcf[i + 3] == 0x32) {
        return i + 8;
      }
    }
    return -1;
  }

  group('Domain Model & PatchDiff R-Out Support', () {
    test('supportsConfigurableRightOutput is true only for MS+ models', () {
      expect(DeviceFamily.zoomMs50gPlus.supportsConfigurableRightOutput, isTrue);
      expect(DeviceFamily.zoomMs60bPlus.supportsConfigurableRightOutput, isTrue);
      expect(DeviceFamily.zoomMs70cdrPlus.supportsConfigurableRightOutput, isTrue);
      expect(DeviceFamily.zoomMs200dPlus.supportsConfigurableRightOutput, isTrue);

      expect(DeviceFamily.zoomB1xFour.supportsConfigurableRightOutput, isFalse);
      expect(DeviceFamily.zoomB1Four.supportsConfigurableRightOutput, isFalse);
      expect(DeviceFamily.zoomG1xFour.supportsConfigurableRightOutput, isFalse);
      expect(DeviceFamily.zoomG1Four.supportsConfigurableRightOutput, isFalse);
      expect(DeviceFamily.line6BassPodPro.supportsConfigurableRightOutput, isFalse);
      expect(DeviceFamily.unknown.supportsConfigurableRightOutput, isFalse);
    });

    test('Patch copyWith, equality, JSON backward-compatibility, and isSignatureMatch handle rightOutputTapCode', () {
      final base = buildMsPlusPatch(slotCount: 4);
      expect(base.rightOutputTapCode, equals(0));
      expect(base.supportsConfigurableRightOutput, isTrue);

      final tapped = base.copyWith(rightOutputTapCode: 3);
      expect(tapped.rightOutputTapCode, equals(3));
      expect(tapped, isNot(equals(base)));
      expect(tapped.hashCode, isNot(equals(base.hashCode)));
      expect(Patch.isSignatureMatch(base, tapped), isFalse);

      // JSON round-trip preserves non-zero tap code
      final jsonMap = tapped.toJson();
      expect(jsonMap['rightOutputTapCode'], equals(3));
      final restored = Patch.fromJson(jsonMap);
      expect(restored, equals(tapped));
      expect(restored.rightOutputTapCode, equals(3));

      // Older JSON without rightOutputTapCode defaults cleanly to 0
      final legacyJson = base.toJson()..remove('rightOutputTapCode');
      final legacyRestored = Patch.fromJson(legacyJson);
      expect(legacyRestored.rightOutputTapCode, equals(0));
      expect(legacyRestored, equals(base));
    });

    test('PatchDiff detects R-Out tap changes and PatchDiffDialog renders delta', () {
      final base = buildMsPlusPatch(slotCount: 4, rightOutputTapCode: 0);
      final target = base.copyWith(rightOutputTapCode: 3);

      final diff = PatchDiff.compute(base, target);
      expect(diff.hasChanges, isTrue);
      expect(diff.totalChangeCount, equals(1));
      expect(diff.rightOutputTapChange, equals((before: 0, after: 3)));
      expect(diff.summaryLabel, equals('1 change'));
    });

    testWidgets('PatchDiffDialog displays R-Out Tap metadata change row', (tester) async {
      final base = buildMsPlusPatch(slotCount: 4, rightOutputTapCode: 0);
      final target = base.copyWith(rightOutputTapCode: 1);
      final diff = PatchDiff.compute(base, target);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatchDiffDialog(
              baseLabel: 'Base',
              targetLabel: 'Target',
              diff: diff,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('R-Out Tap:'), findsOneWidget);
      expect(find.text('End (L+R)'), findsOneWidget);
      expect(find.text('Input (Dry)'), findsOneWidget);
    });
  });

  group('ZoomMsPlusProtocol PRM2 Byte 13 Codec & File Round-Trips', () {
    const protocol = ZoomMsPlusProtocol();

    test('encodes and decodes R-Out tap codes 0, 1, 5 (in 5-effect patch), and 6 (in 6-effect patch)', () {
      // 0x00 = End of Chain
      final patchEnd = buildMsPlusPatch(slotCount: 5, rightOutputTapCode: 0);
      final ptcfEnd = protocol.encodePtcf(patchEnd);
      final prm2End = findPrm2Offset(ptcfEnd);
      expect(prm2End, isNot(-1));
      expect(ptcfEnd[prm2End + 13], equals(0x00));
      expect(ptcfEnd[prm2End + 16], equals(0x00));
      expect(protocol.decodePtcf(ptcfEnd).rightOutputTapCode, equals(0));

      // 0x02 = Input (tap code 1 << 1)
      final patchIn = buildMsPlusPatch(slotCount: 5, rightOutputTapCode: 1);
      final ptcfIn = protocol.encodePtcf(patchIn);
      final prm2In = findPrm2Offset(ptcfIn);
      expect(ptcfIn[prm2In + 13], equals(0x02));
      expect(protocol.decodePtcf(ptcfIn).rightOutputTapCode, equals(1));

      // 0x0A = After Effect 4 / slot 3 (tap code 5 << 1) in a 5-effect patch
      final patchAfter4 = buildMsPlusPatch(slotCount: 5, rightOutputTapCode: 5);
      final ptcfAfter4 = protocol.encodePtcf(patchAfter4);
      final prm2After4 = findPrm2Offset(ptcfAfter4);
      expect(ptcfAfter4[prm2After4 + 13], equals(0x0A));
      expect(protocol.decodePtcf(ptcfAfter4).rightOutputTapCode, equals(5));

      // 0x0C = After Effect 5 / slot 4 (tap code 6 << 1) in a 6-effect patch
      final patchAfter5 = buildMsPlusPatch(slotCount: 6, rightOutputTapCode: 6);
      final ptcfAfter5 = protocol.encodePtcf(patchAfter5);
      final prm2After5 = findPrm2Offset(ptcfAfter5);
      expect(ptcfAfter5[prm2After5 + 13], equals(0x0C));
      expect(protocol.decodePtcf(ptcfAfter5).rightOutputTapCode, equals(6));
    });

    test('decodePtcf preserves unrelated bits in prm2[13] and clamps invalid values > numEffects + 1 to 0', () {
      final base = buildMsPlusPatch(slotCount: 5, rightOutputTapCode: 0);
      final ptcf = Uint8List.fromList(protocol.encodePtcf(base));
      final prm2 = findPrm2Offset(ptcf);
      expect(prm2, isNot(-1));

      // Set unrelated bits (0xF0 | 0x01) + tap code 5 (0x0A) -> 0xFB
      ptcf[prm2 + 13] = 0xFB;
      expect(protocol.decodePtcf(ptcf).rightOutputTapCode, equals(5));

      // Invalid value 7 (> numEffects + 1 = 6) -> clamped safely to 0
      ptcf[prm2 + 13] = 0x0E;
      expect(protocol.decodePtcf(ptcf).rightOutputTapCode, equals(0));

      // Value 6 (== numEffects + 1 in 5-effect patch, after final slot) -> normalized to 0
      ptcf[prm2 + 13] = 0x0C;
      expect(protocol.decodePtcf(ptcf).rightOutputTapCode, equals(0));
    });

    test('writes 0x00 into prm2[13] for Zoom Four patches', () {
      const fourProtocol = ZoomFourProtocol();
      final fourPatch = Patch(
        id: 'four_test',
        name: 'B1X Four',
        deviceFamily: DeviceFamily.zoomB1xFour,
        slots: buildSlots(5),
        rightOutputTapCode: 3, // Even if somehow set on model, Four encodes 0
      );

      final ptcf = fourProtocol.encodePtcf(fourPatch);
      final prm2 = findPrm2Offset(ptcf);
      expect(prm2, isNot(-1));
      expect(ptcf[prm2 + 13], equals(0x00));
      expect(fourProtocol.decodePtcf(ptcf).rightOutputTapCode, equals(0));
    });

    test('round-trips R-Out tap through .zptc, .syx, and .json export/import adapters', () {
      final exportRegistry = ExportAdapterRegistry.standard();
      final importer = PatchImporter.standard();
      const syxImport = RawSysExImportAdapter();

      final patch = buildMsPlusPatch(
        family: DeviceFamily.zoomMs70cdrPlus,
        slotCount: 5,
        rightOutputTapCode: 4, // After slot 2 (Effect 3)
      );

      // 1. .zptc adapters (generic PTCF, Symbiosis, MultiStomp Studio)
      for (final format in [
        ExportFormat.zoomPtcf,
        ExportFormat.symbiosisZptc,
        ExportFormat.zoomMultistompStudio,
      ]) {
        final payload = exportRegistry.adapterFor(format).exportPatch(patch);
        final fileName = format == ExportFormat.zoomMultistompStudio
            ? 'multistomp_${payload.suggestedName}'
            : payload.suggestedName;
        final res = importer.importBytes(
          payload.bytes,
          sourceName: fileName,
          targetDeviceHint: DeviceFamily.zoomMs70cdrPlus,
        );
        expect(res.hasErrors, isFalse, reason: 'Errors for $format');
        expect(
          res.entries.single.patch.rightOutputTapCode,
          equals(4),
          reason: 'R-Out tap should round-trip for $format',
        );
      }

      // 2. .syx (slot dump 0x45 via adapter + current patch dump 64 12 01 via protocol)
      final syxPayload =
          exportRegistry.adapterFor(ExportFormat.rawSysEx).exportPatch(patch);
      final syxResult = syxImport.importBytes(
        syxPayload.bytes,
        sourceName: syxPayload.suggestedName,
        targetDeviceHint: DeviceFamily.zoomMs70cdrPlus,
      );
      expect(syxResult.hasErrors, isFalse);
      expect(syxResult.entries.single.patch.rightOutputTapCode, equals(4));

      final currentDump =
          const ZoomMsPlusProtocol(defaultFamily: DeviceFamily.zoomMs70cdrPlus)
              .encodePatch(patch);
      final currentResult = syxImport.importBytes(
        currentDump.data,
        sourceName: 'current.syx',
        targetDeviceHint: DeviceFamily.zoomMs70cdrPlus,
      );
      expect(currentResult.hasErrors, isFalse);
      expect(currentResult.entries.single.patch.rightOutputTapCode, equals(4));

      // 3. .json
      final jsonPayload =
          exportRegistry.adapterFor(ExportFormat.nativeJson).exportPatch(patch);
      final jsonResult = importer.importBytes(
        jsonPayload.bytes,
        sourceName: jsonPayload.suggestedName,
      );
      expect(jsonResult.hasErrors, isFalse);
      expect(jsonResult.entries.single.patch.rightOutputTapCode, equals(4));
      final decodedJson = json.decode(utf8.decode(jsonPayload.bytes))
          as Map<String, dynamic>;
      expect(decodedJson['rightOutputTapCode'], equals(4));
    });
  });

  group('PatchEditorController R-Out Routing & Slot Invariants', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connection;
    late PatchEditorController editor;

    setUp(() async {
      transport = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'ms60bp',
            name: 'ZOOM MS-60B+ MIDI 1',
            isInput: true,
            isOutput: true,
          ),
        ],
      );
      connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: buildMsPlusPatch(slotCount: 4),
      );
      await transport.connect('ms60bp');
      transport.clearSentMessages();
    });

    tearDown(() async {
      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });

    test('setRightOutputTap normalizes bounds, sets dirty, supports undo/redo, and sends real-time 64 20 00 64 04 SysEx', () async {
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(editor.isDirty, isFalse);

      // No-op when unchanged
      editor.setRightOutputTap(0);
      expect(editor.isDirty, isFalse);
      expect(editor.canUndo, isFalse);
      expect(transport.sentMessages, isEmpty);

      // Set tap to After Effect 2 (code 3) in a 4-slot patch
      editor.setRightOutputTap(3);
      expect(editor.patch!.rightOutputTapCode, equals(3));
      expect(editor.isDirty, isTrue);
      expect(editor.canUndo, isTrue);

      // Must transmit single 15-byte 64 20 00 64 04 message (never 0x51, 64 12 01, 0x50, or 0x45)
      const proto = ZoomMsPlusProtocol();
      expect(transport.sentMessages.length, equals(1));
      final msg = transport.sentMessages.single;
      expect(
        msg.data,
        equals([
          0xF0, 0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x64, 0x04, 0x03, 0x00, 0x00, 0x00, 0x00, 0xF7,
        ]),
      );
      expect(msg, equals(proto.buildRightOutputTapMessage(3)));
      expect(proto.isCurrentPatchDump(msg), isFalse);
      expect(proto.isSlotPatchDump(msg), isFalse);

      // Tapping after final slot (code = slots.length + 1 = 5) normalizes to 0 (End of Chain)
      transport.clearSentMessages();
      editor.setRightOutputTap(5);
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(transport.sentMessages.length, equals(1));
      expect(
        transport.sentMessages.single,
        equals(proto.buildRightOutputTapMessage(0)),
      );

      // Out-of-range values clamp/normalize to 0; Input (1) stays 1
      editor.setRightOutputTap(1);
      expect(editor.patch!.rightOutputTapCode, equals(1));
      editor.setRightOutputTap(99);
      expect(editor.patch!.rightOutputTapCode, equals(0));
      editor.setRightOutputTap(1);
      editor.setRightOutputTap(-2);
      expect(editor.patch!.rightOutputTapCode, equals(0));

      // Undo back through history restores previous tap & syncs hardware via 64 20 00 64 04
      transport.clearSentMessages();
      expect(editor.undo(), isTrue); // -> 1
      expect(editor.patch!.rightOutputTapCode, equals(1));
      expect(transport.sentMessages.length, equals(2));
      expect(
        transport.sentMessages[0],
        equals(proto.buildSlotFocusMessage(0)),
      );
      expect(
        transport.sentMessages[1],
        equals(proto.buildRightOutputTapMessage(1)),
      );

      expect(editor.undo(), isTrue); // -> 0
      expect(editor.undo(), isTrue); // -> 1
      expect(editor.undo(), isTrue); // -> 0
      expect(editor.undo(), isTrue); // -> 3
      expect(editor.patch!.rightOutputTapCode, equals(3));
      expect(editor.undo(), isTrue); // -> initial 0, clean
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(editor.isDirty, isFalse);

      // Redo reapplies tap 3
      transport.clearSentMessages();
      expect(editor.redo(), isTrue);
      expect(editor.patch!.rightOutputTapCode, equals(3));
      expect(editor.isDirty, isTrue);
      expect(transport.sentMessages.length, equals(2));
      expect(
        transport.sentMessages[0],
        equals(proto.buildSlotFocusMessage(0)),
      );
      expect(
        transport.sentMessages[1],
        equals(proto.buildRightOutputTapMessage(3)),
      );
    });

    test('incoming 64 20 00 64 04 updates R-Out tap live without echoing back or pushing undo history', () async {
      int notifyCount = 0;
      editor.addListener(() => notifyCount++);

      // Simulate pedal broadcasting R-Out tap change to After Effect 2 (code 3)
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([
          0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x64, 0x04, 0x03, 0x00, 0x00, 0x00, 0x00,
        ]),
      );
      await pumpEventQueue();

      expect(editor.patch!.rightOutputTapCode, equals(3));
      expect(notifyCount, equals(1));
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      expect(transport.sentMessages, isEmpty);

      // Duplicate incoming value does not fire redundant notifications
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([
          0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x64, 0x04, 0x03, 0x00, 0x00, 0x00, 0x00,
        ]),
      );
      await pumpEventQueue();
      expect(notifyCount, equals(1));
      expect(transport.sentMessages, isEmpty);

      // ACK frame (64 20 01 64 04) is ignored
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([
          0x52, 0x00, 0x6E, 0x64, 0x20, 0x01, 0x64, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00,
        ]),
      );
      await pumpEventQueue();
      expect(editor.patch!.rightOutputTapCode, equals(3));
      expect(notifyCount, equals(1));

      // Out-of-range code (5 in 4-slot patch) normalizes to 0
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([
          0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x64, 0x04, 0x05, 0x00, 0x00, 0x00, 0x00,
        ]),
      );
      await pumpEventQueue();
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(notifyCount, equals(2));
      expect(transport.sentMessages, isEmpty);

      // Direct applyExternalHardwareUpdate also normalizes without echo
      editor.applyExternalHardwareUpdate(rightOutputTapCode: 2);
      expect(editor.patch!.rightOutputTapCode, equals(2));
      expect(notifyCount, equals(3));
      expect(transport.sentMessages, isEmpty);

      // Non-MS+ devices ignore incoming 64 20 00 64 04 and applyExternalHardwareUpdate
      connection.selectDeviceFamily(DeviceFamily.zoomB1xFour);
      editor.loadPatch(
        Patch(
          id: 'four_incoming',
          name: 'Four',
          deviceFamily: DeviceFamily.zoomB1xFour,
          slots: buildSlots(4),
        ),
      );
      transport.clearSentMessages();
      transport.simulateIncomingMessage(
        MidiMessage.sysEx([
          0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x64, 0x04, 0x02, 0x00, 0x00, 0x00, 0x00,
        ]),
      );
      await pumpEventQueue();
      editor.applyExternalHardwareUpdate(rightOutputTapCode: 2);
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(transport.sentMessages, isEmpty);
    });

    test('_syncPatchTransitionToDevice and structural slot edits send 64 20 00 64 04 without 0x51/64 12 01/0x50', () {
      const proto = ZoomMsPlusProtocol();

      // 1. activatePatchLive transition from tap 0 -> tap 3 sends 64 20 00 64 04 03
      final tappedPatch = buildMsPlusPatch(slotCount: 4, rightOutputTapCode: 3)
          .copyWith(id: 'live_target_1');
      editor.activatePatchLive(tappedPatch);
      expect(
        transport.sentMessages,
        contains(proto.buildRightOutputTapMessage(3)),
      );
      expect(
        transport.sentMessages.any(
          (m) =>
              m == proto.buildEditorModeMessage(enable: false) ||
              m == proto.buildEditorModeMessage(enable: true) ||
              proto.isCurrentPatchDump(m),
        ),
        isFalse,
      );

      // 2. activatePatchLive to another patch with the same tap (3) does not emit 64 20 00 64 04
      transport.clearSentMessages();
      final sameTapPatch = buildMsPlusPatch(slotCount: 4, rightOutputTapCode: 3)
          .copyWith(id: 'live_target_2');
      editor.activatePatchLive(sameTapPatch);
      expect(
        transport.sentMessages.any(proto.isRightOutputTapChange),
        isFalse,
      );

      // 3. A/B compare toggle back to tap 0 sends 64 20 00 64 04 00
      editor.loadPatch(buildMsPlusPatch(slotCount: 4, rightOutputTapCode: 0));
      editor.setRightOutputTap(2);
      transport.clearSentMessages();
      editor.toggleCompareSlot();
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(
        transport.sentMessages,
        contains(proto.buildRightOutputTapMessage(0)),
      );
      expect(
        transport.sentMessages.any(
          (m) =>
              m == proto.buildEditorModeMessage(enable: false) ||
              m == proto.buildEditorModeMessage(enable: true) ||
              proto.isCurrentPatchDump(m),
        ),
        isFalse,
      );

      // 4. Slot insertion that shifts tap code sends 64 20 00 64 04
      editor.loadPatch(buildMsPlusPatch(slotCount: 4, rightOutputTapCode: 3));
      transport.clearSentMessages();
      expect(editor.addEffectSlot(index: 0, effectId: '0x07000010'), isTrue);
      expect(editor.patch!.rightOutputTapCode, equals(4));
      expect(
        transport.sentMessages,
        contains(proto.buildRightOutputTapMessage(4)),
      );
      expect(
        transport.sentMessages.any(
          (m) =>
              m == proto.buildEditorModeMessage(enable: false) ||
              m == proto.buildEditorModeMessage(enable: true) ||
              proto.isCurrentPatchDump(m),
        ),
        isFalse,
      );
    });

    test('setRightOutputTap is guarded on non-MS+ devices', () {
      connection.selectDeviceFamily(DeviceFamily.zoomB1xFour);
      editor.loadPatch(
        Patch(
          id: 'four',
          name: 'Four',
          deviceFamily: DeviceFamily.zoomB1xFour,
          slots: buildSlots(4),
        ),
      );
      transport.clearSentMessages();

      editor.setRightOutputTap(2);
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(editor.isDirty, isFalse);
      expect(transport.sentMessages, isEmpty);

      connection.selectDeviceFamily(DeviceFamily.line6BassPodPro);
      editor.loadPatch(
        Patch(
          id: 'line6',
          name: 'Line6',
          deviceFamily: DeviceFamily.line6BassPodPro,
          slots: buildSlots(2),
        ),
      );
      editor.setRightOutputTap(1);
      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(editor.isDirty, isFalse);
    });

    test('slot insertion and removal preserve R-Out tap invariants', () {
      // Start with 4 slots (0..3) and tap after slot 1 (tapCode = 3)
      editor.setRightOutputTap(3);
      expect(editor.patch!.rightOutputTapCode, equals(3));

      // Insert at index 0 (<= tapped slot 1) -> tap increments to 4 (stays after old slot 1, now slot 2)
      expect(editor.addEffectSlot(index: 0, effectId: '0x07000010'), isTrue);
      expect(editor.patch!.slots.length, equals(5));
      expect(editor.patch!.rightOutputTapCode, equals(4));

      // Insert at index 4 (> tapped slot 2) -> tap stays 4
      expect(editor.addEffectSlot(index: 4, effectId: '0x07000020'), isTrue);
      expect(editor.patch!.slots.length, equals(6));
      expect(editor.patch!.rightOutputTapCode, equals(4));

      // Remove slot 0 (< tapped slot 2) -> tap decrements to 3 (stays after slot 1)
      expect(editor.removeEffectSlot(0), isTrue);
      expect(editor.patch!.slots.length, equals(5));
      expect(editor.patch!.rightOutputTapCode, equals(3));

      // Remove tapped slot 1 -> resets to 0 (End of Chain)
      expect(editor.removeEffectSlot(1), isTrue);
      expect(editor.patch!.slots.length, equals(4));
      expect(editor.patch!.rightOutputTapCode, equals(0));

      // Removing the final slot when tapping the second-to-last slot normalizes to 0
      editor.setRightOutputTap(4); // After slot 2 in 4-slot chain (slots 0..3)
      expect(editor.patch!.rightOutputTapCode, equals(4));
      expect(editor.removeEffectSlot(3), isTrue); // Now 3 slots (0..2); slot 2 is final
      expect(editor.patch!.rightOutputTapCode, equals(0));

      // Input (1) stays 1 across insert/remove
      editor.setRightOutputTap(1);
      expect(editor.addEffectSlot(index: 0, effectId: '0x07000010'), isTrue);
      expect(editor.patch!.rightOutputTapCode, equals(1));
      expect(editor.removeEffectSlot(0), isTrue);
      expect(editor.patch!.rightOutputTapCode, equals(1));
    });

    test('moveEffectSlot, reorderEffectSlots, and swapEffectSlots keep R-Out normalized within 0..slots.length', () {
      editor.loadPatch(buildMsPlusPatch(slotCount: 3, rightOutputTapCode: 3));
      expect(editor.moveEffectSlot(0, 2), isTrue);
      expect(editor.patch!.rightOutputTapCode, inInclusiveRange(0, 3));

      expect(editor.reorderEffectSlots(2, 0), isTrue);
      expect(editor.patch!.rightOutputTapCode, inInclusiveRange(0, 3));

      expect(editor.swapEffectSlots(0, 2), isTrue);
      expect(editor.patch!.rightOutputTapCode, inInclusiveRange(0, 3));

      // Even if a patch arrived with out-of-bounds tapCode > slots.length, reorder normalizes it
      editor.loadPatch(buildMsPlusPatch(slotCount: 3, rightOutputTapCode: 5));
      expect(editor.swapEffectSlots(0, 1), isTrue);
      expect(editor.patch!.rightOutputTapCode, equals(0));
    });
  });

  group('SignalChainStripWidget R-Out UI', () {
    Future<PatchEditorController> pumpStrip(
      WidgetTester tester, {
      required DeviceFamily family,
      int slotCount = 3,
      int rightOutputTapCode = 0,
    }) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: family,
      );
      final patch = Patch(
        id: 'ui_test',
        name: 'UI Test',
        deviceFamily: family,
        slots: buildSlots(slotCount),
        rightOutputTapCode: rightOutputTapCode,
      );
      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: patch,
      );

      addTearDown(() async {
        editor.dispose();
        connection.dispose();
        await transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignalChainStripWidget(controller: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return editor;
    }

    testWidgets('renders L/R OUT by default, updates R-OUT split badge position via menu on MS+ patch', (tester) async {
      final editor = await pumpStrip(
        tester,
        family: DeviceFamily.zoomMs60bPlus,
        slotCount: 3,
      );

      // Default: tapCode == 0 -> L/R OUT on output badge, R-OUT selector pill present, no split badge
      expect(find.text('L/R OUT'), findsOneWidget);
      expect(find.text('L OUT'), findsNothing);
      expect(find.byKey(const Key('right_out_tap_selector')), findsOneWidget);
      expect(find.byKey(const Key('signal_chain_out_badge')), findsOneWidget);
      expect(find.byKey(const Key('signal_chain_r_out_badge')), findsNothing);

      // Open selector pill and select Input (Dry) -> tapCode == 1
      await tester.tap(find.byKey(const Key('right_out_tap_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('r_out_menu_item_1')));
      await tester.pumpAndSettle();

      expect(editor.patch!.rightOutputTapCode, equals(1));
      expect(find.text('L OUT'), findsOneWidget);
      expect(find.text('L/R OUT'), findsNothing);
      expect(find.byKey(const Key('signal_chain_r_out_badge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('insertion_zone_0')),
          matching: find.byKey(const Key('signal_chain_r_out_badge')),
        ),
        findsOneWidget,
      );

      // Click the inline R-OUT badge and select After 2: Bass Preamp -> tapCode == 3
      await tester.tap(find.byKey(const Key('signal_chain_r_out_badge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('r_out_menu_item_3')));
      await tester.pumpAndSettle();

      expect(editor.patch!.rightOutputTapCode, equals(3));
      expect(
        find.descendant(
          of: find.byKey(const Key('insertion_zone_2')),
          matching: find.byKey(const Key('signal_chain_r_out_badge')),
        ),
        findsOneWidget,
      );

      // Click the L OUT badge and return to End of Chain (L+R Out) -> tapCode == 0
      await tester.tap(find.byKey(const Key('signal_chain_out_badge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('r_out_menu_item_0')));
      await tester.pumpAndSettle();

      expect(editor.patch!.rightOutputTapCode, equals(0));
      expect(find.text('L/R OUT'), findsOneWidget);
      expect(find.byKey(const Key('signal_chain_r_out_badge')), findsNothing);
    });

    testWidgets('hides R-Out controls completely on Zoom Four and Line 6 patches', (tester) async {
      await pumpStrip(
        tester,
        family: DeviceFamily.zoomB1xFour,
        slotCount: 3,
        rightOutputTapCode: 2,
      );

      expect(find.byKey(const Key('right_out_tap_selector')), findsNothing);
      expect(find.byKey(const Key('signal_chain_r_out_badge')), findsNothing);
      expect(find.byKey(const Key('signal_chain_out_badge')), findsNothing);
      expect(find.text('L/R OUT'), findsNothing);
      expect(find.text('L OUT'), findsNothing);
      expect(find.text('OUT'), findsOneWidget);

      await pumpStrip(
        tester,
        family: DeviceFamily.line6BassPodPro,
        slotCount: 2,
        rightOutputTapCode: 1,
      );

      expect(find.byKey(const Key('right_out_tap_selector')), findsNothing);
      expect(find.byKey(const Key('signal_chain_r_out_badge')), findsNothing);
      expect(find.byKey(const Key('signal_chain_out_badge')), findsNothing);
      expect(find.text('L/R OUT'), findsNothing);
      expect(find.text('L OUT'), findsNothing);
      expect(find.text('OUT'), findsOneWidget);
    });
  });
}

