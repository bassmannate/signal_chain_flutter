import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/android_midi_transport.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AndroidMidiTransport transport;

  const MethodChannel commandChannel = MethodChannel('signal_chain/midi_command');
  const MethodChannel rxMethodChannel = MethodChannel('signal_chain/midi_rx');
  final List<MethodCall> log = [];

  void emitRxChunk(Uint8List chunk) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'signal_chain/midi_rx',
      const StandardMethodCodec().encodeSuccessEnvelope(chunk),
      (ByteData? reply) {},
    );
  }

  setUp(() {
    transport = AndroidMidiTransport();
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(commandChannel, (methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'getAvailablePorts') {
        return [
          {'id': '1', 'name': 'Test Port', 'inputPortCount': 1, 'outputPortCount': 1}
        ];
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rxMethodChannel, (methodCall) async {
      return null;
    });
  });

  tearDown(() async {
    await transport.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(commandChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rxMethodChannel, null);
  });

  test('getAvailablePorts calls MethodChannel', () async {
    final ports = await transport.getAvailablePorts();
    expect(log.length, equals(1));
    expect(log.first.method, equals('getAvailablePorts'));
    expect(ports.length, equals(1));
    expect(ports.first.id, equals('1'));
  });

  test('connect calls MethodChannel', () async {
    await transport.connect('1');
    expect(log.length, equals(2));
    expect(log[0].method, equals('connect'));
    expect(log[1].method, equals('getAvailablePorts'));
    expect(log[0].arguments['portId'], equals('1'));
  });

  test('send calls MethodChannel', () async {
    final msg = MidiMessage.sysEx([0xF0, 0x00, 0xF7]);
    await transport.send(msg);
    expect(log.last.method, equals('send'));
    expect(log.last.arguments['data'], equals(msg.data));
  });

  test('stitches 989-byte SysEx patch dump split across 256-byte EventChannel chunks', () async {
    await transport.connect('1');

    final received = <MidiMessage>[];
    final sub = transport.onMessageReceived.listen(received.add);

    // Build a 989-byte SysEx payload: 0xF0 + 987 7-bit data bytes + 0xF7
    final fullPayload = Uint8List(989);
    fullPayload[0] = 0xF0;
    for (int i = 1; i < 988; i++) {
      fullPayload[i] = i & 0x7F;
    }
    fullPayload[988] = 0xF7;

    // Split into 256-byte chunks (256, 256, 256, 221)
    const chunkSize = 256;
    final chunks = <Uint8List>[];
    for (int offset = 0; offset < fullPayload.length; offset += chunkSize) {
      final end = (offset + chunkSize < fullPayload.length)
          ? offset + chunkSize
          : fullPayload.length;
      chunks.add(Uint8List.sublistView(fullPayload, offset, end));
    }
    expect(chunks.length, equals(4));
    expect(chunks[0].length, equals(256));
    expect(chunks[1].length, equals(256));
    expect(chunks[2].length, equals(256));
    expect(chunks[3].length, equals(221));

    // Emit first 3 incomplete chunks; nothing should be emitted yet
    for (int i = 0; i < 3; i++) {
      emitRxChunk(chunks[i]);
      await pumpEventQueue();
      expect(received, isEmpty);
    }

    // Emit final chunk containing 0xF7; single complete 989-byte SysEx should be emitted
    emitRxChunk(chunks[3]);
    await pumpEventQueue();

    expect(received.length, equals(1));
    expect(received.first.isSysEx, isTrue);
    expect(received.first.data.length, equals(989));
    expect(received.first.data, equals(fullPayload));

    await sub.cancel();
  });

  test('emits 2-byte PC and 3-byte CC messages outside SysEx and across chunks', () async {
    await transport.connect('1');

    final received = <MidiMessage>[];
    final sub = transport.onMessageReceived.listen(received.add);

    // Chunk 1: PC (2 bytes) + partial SysEx
    emitRxChunk(Uint8List.fromList([0xC2, 0x1A, 0xF0, 0x52, 0x00]));
    // Chunk 2: rest of SysEx + partial CC (first 2 bytes)
    emitRxChunk(Uint8List.fromList([0x6E, 0x33, 0xF7, 0xB0, 0x07]));
    // Chunk 3: final byte of CC + another complete PC
    emitRxChunk(Uint8List.fromList([0x64, 0xC0, 0x03]));
    await pumpEventQueue();

    expect(received.length, equals(4));
    expect(received[0].isProgramChange, isTrue);
    expect(received[0].data, equals(Uint8List.fromList([0xC2, 0x1A])));

    expect(received[1].isSysEx, isTrue);
    expect(received[1].data, equals(Uint8List.fromList([0xF0, 0x52, 0x00, 0x6E, 0x33, 0xF7])));

    expect(received[2].isControlChange, isTrue);
    expect(received[2].data, equals(Uint8List.fromList([0xB0, 0x07, 0x64])));

    expect(received[3].isProgramChange, isTrue);
    expect(received[3].data, equals(Uint8List.fromList([0xC0, 0x03])));

    await sub.cancel();
  });
}
