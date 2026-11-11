import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/composite_midi_transport.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';

void main() {
  group('CompositeMidiTransport Unit Tests', () {
    late MockMidiTransport child1;
    late MockMidiTransport child2;
    late CompositeMidiTransport composite;

    setUp(() {
      child1 = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'hw:1,0,0',
            name: 'ZOOM MS-60B+ (Hardware)',
            manufacturer: 'Zoom Corporation',
            isInput: true,
            isOutput: true,
          ),
        ],
      );

      child2 = MockMidiTransport(
        initialPorts: const [
          MidiPortDescriptor(
            id: 'sim_line6',
            name: 'Line 6 Bass Pod Pro (Simulated)',
            manufacturer: 'Line 6',
            isInput: true,
            isOutput: true,
          ),
        ],
      );

      composite = CompositeMidiTransport(transports: [child1, child2]);
    });

    tearDown(() async {
      await composite.dispose();
    });

    test('getAvailablePorts aggregates ports across all child transports', () async {
      final ports = await composite.getAvailablePorts();

      expect(ports.length, 2);
      expect(ports[0].id, 'hw:1,0,0');
      expect(ports[0].name, 'ZOOM MS-60B+ (Hardware)');
      expect(ports[1].id, 'sim_line6');
      expect(ports[1].name, 'Line 6 Bass Pod Pro (Simulated)');
    });

    test('connect routes connection to whichever child transport owns the port', () async {
      expect(composite.isConnected, isFalse);
      expect(composite.activeTransport, isNull);

      // Connect to port owned by child1
      await composite.connect('hw:1,0,0');
      expect(composite.isConnected, isTrue);
      expect(composite.activeTransport, child1);
      expect(child1.isConnected, isTrue);
      expect(child2.isConnected, isFalse);

      // Connect to port owned by child2: should disconnect child1 and connect child2
      await composite.connect('sim_line6');
      expect(composite.isConnected, isTrue);
      expect(composite.activeTransport, child2);
      expect(child1.isConnected, isFalse);
      expect(child2.isConnected, isTrue);
    });

    test('connect throws ArgumentError when portId is not found anywhere', () async {
      expect(
        () => composite.connect('unknown_port_999'),
        throwsArgumentError,
      );
    });

    test('send forwards messages to the currently active child transport', () async {
      await composite.connect('hw:1,0,0');

      final msg = MidiMessage.sysEx([0x52, 0x00, 0x6E]);
      await composite.send(msg);

      expect(child1.sentMessages.length, 1);
      expect(child1.sentMessages.first, msg);
      expect(child2.sentMessages, isEmpty);
    });

    test('send throws StateError when composite transport is not connected', () async {
      expect(
        () => composite.send(MidiMessage.sysEx([0x00])),
        throwsStateError,
      );
    });

    test('onMessageReceived forwards incoming messages from active child transport', () async {
      final received = <MidiMessage>[];
      final sub = composite.onMessageReceived.listen(received.add);

      await composite.connect('sim_line6');

      final testMsg = MidiMessage.controlChange(channel: 0, controller: 14, value: 64);
      child2.simulateIncomingMessage(testMsg);

      await Future<void>.delayed(Duration.zero);

      expect(received.length, 1);
      expect(received.first.data, Uint8List.fromList([0xB0, 0x0E, 0x40]));

      await sub.cancel();
    });

    test('disconnect cleanly disconnects the active child transport', () async {
      await composite.connect('hw:1,0,0');
      expect(composite.isConnected, isTrue);

      await composite.disconnect();
      expect(composite.isConnected, isFalse);
      expect(child1.isConnected, isFalse);
      expect(composite.activeTransport, isNull);
    });

    test('dispose disconnects active transport and disposes all child transports', () async {
      await composite.connect('hw:1,0,0');
      await composite.dispose();

      expect(composite.isConnected, isFalse);
      expect(child1.isConnected, isFalse);
    });
  });
}

