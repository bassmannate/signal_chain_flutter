import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/export/export_adapter_registry.dart';
import 'package:signal_chain_flutter/core/export/export_format.dart';
import 'package:signal_chain_flutter/core/import/import_file_system.dart';
import 'package:signal_chain_flutter/core/import/import_format.dart';
import 'package:signal_chain_flutter/core/import/patch_importer.dart';
import 'package:signal_chain_flutter/core/storage/in_memory_patch_library_repository.dart';
import 'package:signal_chain_flutter/features/library/patch_library_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/parameter_descriptor.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/line6_bass_pod_pro_protocol.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.ensureInitialized();
  });

  final exportRegistry = ExportAdapterRegistry.standard();
  final importer = PatchImporter.standard();

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
    metadata: {'tempo': 132},
  );

  const line6Patch = Patch(
    id: 'line6_test_1',
    name: 'Classic SVT',
    deviceFamily: DeviceFamily.line6BassPodPro,
    programNumber: 4,
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

  group('NativeJsonImportAdapter', () {
    test('round-trips single patch JSON losslessly', () {
      final payload =
          exportRegistry.adapterFor(ExportFormat.nativeJson).exportPatch(zoomPatch);

      final result = importer.importBytes(
        payload.bytes,
        sourceName: payload.suggestedName,
      );

      expect(result.hasErrors, isFalse);
      expect(result.importedCount, equals(1));
      expect(result.entries.single.detectedFormat, equals(ImportFormat.signalChainJson));
      expect(result.entries.single.inferredDeviceFamily, equals(DeviceFamily.zoomMs60bPlus));
      expect(result.entries.single.patch, equals(zoomPatch));
    });

    test('round-trips multi-patch library bundle JSON', () {
      final payload = exportRegistry
          .adapterFor(ExportFormat.nativeJson)
          .exportLibrary([zoomPatch, line6Patch], libraryName: 'Mixed Bank');

      final result = importer.importBytes(
        payload.bytes,
        sourceName: payload.suggestedName,
      );

      expect(result.hasErrors, isFalse);
      expect(result.importedCount, equals(2));
      expect(result.entries[0].patch, equals(zoomPatch));
      expect(result.entries[1].patch, equals(line6Patch));
    });

    test('handles newer schemaVersion warning and partial malformed bundle entries', () {
      final bundle = json.encode({
        'format': 'signal_chain_library',
        'schemaVersion': 99,
        'patches': [
          zoomPatch.toJson(),
          {'invalid': 'entry'},
        ],
      });

      final result = importer.importText(bundle);
      expect(result.importedCount, equals(1));
      expect(result.errorCount, equals(1));
      expect(result.hasWarnings, isTrue);
      expect(result.allWarnings.first, contains('schemaVersion (99)'));
    });

    test('reports error diagnostic on malformed JSON without throwing', () {
      final result = importer.importText('{ not valid json');
      expect(result.importedCount, equals(0));
      expect(result.hasErrors, isTrue);
      expect(result.allErrors.single, contains('Malformed JSON'));
    });
  });

  group('ZoomPtcfImportAdapter & ZoomMultistompStudioImportAdapter', () {
    test('round-trips 848-byte Zoom PTCF and MultiStomp Studio .zptc files', () {
      for (final format in [ExportFormat.zoomPtcf, ExportFormat.zoomMultistompStudio]) {
        final payload = exportRegistry.adapterFor(format).exportPatch(zoomPatch);
        final fileName = format == ExportFormat.zoomMultistompStudio
            ? 'multistomp_Slap_Funk.zptc'
            : payload.suggestedName;

        final result = importer.importBytes(payload.bytes, sourceName: fileName);
        expect(result.hasErrors, isFalse);
        expect(result.importedCount, equals(1));

        final entry = result.entries.single;
        expect(
          entry.detectedFormat,
          equals(
            format == ExportFormat.zoomMultistompStudio
                ? ImportFormat.zoomMultiStompStudio
                : ImportFormat.zoomPtcf,
          ),
        );
        expect(entry.patch.name, equals('Slap Funk'));
        expect(entry.patch.deviceFamily, equals(DeviceFamily.zoomMs60bPlus));
        expect(entry.patch.tempo, equals(132));
        expect(entry.patch.slots.first.effectId, equals('0x01000010'));
        expect(entry.patch.slots.first.parameters.first.currentValue, equals(7.0));
      }
    });

    test('handles truncated/corrupted PTCF gracefully', () {
      final badBytes = Uint8List.fromList([0x50, 0x54, 0x43, 0x46, 0x01, 0x00]);
      final result = importer.importBytes(badBytes, sourceName: 'broken.zptc');
      expect(result.importedCount, equals(0));
      expect(result.hasErrors, isTrue);
    });
  });

  group('SymbiosisImportAdapter & Batch Folder Import', () {
    test('infers exact Zoom MS Plus model from all 4 Symbiosis suffixes', () {
      final cases = <DeviceFamily, String>{
        DeviceFamily.zoomMs60bPlus: '.60bp.zptc',
        DeviceFamily.zoomMs50gPlus: '.50gp.zptc',
        DeviceFamily.zoomMs70cdrPlus: '.70cdrp.zptc',
        DeviceFamily.zoomMs200dPlus: '.200dp.zptc',
      };

      for (final entry in cases.entries) {
        final patch = zoomPatch.copyWith(deviceFamily: entry.key);
        final payload =
            exportRegistry.adapterFor(ExportFormat.symbiosisZptc).exportPatch(patch);
        expect(payload.suggestedName, endsWith(entry.value));

        final result = importer.importBytes(
          payload.bytes,
          sourceName: payload.suggestedName,
        );
        expect(result.hasErrors, isFalse);
        expect(result.importedCount, equals(1));
        expect(result.entries.single.detectedFormat, equals(ImportFormat.symbiosisPtcf));
        expect(result.entries.single.inferredDeviceFamily, equals(entry.key));
        expect(result.entries.single.patch.deviceFamily, equals(entry.key));
      }
    });

    test('round-trips Symbiosis batch folder via InMemoryImportFileSystem', () async {
      final symPayload = exportRegistry
          .adapterFor(ExportFormat.symbiosisZptc)
          .exportLibrary(
            [
              zoomPatch,
              zoomPatch.copyWith(
                name: 'Ambient 70',
                deviceFamily: DeviceFamily.zoomMs70cdrPlus,
                programNumber: 12,
              ),
            ],
            libraryName: 'SymbiosisBackup',
          );

      final fs = InMemoryImportFileSystem();
      const folderPath = '/memory/Documents/SignalChainExports/SymbiosisBackup';
      for (final fileEntry in symPayload.folderEntries) {
        fs.addFile('$folderPath/${fileEntry.fileName}', fileEntry.bytes);
      }
      // Add an unrelated text file (should be skipped) and a corrupted .zptc (should error)
      fs.addFile('$folderPath/README.txt', Uint8List.fromList(utf8.encode('notes')));
      fs.addFile('$folderPath/99_corrupt.60bp.zptc', Uint8List.fromList([1, 2, 3, 4]));

      final result = await importer.importDirectory(
        folderPath,
        fileSystem: fs,
        activeDeviceFamily: DeviceFamily.zoomMs60bPlus,
      );

      expect(result.importedCount, equals(2));
      expect(result.skippedCount, equals(1));
      expect(result.errorCount, equals(1));
      expect(result.entries[0].patch.programNumber, equals(3));
      expect(result.entries[0].inferredDeviceFamily, equals(DeviceFamily.zoomMs60bPlus));
      expect(result.entries[1].patch.programNumber, equals(12));
      expect(result.entries[1].inferredDeviceFamily, equals(DeviceFamily.zoomMs70cdrPlus));
      expect(result.entries[1].isDeviceMismatch(DeviceFamily.zoomMs60bPlus), isTrue);
    });
  });

  group('RawSysExImportAdapter', () {
    test('round-trips Zoom 0x45 989-byte and Line 6 0x02 170-byte .syx files', () {
      final rawAdapter = exportRegistry.adapterFor(ExportFormat.rawSysEx);

      final zoomPayload = rawAdapter.exportPatch(zoomPatch);
      expect(zoomPayload.bytes.length, equals(989));
      final zoomRes = importer.importBytes(
        zoomPayload.bytes,
        sourceName: zoomPayload.suggestedName,
      );
      expect(zoomRes.hasErrors, isFalse);
      expect(zoomRes.importedCount, equals(1));
      expect(zoomRes.entries.single.detectedFormat, equals(ImportFormat.rawSysEx));
      expect(zoomRes.entries.single.patch.name, equals('Slap Funk'));
      expect(zoomRes.entries.single.patch.programNumber, equals(3));

      final line6Payload = rawAdapter.exportPatch(line6Patch);
      expect(line6Payload.bytes.length, equals(170));
      final line6Res = importer.importBytes(
        line6Payload.bytes,
        sourceName: line6Payload.suggestedName,
      );
      expect(line6Res.hasErrors, isFalse);
      expect(line6Res.importedCount, equals(1));
      expect(line6Res.entries.single.inferredDeviceFamily, equals(DeviceFamily.line6BassPodPro));
      expect(line6Res.entries.single.patch.name, equals('Classic SVT'));
      expect(line6Res.entries.single.patch.programNumber, equals(4));
    });

    test('decodes Zoom 64 12 01 and Line 6 169-byte edit buffer dumps', () {
      final zoomEdit = const ZoomMsPlusProtocol().encodePatch(zoomPatch).data;
      final line6Edit = const Line6BassPodProProtocol().encodePatch(line6Patch).data;

      final combined = Uint8List.fromList([...zoomEdit, ...line6Edit]);
      final result = importer.importBytes(combined, sourceName: 'multi_dump.syx');

      expect(result.hasErrors, isFalse);
      expect(result.importedCount, equals(2));
      expect(result.entries[0].patch.name, equals('Slap Funk'));
      expect(result.entries[1].patch.name, equals('Classic SVT'));
    });

    test('handles truncated SysEx frames and CRC mismatch gracefully', () {
      final validZoom =
          exportRegistry.adapterFor(ExportFormat.rawSysEx).exportPatch(zoomPatch).bytes;
      // Corrupt one CRC byte before F7
      final badCrc = Uint8List.fromList(validZoom);
      badCrc[badCrc.length - 2] ^= 0x01;
      // Append a truncated frame without F7
      final combined = Uint8List.fromList([...badCrc, 0xF0, 0x52, 0x00, 0x6E]);

      final result = importer.importBytes(combined, sourceName: 'partial.syx');
      expect(result.importedCount, equals(1));
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
      expect(result.allWarnings.first, contains('CRC mismatch'));
      expect(result.allErrors.first, contains('missing terminating 0xF7'));
    });
  });

  group('PatchLibraryController.importEntries ID collision safety', () {
    test('assigns unique IDs when importing multiple .zptc patches', () async {
      final repo = InMemoryPatchLibraryRepository();
      final controller = PatchLibraryController(repository: repo);

      final bytes1 = exportRegistry
          .adapterFor(ExportFormat.zoomPtcf)
          .exportPatch(zoomPatch.copyWith(name: 'Tone A', programNumber: null))
          .bytes;
      final bytes2 = exportRegistry
          .adapterFor(ExportFormat.zoomPtcf)
          .exportPatch(zoomPatch.copyWith(name: 'Tone B', programNumber: null))
          .bytes;

      final res1 = importer.importBytes(bytes1, sourceName: 'Tone_A.zptc');
      final res2 = importer.importBytes(bytes2, sourceName: 'Tone_B.zptc');

      await controller.importEntries([...res1.entries, ...res2.entries]);

      expect(controller.patches.length, equals(2));
      expect(controller.patches[0].id, isNot(equals(controller.patches[1].id)));
      expect(controller.patches.map((p) => p.name), containsAll(['Tone A', 'Tone B']));
    });
  });
}

