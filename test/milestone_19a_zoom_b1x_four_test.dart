@Timeout(Duration(seconds: 10)) library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/import_format.dart';
import 'package:signal_chain_flutter/core/import/patch_importer.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/data/zoom_four_catalog.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/editor/write_to_slot_dialog.dart';
import 'package:signal_chain_flutter/models/bank_slot_descriptor.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

Patch _buildSampleB1xFourPatch({
  String id = 'b1xf_patch_01',
  String name = 'Motown B1X',
  int? programNumber = 0,
  DeviceFamily family = DeviceFamily.zoomB1xFour,
  int slotCount = 5,
}) {
  final allDefs = [
    ZoomFourCatalog.getByName('OptComp')!,
    ZoomFourCatalog.getByName('Bass DRV')!,
    ZoomFourCatalog.getByName('FlipTop')!,
    ZoomFourCatalog.getByName('AM1x15')!,
    ZoomFourCatalog.getByName('PDL Vol')!,
    ZoomFourCatalog.getByName('Hall')!,
  ];

  final slots = <EffectSlot>[];
  for (int i = 0; i < slotCount && i < allDefs.length; i++) {
    final def = allDefs[i];
    slots.add(EffectSlot(
      slotIndex: i,
      effectId: def.effectId,
      effectName: def.name,
      isEnabled: true,
      parameters: [
        for (int p = 0; p < def.parameters.length; p++)
          ParameterValue(
            descriptor: def.parameters[p],
            currentValue: p == 0
                ? (def.parameters[p].defaultValue + 5).clamp(
                    def.parameters[p].min,
                    def.parameters[p].max,
                  )
                : def.parameters[p].defaultValue,
          ),
      ],
    ));
  }

  return Patch(
    id: id,
    name: name,
    deviceFamily: family,
    programNumber: programNumber,
    slots: slots,
    notes: 'Warm flatwound bass chain with volume pedal',
    metadata: const {'tempo': 108},
  );
}

