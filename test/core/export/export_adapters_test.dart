import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_file_writer.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/line6_bass_pod_pro_protocol.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  final registry = ExportAdapterRegistry.standard();

  const zoomPatch = Patch(
    id: 'zoom_test_1',
    name: 'Slap Funk',
    deviceFamily: DeviceFamily.zoomMs60bPlus,
    programNumber: 3,
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
            currentValue: 7.0,
          ),
        ],
      ),
    ],
    metadata: {'tempo': 118},
  );

  const line6Patch = Patch(
    id: 'line6_test_1',
    name: 'Classic SVT',
    deviceFamily: DeviceFamily.line6BassPodPro,
    programNumber: 1,
    slots: [
      EffectSlot(
        slotIndex: 0,
        effectId: 'line6_amp_8',
        effectName: 'Rock Classic',
        isEnabled: true,
        parameters: [
          ParameterValue(
            descriptor: ParameterDescriptor(
              id: 'amp_model',
              name: 'Amp Model',
              min: 0,
              max: 15,
              defaultValue: 8,
            ),
            currentValue: 8.0,
          ),
        ],
      ),
    ],
  );

  group('ExportAdapterRegistry & Device Filtering', () {
    test('exposes all 5 formats for Zoom MS Plus devices', () {
      final adapters = registry.adaptersForDevice(DeviceFamily.zoomMs60bPlus);
      expect(adapters.map((a) => a.format), containsAll(ExportFormat.values));
    });

    test('filters out Zoom-only formats for Line 6 Bass POD Pro', () {
      final adapters = registry.adaptersForDevice(DeviceFamily.line6BassPodPro);
      expect(
        adapters.map((a) => a.format).toList(),
        equals([ExportFormat.nativeJson, ExportFormat.rawSysEx]),
      );
    });
  });

  group('NativeJsonExportAdapter', () {
    final adapter = registry.adapterFor(ExportFormat.nativeJson);

    test('round-trips single patch losslessly', () {
      final payload = adapter.exportPatch(zoomPatch);
      expect(payload.isBinary, isFalse);
      expect(payload.suggestedName, equals('Slap_Funk.json'));

      final decoded = Patch.fromJson(json.decode(utf8.decode(payload.bytes)) as Map<String, dynamic>);
      expect(decoded, equals(zoomPatch));
    });

    test('exports mixed-device library bundle', () {
      final payload = adapter.exportLibrary([zoomPatch, line6Patch], libraryName: 'My Bank');
      expect(payload.exportedPatchCount, equals(2));
      expect(payload.skippedPatchCount, equals(0));
      expect(payload.suggestedName, equals('My_Bank.json'));

      final decoded = json.decode(utf8.decode(payload.bytes)) as Map<String, dynamic>;
      expect(decoded['format'], equals('signal_chain_library'));
      expect(decoded['patchCount'], equals(2));
      expect((decoded['patches'] as List).length, equals(2));
    });
  });

  group('ZoomPtcfExportAdapter & ZoomMultistompStudioExportAdapter', () {
    test('encodes 848-byte PTCF binary that decodes cleanly', () {
      for (final format in [ExportFormat.zoomPtcf, ExportFormat.zoomMultistompStudio]) {
        final adapter = registry.adapterFor(format);
        final payload = adapter.exportPatch(zoomPatch);
        expect(payload.isBinary, isTrue);
        expect(payload.bytes.length, equals(ZoomMsPlusProtocol.msPlusPtcfSlotLength));
        expect(ascii.decode(payload.bytes.sublist(0, 4)), equals('PTCF'));
        expect(payload.suggestedName, equals('Slap_Funk.zptc'));

        final decoded = const ZoomMsPlusProtocol().decodePtcf(payload.bytes);
        expect(decoded.name, equals('Slap Funk'));
        expect(decoded.slots.first.effectId, equals('0x01000010'));
      }
    });

    test('throws UnsupportedError for single Line 6 patch', () {
      final adapter = registry.adapterFor(ExportFormat.zoomPtcf);
      expect(() => adapter.exportPatch(line6Patch), throwsUnsupportedError);
    });
  });

  group('SymbiosisExportAdapter', () {
    final adapter = registry.adapterFor(ExportFormat.symbiosisZptc);

    test('uses model-suffixed .zptc filenames for all Zoom MS Plus models', () {
      expect(
        adapter.exportPatch(zoomPatch).suggestedName,
        equals('Slap_Funk.60bp.zptc'),
      );
      expect(
        adapter.exportPatch(zoomPatch.copyWith(deviceFamily: DeviceFamily.zoomMs50gPlus)).suggestedName,
        equals('Slap_Funk.50gp.zptc'),
      );
      expect(
        adapter.exportPatch(zoomPatch.copyWith(deviceFamily: DeviceFamily.zoomMs70cdrPlus)).suggestedName,
        equals('Slap_Funk.70cdrp.zptc'),
      );
      expect(
        adapter.exportPatch(zoomPatch.copyWith(deviceFamily: DeviceFamily.zoomMs200dPlus)).suggestedName,
        equals('Slap_Funk.200dp.zptc'),
      );
    });

    test('exports mixed library as folder of .zptc files and skips non-Zoom patches with warning', () {
      final payload = adapter.exportLibrary([zoomPatch, line6Patch], libraryName: 'Symbiosis Backup');
      expect(payload.isDirectoryExport, isTrue);
      expect(payload.exportedPatchCount, equals(1));
      expect(payload.skippedPatchCount, equals(1));
      expect(payload.warnings.single, contains('Skipped 1 non-Zoom patch'));
      expect(payload.folderEntries.length, equals(1));
      expect(payload.folderEntries.single.fileName, equals('03_Slap_Funk.60bp.zptc'));
      expect(payload.folderEntries.single.bytes.length, equals(848));
    });
  });

  group('RawSysExExportAdapter', () {
    final adapter = registry.adapterFor(ExportFormat.rawSysEx);

    test('exports Zoom 989-byte 0x45 SysEx and Line 6 170-byte 0x02 SysEx', () {
      final zoomPayload = adapter.exportPatch(zoomPatch);
      expect(zoomPayload.bytes.length, equals(989));
      expect(zoomPayload.bytes.first, equals(0xF0));
      expect(zoomPayload.bytes.last, equals(0xF7));
      final decodedZoom = const ZoomMsPlusProtocol().decodePatch(
        MidiMessage(zoomPayload.bytes, timestamp: DateTime.now()),
      );
      expect(decodedZoom.name, equals('Slap Funk'));

      final line6Payload = adapter.exportPatch(line6Patch);
      expect(line6Payload.bytes.length, equals(170));
      expect(line6Payload.bytes.first, equals(0xF0));
      expect(line6Payload.bytes.last, equals(0xF7));
      final decodedLine6 = const Line6BassPodProProtocol().decodePatch(
        MidiMessage(line6Payload.bytes, timestamp: DateTime.now()),
      );
      expect(decodedLine6.name, equals('Classic SVT'));
    });
  });

  group('ExportFileWriter', () {
    test('writes single file and directory exports to disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('signal_chain_export_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      const writer = ExportFileWriter();

      final jsonPayload = registry.adapterFor(ExportFormat.nativeJson).exportPatch(zoomPatch);
      final filePath = await writer.writePayload(jsonPayload, targetDir: tempDir);
      expect(File(filePath).existsSync(), isTrue);

      final symPayload = registry.adapterFor(ExportFormat.symbiosisZptc).exportLibrary([zoomPatch]);
      final dirPath = await writer.writePayload(symPayload, targetDir: tempDir);
      expect(Directory(dirPath).existsSync(), isTrue);
      expect(File('$dirPath${Platform.pathSeparator}03_Slap_Funk.60bp.zptc').existsSync(), isTrue);
    });
  });
}

