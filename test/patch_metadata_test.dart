import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  group('PatchEditorController - Patch Metadata Controls', () {
    late MockMidiTransport transport;
    late DeviceConnectionController connectionController;
    late PatchEditorController editorController;

    const initialPatch = Patch(
      id: 'test_patch',
      name: 'InitPatch',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      slots: [
        EffectSlot(
          slotIndex: 0,
          effectId: '0x01000010',
          effectName: 'DYN Comp',
          isEnabled: true,
          parameters: [],
        ),
      ],
      metadata: {'tempo': 120},
    );

    setUp(() {
      transport = MockMidiTransport();
      connectionController = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );
      editorController = PatchEditorController(
        transport: transport,
        connectionController: connectionController,
        initialPatch: initialPatch,
      );
    });

    test('updatePatchName enforces device character limit (10 chars for Zoom MS-60B+)', () {
      expect(editorController.isDirty, isFalse);

      // Name longer than 10 characters should be truncated to 10
      editorController.updatePatchName('SuperLongPresetName123');
      expect(editorController.patch?.name, equals('SuperLongP'));
      expect(editorController.patch?.name.length, equals(10));
      expect(editorController.isDirty, isTrue);

      // Short name remains within limit
      editorController.updatePatchName('Slap');
      expect(editorController.patch?.name, equals('Slap'));
    });

    test('updatePatchName translates unprintable and invalid chars to spaces', () {
      // Input with tab, newline, and non-ASCII character
      editorController.updatePatchName('Hi\t\nYo\x00Bass');
      // 'H', 'i', ' ', ' ', 'Y', 'o', ' ', 'B', 'a', 's' (10 chars)
      expect(editorController.patch?.name, equals('Hi  Yo Bas'));
    });

    test('updatePatchName respects Line 6 16-character limit when connected to Line 6', () {
      connectionController.selectDeviceFamily(DeviceFamily.line6BassPodPro);
      expect(connectionController.activeFamily.maxNameLength, equals(16));

      editorController.updatePatchName('BassPodProSVT1976Special');
      expect(editorController.patch?.name, equals('BassPodProSVT197'));
      expect(editorController.patch?.name.length, equals(16));
    });

    test('updatePatchTempo clamps BPM to 40..250 and marks patch dirty', () {
      expect(editorController.patch?.tempo, equals(120));
      expect(editorController.isDirty, isFalse);

      // Test lower bound clamping (< 40)
      editorController.updatePatchTempo(25);
      expect(editorController.patch?.tempo, equals(40));
      expect(editorController.patch?.metadata['tempo'], equals(40));
      expect(editorController.isDirty, isTrue);

      // Test upper bound clamping (> 250)
      editorController.updatePatchTempo(320);
      expect(editorController.patch?.tempo, equals(250));
      expect(editorController.patch?.metadata['tempo'], equals(250));

      // Test normal tempo in valid range
      editorController.updatePatchTempo(144);
      expect(editorController.patch?.tempo, equals(144));
      expect(editorController.patch?.metadata['tempo'], equals(144));
    });

    test('Tempo is preserved through Zoom SysEx encoding and decoding', () {
      const proto = ZoomMsPlusProtocol();
      editorController.updatePatchTempo(165);

      final current = editorController.patch!;
      final encoded = proto.encodePatch(current);
      final decoded = proto.decodePatch(encoded);

      expect(decoded.tempo, equals(165));
      expect(decoded.name, equals(current.name));
    });
  });
}