void main() {
  setUp(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('Zoom Four Identity & USB Port Detection', () {
    test('detects B1X FOUR, B1 FOUR, G1X FOUR, G1 FOUR from USB strings without MS+ collision', () {
      expect(ZoomFourProfile.fromPortName('ZOOM B1X FOUR'), ZoomFourProfile.b1xFour);
      expect(ZoomFourProfile.fromPortName('ZOOM B1X FOUR MIDI 1'), ZoomFourProfile.b1xFour);
      expect(ZoomFourProfile.fromPortName('ZOOM B1 FOUR'), ZoomFourProfile.b1Four);
      expect(ZoomFourProfile.fromPortName('ZOOM G1X FOUR MIDI In'), ZoomFourProfile.g1xFour);
      expect(ZoomFourProfile.fromPortName('ZOOM G1 FOUR'), ZoomFourProfile.g1Four);
      expect(ZoomFourProfile.fromPortName('ZOOM MS-60B+'), isNull);
      expect(ZoomFourProfile.fromPortName('ZOOM MS-50G+'), isNull);

      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM B1X FOUR MIDI 1'),
        DeviceFamily.zoomB1xFour,
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM B1 FOUR'),
        DeviceFamily.zoomB1Four,
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM G1X FOUR'),
        DeviceFamily.zoomG1xFour,
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM G1 FOUR'),
        DeviceFamily.zoomG1Four,
      );
      expect(
        DeviceConnectionController.identifyFamilyFromPortName('ZOOM MS-60B+'),
        DeviceFamily.zoomMs60bPlus,
      );
    });

    test('parses 0x6E Universal Identity Reply sub-model bytes accurately', () {
      const protocol = ZoomFourProtocol();

      MidiMessage buildIdentity(int subModelId) => MidiMessage.sysEx([
            0x7E,
            0x7F,
            0x06,
            0x02,
            0x52,
            0x6E,
            0x00,
            subModelId,
            0x00,
            0x31,
            0x30,
            0x30,
            0x30,
          ]);

      expect(protocol.matchesIdentityResponse(buildIdentity(0x0F)), isTrue);
      expect(protocol.parseDeviceFamily(buildIdentity(0x0F)), DeviceFamily.zoomB1xFour);
      expect(protocol.parseDeviceFamily(buildIdentity(0x0E)), DeviceFamily.zoomB1Four);
      expect(protocol.parseDeviceFamily(buildIdentity(0x0D)), DeviceFamily.zoomG1xFour);
      expect(protocol.parseDeviceFamily(buildIdentity(0x0C)), DeviceFamily.zoomG1Four);
      // Legacy aliases
      expect(protocol.parseDeviceFamily(buildIdentity(0x1F)), DeviceFamily.zoomB1xFour);
      expect(protocol.parseDeviceFamily(buildIdentity(0x1E)), DeviceFamily.zoomB1Four);
      expect(protocol.parseDeviceFamily(buildIdentity(0x1D)), DeviceFamily.zoomG1xFour);
      expect(protocol.parseDeviceFamily(buildIdentity(0x1C)), DeviceFamily.zoomG1Four);
      expect(protocol.parseDeviceFamily(buildIdentity(0x27)), DeviceFamily.zoomMs60bPlus);

      expect(DeviceFamily.zoomB1xFour.generation, DeviceGeneration.zoomFour);
      expect(DeviceFamily.zoomB1Four.generation, DeviceGeneration.zoomFour);
      expect(DeviceFamily.zoomG1xFour.generation, DeviceGeneration.zoomFour);
      expect(DeviceFamily.zoomG1Four.generation, DeviceGeneration.zoomFour);
      expect(DeviceFamily.zoomMs60bPlus.generation, DeviceGeneration.zoomMsPlus);
    });

    test('connection controller auto-handshake selects B1X FOUR and initializes 50 slots', () async {
      const port = MidiPortDescriptor(
        id: 'zoom_b1x_1',
        name: 'ZOOM B1X FOUR MIDI 1',
        manufacturer: 'ZOOM',
        isInput: true,
        isOutput: true,
      );
      final transport = MockMidiTransport(initialPorts: [port]);
      transport.registerResponder(
        (msg) =>
            msg.data.length >= 6 &&
            msg.data[1] == 0x7E &&
            msg.data[3] == 0x06 &&
            msg.data[4] == 0x01,
        (_) => MidiMessage.sysEx([
          0x7E, 0x7F, 0x06, 0x02,
          0x52, 0x6E, 0x00, ZoomMsPlusProtocol.modelIdB1xFour, 0x00,
          0x31, 0x2E, 0x31, 0x30,
        ]),
      );

      final connection = DeviceConnectionController(transport: transport);
      addTearDown(() async {
        connection.dispose();
        await transport.dispose();
      });

      await connection.connect(port, fetchCurrentPatch: false);

      expect(connection.activeFamily, DeviceFamily.zoomB1xFour);
      expect(connection.activeFamily.generation, DeviceGeneration.zoomFour);
      expect(connection.activeFamily.hasExpressionPedal, isTrue);
      expect(connection.activeProtocol, isA<ZoomFourProtocol>());
      expect(connection.bankSlots.length, 50);
      expect(connection.bankSlots.first.formattedSlotIndex, '10');
      expect(connection.bankSlots.last.formattedSlotIndex, '59');
      expect(connection.bankSlots.first.name, 'Slot 10');
      expect(connection.bankSlots.last.name, 'Slot 59');
    });
  });

  group('ZoomFourProfile Constraints & Hardware Numbering (10-59)', () {
    test('exposes expression pedal capability flags and 5-slot / 50-patch limits', () {
      expect(ZoomFourProfile.b1xFour.hasExpressionPedal, isTrue);
      expect(ZoomFourProfile.g1xFour.hasExpressionPedal, isTrue);
      expect(ZoomFourProfile.b1Four.hasExpressionPedal, isFalse);
      expect(ZoomFourProfile.g1Four.hasExpressionPedal, isFalse);

      expect(DeviceFamily.zoomB1xFour.maxEffectSlots, 5);
      expect(DeviceFamily.zoomB1xFour.totalMemorySlots, 50);
      expect(DeviceFamily.zoomB1xFour.hasExpressionPedal, isTrue);
      expect(DeviceFamily.zoomB1Four.hasExpressionPedal, isFalse);
      expect(DeviceFamily.zoomMs60bPlus.maxEffectSlots, 6);
      expect(DeviceFamily.zoomMs60bPlus.totalMemorySlots, 100);
    });

    test('formats zero-based indices 0..49 as hardware labels 10..59 and banks 10-19..50-59', () {
      const protocol = ZoomFourProtocol();
      expect(protocol.formatPatchNumber(0), '10');
      expect(protocol.formatPatchNumber(9), '19');
      expect(protocol.formatPatchNumber(10), '20');
      expect(protocol.formatPatchNumber(49), '59');

      expect(protocol.parsePatchNumber('10'), 0);
      expect(protocol.parsePatchNumber('59'), 49);
      expect(protocol.parsePatchNumber('09'), isNull);
      expect(protocol.parsePatchNumber('60'), isNull);

      expect(ZoomFourProfile.formatBankRange(0), '10–19');
      expect(ZoomFourProfile.formatBankRange(1), '20–29');
      expect(ZoomFourProfile.formatBankRange(4), '50–59');

      const firstSlot = BankSlotDescriptor(
        index: 0,
        name: 'Clean Jazz',
        deviceFamily: DeviceFamily.zoomB1xFour,
      );
      const lastSlot = BankSlotDescriptor(
        index: 49,
        name: 'Synth Lead',
        deviceFamily: DeviceFamily.zoomB1xFour,
      );
      expect(firstSlot.hardwarePatchLabel, '10');
      expect(firstSlot.formattedSlotIndex, '10');
      expect(firstSlot.bankAndProgramNumber, '1-0');
      expect(firstSlot.slotLabel, '#10 (1-0)');

      expect(lastSlot.hardwarePatchLabel, '59');
      expect(lastSlot.formattedSlotIndex, '59');
      expect(lastSlot.bankAndProgramNumber, '5-9');
      expect(lastSlot.slotLabel, '#59 (5-9)');
    });
  });

  group('5-Slot PTCF & SysEx Round-Trip', () {
    test('round-trips a 5-slot Zoom B1X FOUR patch through PtcfCodec and ZoomFourProtocol', () {
      final original = _buildSampleB1xFourPatch();
      const codec = PtcfCodec(defaultFamily: DeviceFamily.zoomB1xFour);
      const protocol = ZoomFourProtocol();

      final ptcfBytes = codec.encode(original);
      expect(PtcfCodec.isPtcfBuffer(ptcfBytes), isTrue);
      expect(PtcfCodec.detectGeneration(ptcfBytes), DeviceGeneration.zoomFour);

      final decodedPtcf = codec.decode(ptcfBytes, programNumber: 49);
      expect(decodedPtcf.name, 'Motown B1X');
      expect(decodedPtcf.deviceFamily, DeviceFamily.zoomB1xFour);
      expect(decodedPtcf.generation, DeviceGeneration.zoomFour);
      expect(decodedPtcf.slots.length, 5);
      expect(decodedPtcf.slots.map((s) => s.effectName).toList(), [
        'OptComp',
        'Bass DRV',
        'FlipTop',
        'AM1x15',
        'PDL Vol',
      ]);
      expect(decodedPtcf.slots[1].parameters.first.currentValue, 70.0);

      // SysEx 0x45 memory slot dump round-trip at slot 49 (hardware patch 59 -> Bank 4, Prog 9)
      final sysexMsg = protocol.encodePatch(original, programNumber: 49);
      expect(protocol.isSlotPatchDump(sysexMsg), isTrue);
      expect(protocol.extractSlotIndex(sysexMsg), 49);

      final decodedSysex = protocol.decodePatch(sysexMsg);
      expect(decodedSysex.deviceFamily, DeviceFamily.zoomB1xFour);
      expect(decodedSysex.generation, DeviceGeneration.zoomFour);
      expect(decodedSysex.programNumber, 49);
      expect(decodedSysex.slots.length, 5);
      expect(decodedSysex.slots[4].effectName, 'PDL Vol');
    });

    test('enforces 5-slot maximum limit in ZoomFourProtocol & PatchEditorController', () async {
      final sixSlotPatch = _buildSampleB1xFourPatch(slotCount: 6);
      expect(sixSlotPatch.slots.length, 6);

      const protocol = ZoomFourProtocol();
      final ptcf = protocol.encodePtcf(sixSlotPatch);
      final decoded = protocol.decodePtcf(ptcf);
      expect(decoded.slots.length, 5);
      expect(decoded.slots.last.effectName, 'PDL Vol');

      // Slot bypass/parameter edits reject slotIndex == 5 on ZoomFour (valid only on MS+ 0..5)
      final slot5Bypass = MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x05, 0x00, 0x01]);
      expect(protocol.isSlotBypass(slot5Bypass), isFalse);
      expect(const ZoomMsPlusProtocol().isSlotBypass(slot5Bypass), isTrue);

      // PatchEditorController enforces activeFamily.maxEffectSlots == 5
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomB1xFour,
      );
      final fiveSlot = _buildSampleB1xFourPatch(slotCount: 5);
      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: fiveSlot,
      );
      addTearDown(() async {
        editor.dispose();
        connection.dispose();
        await transport.dispose();
      });

      expect(editor.canAddEffectSlot, isFalse);
      editor.removeEffectSlot(4);
      expect(editor.patch!.slots.length, 4);
      expect(editor.canAddEffectSlot, isTrue);
    });
  });

  group('Zoom B1X FOUR Effect Catalog Coverage & Isolation', () {
    test('includes all 99 authoritative ZDL7 B1X FOUR effects and expression pedal models', () {
      expect(ZoomFourCatalog.allB1xFourEffects.length, 99);
      const requiredNames = [
        // Dynamics / Filter
        'SlowATTCK', 'ZNR', 'OptComp', '160 Comp', 'DualComp', 'BassA-Wah', 'Z Tron',
        // Overdrive / Distortion
        'Bass DRV', 'D.I Plus', 'Dark Pre', 'Bass BB', 'NYC Muff', 'BassMetal',
        // Amps & Cabinets
        'AMPG SVT', 'FlipTop', 'BMAN100', 'AG 750', 'SMR400', 'TE400SMX',
        'SVT8x10', 'AM1x15', 'FD-B4x12', 'AG4x10TW', 'SMR4x10TW', 'TE4x10',
        // Modulation / SFX
        'BassStCho', 'CloneCho', 'BaVinFLNG', 'BassPhase', 'Ba Octave', 'StdSyn', 'Defret', 'Bomber',
        // Delay / Reverb
        'Delay', 'AnalogDly', 'TapeEcho', 'Hall', 'Room', 'Plate',
        // Expression Pedal
        'PDL Vol', 'BassWah', 'PDL Reso', 'Ba PDLPit', 'Ba PDLMnP', 'Output VP',
      ];

      for (final name in requiredNames) {
        final def = ZoomFourCatalog.getByName(name);
        expect(def, isNotNull, reason: 'Expected "$name" in Zoom B1X FOUR catalog');
        expect(def!.deviceFamily, DeviceFamily.zoomB1xFour);
        expect(def.parameters, isNotEmpty, reason: 'Expected parameters for "$name"');
        expect(
          EffectCatalogRegistry.getByName(DeviceFamily.zoomB1xFour, name)?.effectId,
          def.effectId,
        );
      }

      // Spot-check key effect IDs, categories & parameters
      final fliptop = ZoomFourCatalog.getByName('FlipTop')!;
      expect(fliptop.effectId, '0x04800091');
      expect(fliptop.category, 'Amp');
      expect(fliptop.parameters.map((p) => p.name), containsAll(['Gain', 'Bass', 'Trebl', 'Vol']));

      final bassDrv = ZoomFourCatalog.getByName('Bass DRV')!;
      expect(bassDrv.effectId, '0x03800011');
      expect(bassDrv.category, 'Overdrive / Distortion');
      expect(bassDrv.parameters.map((p) => p.name), containsAll(['Drive', 'Blend', 'Bass']));

      final pdlVol = ZoomFourCatalog.getByName('PDL Vol')!;
      expect(pdlVol.effectId, '0x0b000010');
      expect(pdlVol.category, 'Pedal');
      final bassWah = ZoomFourCatalog.getByName('BassWah')!;
      expect(bassWah.effectId, '0x0b800010');
      expect(bassWah.category, 'Pedal');

      // B1 FOUR (no expression pedal) omits 6 'Pedal' effects (93 remaining)
      final b1FourCatalog = ZoomFourCatalog.effectsForFamily(DeviceFamily.zoomB1Four);
      expect(b1FourCatalog.length, 93);
      expect(b1FourCatalog.any((e) => e.category == 'Pedal'), isFalse);
      expect(b1FourCatalog.any((e) => e.name == 'FlipTop'), isTrue);
    });

    test('strictly isolates ZDL7 B1X FOUR effect IDs from MS-60B+ and never falls back', () {
      // 0x01000040 is ZNR on B1X FOUR, DualComp on MS-60B+
      expect(
        EffectCatalogRegistry.getDefinition(DeviceFamily.zoomB1xFour, '0x01000040').name,
        'ZNR',
      );
      expect(
        EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x01000040').name,
        'DualComp',
      );

      // 0x07000010 is Bomber on B1X FOUR, BaOctaver on MS-60B+
      expect(
        EffectCatalogRegistry.getDefinition(DeviceFamily.zoomB1xFour, '0x07000010').name,
        'Bomber',
      );
      expect(
        EffectCatalogRegistry.getDefinition(DeviceFamily.zoomMs60bPlus, '0x07000010').name,
        'BaOctaver',
      );

      // Extended ZDL7 master list IDs resolve accurately (e.g. 0x01000010 -> Comp, NOT MS-60B+ DYN Comp)
      final zdl7Comp = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomB1xFour, '0x01000010');
      expect(zdl7Comp.name, 'Comp');
      expect(EffectCatalogRegistry.getDefinition(DeviceFamily.zoomB1xFour, '0x14400000').name, 'D-28');

      // Genuinely unmapped ID on zoomB1xFour must NOT fall back to MS-60B+
      final unmapped = EffectCatalogRegistry.getDefinition(DeviceFamily.zoomB1xFour, '0x01000099');
      expect(unmapped.name, contains('Unknown'));
      expect(unmapped.name, contains('0x01000099'));

      // Decoding a PTCF patch on ZoomFourProtocol with an unmapped ID preserves raw hex as Unknown
      const fourProto = ZoomFourProtocol();
      final unknownPatch = Patch(
        id: 'unk_1',
        name: 'Unk Test',
        deviceFamily: DeviceFamily.zoomB1xFour,
        slots: const [
          EffectSlot(
            slotIndex: 0,
            effectId: '0x01000099',
            effectName: 'Placeholder',
            isEnabled: true,
          ),
        ],
      );
      final ptcf = fourProto.encodePtcf(unknownPatch);
      final decoded = fourProto.decodePtcf(ptcf);
      expect(decoded.slots.single.effectName, 'Unknown (0x01000099)');
    });

    test('auto-switches DeviceFamily to zoomB1xFour from ALSA port on connect and disconnect/reconnect', () async {
      const alsaPort = MidiPortDescriptor(
        id: 'alsa_24_0',
        name: 'ZOOM B1X FOUR:ZOOM B1X FOUR MIDI 1 24:0',
        manufacturer: 'ZOOM',
        isInput: true,
        isOutput: true,
      );
      final transport = MockMidiTransport(initialPorts: [alsaPort]);
      // Simulate no identity reply (timeout) or unrecognized 0x6E reply
      transport.registerResponder(
        (msg) => msg.data.length >= 6 && msg.data[1] == 0x7E && msg.data[3] == 0x06 && msg.data[4] == 0x01,
        (_) => MidiMessage.sysEx([0x7E, 0x7F, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x27, 0x00, 0x31, 0x30, 0x30, 0x30]),
      );
      final controller = DeviceConnectionController(transport: transport);
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      expect(controller.activeFamily, DeviceFamily.zoomMs60bPlus);

      // Initial connect
      await controller.connect(alsaPort, fetchCurrentPatch: false, autoSyncBank: false);
      expect(controller.activeFamily, DeviceFamily.zoomB1xFour);
      expect(controller.activeProtocol, isA<ZoomFourProtocol>());

      // Disconnect & reconnect must retain zoomB1xFour and decode 0x03800011 as Bass DRV
      await controller.disconnect();
      await controller.connect(alsaPort, fetchCurrentPatch: false, autoSyncBank: false);
      expect(controller.activeFamily, DeviceFamily.zoomB1xFour);
      expect(
        EffectCatalogRegistry.getDefinition(controller.activeFamily, '0x03800011').name,
        'Bass DRV',
      );
    });

    test('filters out 0x00000000 Bypass padding slots and caps zoomFour patches at 5 slots', () {
      const fourProto = ZoomFourProtocol();
      final paddedPatch = Patch(
        id: 'padded_1',
        name: 'Padded B1X',
        deviceFamily: DeviceFamily.zoomB1xFour,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: ZoomFourCatalog.getByName('OptComp')!.effectId,
            effectName: 'OptComp',
            isEnabled: true,
          ),
          const EffectSlot(
            slotIndex: 1,
            effectId: '0x00000000',
            effectName: 'Bypass',
            isEnabled: false,
          ),
          EffectSlot(
            slotIndex: 2,
            effectId: ZoomFourCatalog.getByName('Bass DRV')!.effectId,
            effectName: 'Bass DRV',
            isEnabled: true,
          ),
          const EffectSlot(
            slotIndex: 3,
            effectId: '0x00000000',
            effectName: 'Bypass',
            isEnabled: false,
          ),
        ],
      );
      final ptcf = fourProto.encodePtcf(paddedPatch);
      final decoded = fourProto.decodePtcf(ptcf);
      expect(decoded.slots.map((s) => s.effectName).toList(), ['OptComp', 'Bass DRV']);
      expect(decoded.slots[0].slotIndex, 0);
      expect(decoded.slots[1].slotIndex, 2);
    });

    test('signal chain direction is RTL for MS Plus and LTR for Zoom Four', () {
      expect(DeviceFamily.zoomMs60bPlus.isSignalChainRightToLeft, isTrue);
      expect(DeviceFamily.zoomMs50gPlus.isSignalChainRightToLeft, isTrue);
      expect(DeviceFamily.zoomMs70cdrPlus.isSignalChainRightToLeft, isTrue);
      expect(DeviceFamily.zoomMs200dPlus.isSignalChainRightToLeft, isTrue);

      expect(DeviceFamily.zoomB1xFour.isSignalChainRightToLeft, isFalse);
      expect(DeviceFamily.zoomB1Four.isSignalChainRightToLeft, isFalse);
      expect(DeviceFamily.zoomG1xFour.isSignalChainRightToLeft, isFalse);
      expect(DeviceFamily.zoomG1Four.isSignalChainRightToLeft, isFalse);
      expect(DeviceFamily.zoomB1xFour.isSignalChainLeftToRight, isTrue);
    });

    test('decodes SA-Drive style patch with 3 active effects in slots 0, 2, 4 and 0x00000001 BYPASS slots in 1, 3', () {
      const fourProto = ZoomFourProtocol();
      final saDrive = Patch(
        id: 'sa_drive',
        name: 'SA-Drive',
        deviceFamily: DeviceFamily.zoomB1xFour,
        slots: [
          EffectSlot(
            slotIndex: 0,
            effectId: ZoomFourCatalog.getByName('ZNR')!.effectId,
            effectName: 'ZNR',
            isEnabled: true,
          ),
          const EffectSlot(
            slotIndex: 1,
            effectId: '0x00000001',
            effectName: 'Bypass',
            isEnabled: false,
          ),
          EffectSlot(
            slotIndex: 2,
            effectId: ZoomFourCatalog.getByName('OptComp')!.effectId,
            effectName: 'OptComp',
            isEnabled: true,
          ),
          const EffectSlot(
            slotIndex: 3,
            effectId: '0x00000001',
            effectName: 'Bypass',
            isEnabled: false,
          ),
          EffectSlot(
            slotIndex: 4,
            effectId: ZoomFourCatalog.getByName('Bass DRV')!.effectId,
            effectName: 'Bass DRV',
            isEnabled: true,
          ),
        ],
      );
      final ptcf = fourProto.encodePtcf(saDrive);
      final decoded = fourProto.decodePtcf(ptcf);
      expect(decoded.slots.map((s) => s.effectName).toList(), ['ZNR', 'OptComp', 'Bass DRV']);
      expect(decoded.slots.length, 3);
      // Preserves actual hardware slotIndex (0, 2, 4) for 2-way real-time SysEx editing
      expect(decoded.slots.map((s) => s.slotIndex).toList(), [0, 2, 4]);
    });

    test('ZoomFourProtocol uses 0x64 0x03 0x00 for 2-way real-time bypass, parameter, and effect edits', () async {
      const fourProto = ZoomFourProtocol();

      // 1. Bypass toggle: F0 52 00 6E 64 03 00 <slot> 00 <on/off> 00 00 00 00 F7
      final bypassMsg = fourProto.buildSlotBypassMessage(slotIndex: 2, isEnabled: false);
      expect(bypassMsg.data, [0xF0, 0x52, 0x00, 0x6E, 0x64, 0x03, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF7]);
      expect(fourProto.isSlotBypass(bypassMsg), isTrue);
      expect(fourProto.parseSlotBypass(bypassMsg), (slotIndex: 2, isEnabled: false));

      // 2. Parameter edit: F0 52 00 6E 64 03 00 <slot> <param+2> <lsb> <msb> 00 00 00 F7
      final paramMsg = fourProto.buildParameterEditMessage(slotIndex: 2, paramIndex: 0, value: 130);
      expect(paramMsg.data, [0xF0, 0x52, 0x00, 0x6E, 0x64, 0x03, 0x00, 0x02, 0x02, 0x02, 0x01, 0x00, 0x00, 0x00, 0xF7]);
      expect(fourProto.isParameterEdit(paramMsg), isTrue);
      expect(fourProto.parseParameterEdit(paramMsg), (slotIndex: 2, paramIndex: 0, value: 130));

      // 3. Effect ID change: F0 52 00 6E 64 03 00 <slot> 01 <fxLsb> <fxMsb> 00 <grpLsb> <grpMsb> F7
      final fxMsg = fourProto.buildEffectTypeMessage(1, 0x04800011); // AMPG SVT
      expect(fxMsg.data, [0xF0, 0x52, 0x00, 0x6E, 0x64, 0x03, 0x00, 0x01, 0x01, 0x11, 0x00, 0x00, 0x00, 0x09, 0xF7]);
    });

    test('PTCF target 0x80 auto-switches generic port to zoomB1xFour and scans 50 patches (0..49)', () async {
      const genericPort = MidiPortDescriptor(
        id: 'usb_midi_1',
        name: 'USB MIDI Device',
        manufacturer: 'Generic',
        isInput: true,
        isOutput: true,
      );
      final transport = MockMidiTransport(initialPorts: [genericPort]);
      const fourProto = ZoomFourProtocol();
      final currentPatch = _buildSampleB1xFourPatch(name: 'SA-Drive', programNumber: null);
      final currentDump = fourProto.encodePatch(currentPatch);

      final requestedSlots = <int>[];
      transport.registerResponder(
        (msg) =>
            msg.data.length >= 7 &&
            msg.data[3] == 0x6E &&
            msg.data[4] == 0x64 &&
            msg.data[5] == 0x13,
        (_) => currentDump,
      );
      transport.registerResponder(
        (msg) => msg.data.length >= 11 && msg.data[3] == 0x6E && msg.data[4] == 0x46,
        (req) {
          final slot = req.data[7] * 10 + req.data[9];
          requestedSlots.add(slot);
          return fourProto.encodePatch(currentPatch, programNumber: slot);
        },
      );

      final controller = DeviceConnectionController(transport: transport);
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      await controller.connect(genericPort, fetchCurrentPatch: true, autoSyncBank: true);
      // Allow background syncDeviceBank to complete
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(controller.activeFamily, DeviceFamily.zoomB1xFour);
      expect(controller.bankSlots.length, 50);
      expect(requestedSlots.length, 50);
      expect(requestedSlots.every((s) => s >= 0 && s < 50), isTrue);
    });

    test('USB port B1X FOUR detection is preserved even on unrecognized 0x6E identity reply', () async {
      const port = MidiPortDescriptor(
        id: 'zoom_b1x_generic',
        name: 'ZOOM B1X FOUR',
        manufacturer: 'ZOOM',
        isInput: true,
        isOutput: true,
      );
      final transport = MockMidiTransport(initialPorts: [port]);
      transport.registerResponder(
        (msg) => msg.data.length >= 6 && msg.data[1] == 0x7E && msg.data[3] == 0x06 && msg.data[4] == 0x01,
        (_) => MidiMessage.sysEx([0x7E, 0x7F, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x7F, 0x00, 0x31, 0x30, 0x30, 0x30]),
      );
      final controller = DeviceConnectionController(transport: transport);
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      await controller.connect(port, fetchCurrentPatch: false, autoSyncBank: false);
      expect(controller.activeFamily, DeviceFamily.zoomB1xFour);
    });
  });

  group('ToneLib .zb1f / .zg1f & External PTCF / SysEx Import & Export', () {
    test('round-trips a B1X FOUR patch through ToneLib .zb1f XML/PTCF export & import', () async {
      final patch = _buildSampleB1xFourPatch(name: 'Fuzz Syn', programNumber: 12);
      final registry = ExportAdapterRegistry.standard();
      final zb1fAdapter = registry.adapterFor(ExportFormat.zoomFourZb1f);

      expect(zb1fAdapter.supportsDevice(DeviceFamily.zoomB1xFour), isTrue);
      expect(zb1fAdapter.supportsDevice(DeviceFamily.zoomB1Four), isTrue);
      expect(zb1fAdapter.supportsDevice(DeviceFamily.zoomMs60bPlus), isFalse);

      final exported = zb1fAdapter.exportPatch(patch);
      expect(exported.fileExtension, '.zb1f');
      expect(exported.suggestedName, endsWith('.zb1f'));
      final xmlText = utf8.decode(exported.bytes);
      expect(xmlText, contains('<ZoomPatch'));
      expect(xmlText, contains('device="Zoom B1X FOUR"'));
      expect(xmlText, contains('generation="zoomFour"'));
      expect(xmlText, contains('<PatchData encoding="base64"'));

      final importer = PatchImporter.standard();
      final importedResult = importer.importBytes(
        exported.bytes,
        sourceName: '22_Fuzz_Syn.zb1f',
      );
      expect(importedResult.hasErrors, isFalse, reason: importedResult.allErrors.join('; '));
      expect(importedResult.importedCount, 1);

      final entry = importedResult.entries.first;
      expect(entry.detectedFormat, ImportFormat.zoomFourZb1f);
      expect(entry.inferredDeviceFamily, DeviceFamily.zoomB1xFour);
      expect(entry.patch.deviceFamily, DeviceFamily.zoomB1xFour);
      expect(entry.patch.generation, DeviceGeneration.zoomFour);
      expect(entry.patch.programNumber, 12); // "22" hardware patch label -> zero-based 12
      expect(entry.patch.name, 'Fuzz Syn');
      expect(entry.patch.slots.length, 5);
      expect(entry.patch.slots[4].effectName, 'PDL Vol');
    });

    test('supports G1X FOUR .zg1f and raw .ptcf / .syx tagged with DeviceGeneration.zoomFour', () {
      final g1xPatch = _buildSampleB1xFourPatch(
        id: 'g1xf_01',
        name: 'Rock Lead',
        family: DeviceFamily.zoomG1xFour,
        programNumber: 0,
      );
      final registry = ExportAdapterRegistry.standard();
      final importer = PatchImporter.standard();

      // .zg1f round-trip
      final zg1fPayload = registry.adapterFor(ExportFormat.zoomFourZb1f).exportPatch(g1xPatch);
      expect(zg1fPayload.fileExtension, '.zg1f');
      final zg1fImport = importer.importBytes(zg1fPayload.bytes, sourceName: zg1fPayload.suggestedName);
      expect(zg1fImport.importedCount, 1);
      expect(zg1fImport.entries.first.patch.deviceFamily, DeviceFamily.zoomG1xFour);
      expect(zg1fImport.entries.first.patch.generation, DeviceGeneration.zoomFour);

      // Raw .ptcf round-trip tagged zoomFour
      final ptcfPayload = registry.adapterFor(ExportFormat.zoomPtcf).exportPatch(
            g1xPatch.copyWith(deviceFamily: DeviceFamily.zoomB1Four),
          );
      final ptcfImport = importer.importBytes(ptcfPayload.bytes, sourceName: '10_Test.ptcf');
      expect(ptcfImport.importedCount, 1);
      expect(ptcfImport.entries.first.inferredDeviceFamily, DeviceFamily.zoomB1Four);
      expect(ptcfImport.entries.first.patch.generation, DeviceGeneration.zoomFour);

      // Raw .syx round-trip tagged zoomFour
      final syxPayload = registry.adapterFor(ExportFormat.rawSysEx).exportPatch(
            _buildSampleB1xFourPatch(family: DeviceFamily.zoomB1xFour),
          );
      final syxImport = importer.importBytes(Uint8List.fromList(syxPayload.bytes), sourceName: syxPayload.suggestedName);
      expect(syxImport.importedCount, 1);
      expect(syxImport.entries.first.inferredDeviceFamily, DeviceFamily.zoomB1xFour);
      expect(syxImport.entries.first.patch.generation, DeviceGeneration.zoomFour);
    });
  });

  group('Cross-Generation Write Protection', () {
    test('blocks writes between zoomFour and zoomMsPlus while permitting B1 FOUR <-> B1X FOUR', () async {
      expect(DeviceFamily.zoomB1xFour.isSameGeneration(DeviceFamily.zoomMs60bPlus), isFalse);
      expect(DeviceFamily.zoomMs60bPlus.isSameGeneration(DeviceFamily.zoomB1Four), isFalse);
      expect(DeviceFamily.zoomB1Four.isSameGeneration(DeviceFamily.zoomB1xFour), isTrue);
      expect(DeviceFamily.zoomG1xFour.isSameGeneration(DeviceFamily.zoomB1xFour), isTrue);

      const msPort = MidiPortDescriptor(
        id: 'ms60b_1',
        name: 'ZOOM MS-60B+',
        isInput: true,
        isOutput: true,
      );
      const b1xPort = MidiPortDescriptor(
        id: 'b1xf_1',
        name: 'ZOOM B1X FOUR',
        isInput: true,
        isOutput: true,
      );

      final transport = MockMidiTransport(initialPorts: [msPort, b1xPort]);
      final connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: _buildSampleB1xFourPatch(family: DeviceFamily.zoomB1xFour),
      );
      addTearDown(() async {
        editor.dispose();
        connection.dispose();
        await transport.dispose();
      });

      // 1. Attempt writing B1X FOUR (zoomFour) patch onto connected MS-60B+ (zoomMsPlus) -> blocked
      await connection.connect(msPort, explicitFamily: DeviceFamily.zoomMs60bPlus, fetchCurrentPatch: false);
      transport.clearSentMessages();
      await editor.savePatchToDeviceSlot(0);
      expect(editor.errorMessage, isNotNull);
      expect(editor.errorMessage, contains('incompatible hardware generation'));
      expect(
        transport.sentMessages.where((m) => const ZoomMsPlusProtocol().isSlotPatchDump(m)),
        isEmpty,
      );

      // 2. Write B1 FOUR patch onto connected B1X FOUR (same DeviceGeneration.zoomFour) -> permitted
      await connection.connect(b1xPort, explicitFamily: DeviceFamily.zoomB1xFour, fetchCurrentPatch: false);
      transport.clearSentMessages();
      final b1FourPatch = _buildSampleB1xFourPatch(
        id: 'b1f_patch',
        name: 'B1 Four Cl',
        family: DeviceFamily.zoomB1Four,
        slotCount: 4,
      );
      await editor.savePatchToDeviceSlot(5, b1FourPatch);
      expect(editor.errorMessage, isNull);
      final dumps = transport.sentMessages
          .where((m) => const ZoomFourProtocol().isSlotPatchDump(m))
          .toList();
      expect(dumps.length, 1);
      expect(const ZoomFourProtocol().extractSlotIndex(dumps.first), 5);
    });

    testWidgets('WriteToSlotDialog hard-blocks B1X FOUR preset write on connected MS-60B+', (tester) async {
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      final b1xPatch = _buildSampleB1xFourPatch(family: DeviceFamily.zoomB1xFour);
      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: b1xPatch,
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
      await tester.pumpAndSettle();

      expect(find.textContaining('Incompatible hardware generation'), findsOneWidget);
      final writeButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirm_write_slot_button')),
      );
      expect(writeButton.onPressed, isNull);

      editor.dispose();
      connection.dispose();
      await transport.dispose();
    });
  });
}
