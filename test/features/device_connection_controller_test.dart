import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/zoom_ms_plus_protocol.dart';

void main() {
  group('DeviceConnectionController Handshake, Pacing & Retry Tests', () {
    const proto = ZoomMsPlusProtocol();
    final testPatch = Patch(
      id: 'test_patch',
      name: 'Paced Preset',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      slots: [],
    );

    late MockMidiTransport transport;
    late MidiPortDescriptor testPort;

    setUp(() {
      testPort = const MidiPortDescriptor(
        id: 'port_zoom',
        name: 'ZOOM MS-60B+',
        manufacturer: 'Zoom Corporation',
        isInput: true,
        isOutput: true,
      );
      transport = MockMidiTransport(initialPorts: [testPort]);
    });

    test('connect sends init sequence with pacing and fetches current patch with retry on timeout', () async {
      int currentPatchRequestsCount = 0;

      // Register responder for 64 13 that times out on attempt 1, responds on attempt 2 (retry)
      transport.registerResponder(
        (msg) =>
            msg.isSysEx &&
            msg.data.length >= 6 &&
            msg.data[1] == 0x52 &&
            msg.data[4] == 0x64 &&
            msg.data[5] == 0x13,
        (msg) {
          currentPatchRequestsCount++;
          if (currentPatchRequestsCount == 1) {
            // First attempt: simulate timeout by emitting an unrelated message
            return MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x00]);
          }
          // Second attempt (retry): respond with current patch dump
          return proto.buildSavePatchToSlotMessage(testPatch, 0);
        },
      );

      final controller = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
        currentPatchTimeoutOverride: const Duration(milliseconds: 30),
      );

      await controller.connect(
        testPort,
        explicitFamily: DeviceFamily.zoomMs60bPlus,
        fetchCurrentPatch: true,
        autoSyncBank: false,
      );

      expect(controller.isConnected, isTrue);
      // Verify that retry occurred (2 requests total)
      expect(currentPatchRequestsCount, 2);

      // Verify command ordering: 0x53, 0x50, 0x33, followed by 64 13
      final sentOpcodes = transport.sentMessages
          .where((m) => m.isSysEx && m.data.length >= 5 && m.data[1] == 0x52)
          .map((m) => m.data[4])
          .toList();

      expect(sentOpcodes, containsAllInOrder([0x53, 0x50, 0x33, 0x64]));
      controller.dispose();
    });

    test('syncDeviceBank retries timed-out slot requests once before falling back to empty slot', () async {
      final slot1RequestCounts = <int, int>{};

      // Auto-responder for slot dumps (0x46)
      transport.registerResponder(
        (msg) =>
            msg.isSysEx &&
            msg.data.length >= 11 &&
            msg.data[1] == 0x52 &&
            msg.data[4] == 0x46,
        (msg) {
          final bank = msg.data[7] | (msg.data[8] << 7);
          final prog = msg.data[9] | (msg.data[10] << 7);
          final slotIndex = (bank * 10) + prog;

          slot1RequestCounts[slotIndex] = (slot1RequestCounts[slotIndex] ?? 0) + 1;

          if (slotIndex == 0) {
            // Slot 0: responds immediately on first attempt
            return proto.buildSavePatchToSlotMessage(
              testPatch.copyWith(name: 'Slot Zero', programNumber: 0),
              0,
            );
          } else if (slotIndex == 1) {
            // Slot 1: fails on attempt 1, responds on attempt 2 (retry)
            if (slot1RequestCounts[slotIndex] == 1) {
              return MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x00]); // irrelevant reply causes timeout
            }
            return proto.buildSavePatchToSlotMessage(
              testPatch.copyWith(name: 'Recovered Slot 1', programNumber: 1),
              1,
            );
          } else {
            // Slot 2: fails on both attempt 1 and attempt 2 (causes empty slot fallback)
            return MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x00]);
          }
        },
      );

      final controller = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
      );

      await controller.connect(
        testPort,
        explicitFamily: DeviceFamily.zoomMs60bPlus,
        fetchCurrentPatch: false,
        autoSyncBank: false,
      );

      // Sync first 3 slots with short timeout
      await controller.syncDeviceBank(
        slotCount: 3,
        perSlotTimeout: const Duration(milliseconds: 30),
      );

      // Verify the first 3 slots were synced
      expect(controller.bankSlots.length, 100);

      // Slot 0 succeeded on first try
      expect(controller.bankSlots[0].isLoaded, isTrue);
      expect(controller.bankSlots[0].isEmpty, isFalse);
      expect(controller.bankSlots[0].name, 'Slot Zero');
      expect(slot1RequestCounts[0], 1);

      // Slot 1 recovered on retry
      expect(controller.bankSlots[1].isLoaded, isTrue);
      expect(controller.bankSlots[1].isEmpty, isFalse);
      expect(controller.bankSlots[1].name, 'Recovered Slot 1');
      expect(slot1RequestCounts[1], 2);

      // Slot 2 failed on both attempts, fell back to empty slot descriptor
      expect(controller.bankSlots[2].isLoaded, isTrue);
      expect(controller.bankSlots[2].isEmpty, isTrue);
      expect(controller.bankSlots[2].name, 'Slot 02');
      expect(slot1RequestCounts[2], 2);

      // Slot 3 remained unsynced
      expect(controller.bankSlots[3].isLoaded, isFalse);

      controller.dispose();
    });

    test('syncDeviceBank is only launched after current patch request finishes', () async {
      final executionOrder = <String>[];

      transport.registerResponder(
        (msg) =>
            msg.isSysEx &&
            msg.data.length >= 6 &&
            msg.data[1] == 0x52 &&
            msg.data[4] == 0x64 &&
            msg.data[5] == 0x13,
        (msg) {
          executionOrder.add('currentPatchRequest');
          return proto.buildSavePatchToSlotMessage(testPatch, 0);
        },
      );

      transport.registerResponder(
        (msg) =>
            msg.isSysEx &&
            msg.data.length >= 11 &&
            msg.data[1] == 0x52 &&
            msg.data[4] == 0x46,
        (msg) {
          executionOrder.add('slotBankRequest');
          return proto.buildSavePatchToSlotMessage(testPatch, 0);
        },
      );

      final controller = DeviceConnectionController(
        transport: transport,
        defaultFamily: DeviceFamily.zoomMs60bPlus,
        currentPatchTimeoutOverride: const Duration(milliseconds: 30),
      );

      await controller.connect(
        testPort,
        explicitFamily: DeviceFamily.zoomMs60bPlus,
        fetchCurrentPatch: true,
        autoSyncBank: true,
      );

      // Await brief microtask to let autoSyncBank start
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(executionOrder.isNotEmpty, isTrue);
      expect(executionOrder.first, 'currentPatchRequest');

      controller.dispose();
    });
  });
}
