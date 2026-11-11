import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';

void main() {
  group('MidiPortDescriptor', () {
    test('instantiates with properties and supports value equality', () {
      const port1 = MidiPortDescriptor(
        id: 'port_1',
        name: 'Zoom MS-60B+',
        manufacturer: 'Zoom Corporation',
        isInput: true,
        isOutput: true,
      );

      const port2 = MidiPortDescriptor(
        id: 'port_1',
        name: 'Zoom MS-60B+',
        manufacturer: 'Zoom Corporation',
        isInput: true,
        isOutput: true,
      );

      const port3 = MidiPortDescriptor(
        id: 'port_2',
        name: 'Bass Pod Pro',
        manufacturer: 'Line 6',
        isInput: true,
        isOutput: false,
      );

      expect(port1, equals(port2));
      expect(port1.hashCode, equals(port2.hashCode));
      expect(port1, isNot(equals(port3)));
      expect(port1.toString(), contains('Zoom MS-60B+'));
    });
  });

  group('MidiMessage', () {
    test('sysEx factory automatically wraps payload with 0xF0 and 0xF7 if missing', () {
      // Missing framing
      final msg = MidiMessage.sysEx([0x52, 0x00, 0x50]);
      expect(msg.isSysEx, isTrue);
      expect(msg.data, equals(Uint8List.fromList([0xF0, 0x52, 0x00, 0x50, 0xF7])));

      // Already framed
      final alreadyFramed = MidiMessage.sysEx([0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7]);
      expect(alreadyFramed.isSysEx, isTrue);
      expect(alreadyFramed.data, equals(Uint8List.fromList([0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7])));
    });

    test('controlChange factory builds valid 3-byte CC message', () {
      final ccMsg = MidiMessage.controlChange(channel: 1, controller: 7, value: 100);
      expect(ccMsg.isControlChange, isTrue);
      expect(ccMsg.isSysEx, isFalse);
      expect(ccMsg.isProgramChange, isFalse);
      expect(ccMsg.data, equals(Uint8List.fromList([0xB1, 0x07, 0x64])));
    });

    test('programChange factory builds valid 2-byte PC message', () {
      final pcMsg = MidiMessage.programChange(channel: 0, program: 42);
      expect(pcMsg.isProgramChange, isTrue);
      expect(pcMsg.isControlChange, isFalse);
      expect(pcMsg.isSysEx, isFalse);
      expect(pcMsg.data, equals(Uint8List.fromList([0xC0, 0x2A])));
    });

    test('evaluates byte-level equality and hashCodes', () {
      final msg1 = MidiMessage(Uint8List.fromList([0xF0, 0x52, 0xF7]));
      final msg2 = MidiMessage(Uint8List.fromList([0xF0, 0x52, 0xF7]));
      final msg3 = MidiMessage(Uint8List.fromList([0xF0, 0x53, 0xF7]));

      expect(msg1, equals(msg2));
      expect(msg1.hashCode, equals(msg2.hashCode));
      expect(msg1, isNot(equals(msg3)));
      expect(msg1.toString(), contains('F0 52 F7'));
    });
  });

  group('MockMidiTransport', () {
    late MockMidiTransport transport;
    final testPort = const MidiPortDescriptor(
      id: 'test_port_0',
      name: 'Simulated Pedal Port',
      manufacturer: 'SimCorp',
      isInput: true,
      isOutput: true,
    );

    setUp(() {
      transport = MockMidiTransport(initialPorts: [testPort]);
    });

    tearDown(() async {
      await transport.dispose();
    });

    test('retrieves available ports and manages connection lifecycle', () async {
      final ports = await transport.getAvailablePorts();
      expect(ports.length, equals(1));
      expect(ports.first.id, equals('test_port_0'));
      expect(transport.isConnected, isFalse);
      expect(transport.connectedPort, isNull);

      await transport.connect('test_port_0');
      expect(transport.isConnected, isTrue);
      expect(transport.connectedPort, equals(testPort));

      await transport.disconnect();
      expect(transport.isConnected, isFalse);
      expect(transport.connectedPort, isNull);
    });

    test('throws ArgumentError when connecting to unknown port ID', () async {
      expect(
        () => transport.connect('invalid_port_id'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws StateError when attempting to send while disconnected', () async {
      final msg = MidiMessage.sysEx([0x52, 0x01]);
      expect(() => transport.send(msg), throwsA(isA<StateError>()));
    });

    test('records sent messages into sentMessages history', () async {
      await transport.connect('test_port_0');
      final msg1 = MidiMessage.controlChange(channel: 0, controller: 4, value: 64);
      final msg2 = MidiMessage.programChange(channel: 0, program: 12);

      await transport.send(msg1);
      await transport.send(msg2);

      expect(transport.sentMessages.length, equals(2));
      expect(transport.sentMessages[0], equals(msg1));
      expect(transport.sentMessages[1], equals(msg2));

      transport.clearSentMessages();
      expect(transport.sentMessages, isEmpty);
    });

    test('simulateIncomingMessage emits messages on onMessageReceived', () async {
      await transport.connect('test_port_0');
      final incoming = MidiMessage.sysEx([0x52, 0x99]);

      final futureReceived = transport.onMessageReceived.first;
      transport.simulateIncomingMessage(incoming);

      final received = await futureReceived;
      expect(received, equals(incoming));
    });

    test('sendSysExAndWait dispatches request and awaits matching responder', () async {
      await transport.connect('test_port_0');

      final inquiryRequest = MidiMessage.sysEx([0x7E, 0x00, 0x06, 0x01]);
      final inquiryReply = MidiMessage.sysEx([0x7E, 0x00, 0x06, 0x02, 0x52, 0x60]);

      // Register mock responder
      transport.registerResponder(
        (req) => req.isSysEx && req.data.contains(0x06),
        (req) => inquiryReply,
      );

      final response = await transport.sendSysExAndWait(
        inquiryRequest,
        responseMatcher: (res) => res.isSysEx && res.data.contains(0x02),
        timeout: const Duration(seconds: 1),
      );

      expect(response, equals(inquiryReply));
      expect(transport.sentMessages.first, equals(inquiryRequest));
    });

    test('sendSysExAndWait times out if matching response is not received', () async {
      await transport.connect('test_port_0');
      final request = MidiMessage.sysEx([0x12, 0x34]);

      expect(
        () => transport.sendSysExAndWait(
          request,
          responseMatcher: (msg) => msg.data.contains(0xFF),
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

