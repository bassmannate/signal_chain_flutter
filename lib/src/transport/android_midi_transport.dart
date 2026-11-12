import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/midi/midi_message.dart';
import '../../core/midi/midi_port_descriptor.dart';
import '../../core/midi/midi_transport.dart';

class AndroidMidiTransport extends MidiTransport {
  static const _commandChannel = MethodChannel('signal_chain/midi_command');
  static const _rxChannel = EventChannel('signal_chain/midi_rx');

  MidiPortDescriptor? _connectedPort;
  StreamSubscription<dynamic>? _rxSubscription;
  final StreamController<MidiMessage> _incomingController = StreamController<MidiMessage>.broadcast();
  final List<int> _rxBuffer = [];

  @override
  bool get isConnected => _connectedPort != null;

  @override
  MidiPortDescriptor? get connectedPort => _connectedPort;

  @override
  Stream<MidiMessage> get onMessageReceived => _incomingController.stream;

  @override
  Future<List<MidiPortDescriptor>> getAvailablePorts() async {
    final List<dynamic> ports = await _commandChannel.invokeMethod('getAvailablePorts');
    return ports.map((port) {
      final map = port as Map<dynamic, dynamic>;
      return MidiPortDescriptor(
        id: map['id'] as String,
        name: map['name'] as String,
        isInput: (map['inputPortCount'] as int) > 0,
        isOutput: (map['outputPortCount'] as int) > 0,
      );
    }).toList();
  }

  @override
  Future<void> connect(String portId) async {
    await _rxSubscription?.cancel();
    _rxSubscription = null;
    _rxBuffer.clear();

    await _commandChannel.invokeMethod('connect', {'portId': portId});
    _connectedPort = (await getAvailablePorts()).firstWhere((p) => p.id == portId);
    
    _rxSubscription = _rxChannel.receiveBroadcastStream().listen(_onRxData);
  }

  void _onRxData(dynamic data) {
    if (data is List<int>) {
      _rxBuffer.addAll(data);
    } else if (data is List) {
      _rxBuffer.addAll(data.cast<int>());
    } else {
      return;
    }
    _processRxBuffer();
  }

  void _processRxBuffer() {
    int cursor = 0;

    while (cursor < _rxBuffer.length) {
      final status = _rxBuffer[cursor];

      if (status < 0x80) {
        // Ignore stray data bytes outside of a valid MIDI message.
        cursor++;
        continue;
      }

      if (status == 0xF0) {
        int endIndex = -1;
        int? restartIndex;
        for (int i = cursor + 1; i < _rxBuffer.length; i++) {
          final b = _rxBuffer[i];
          if (b == 0xF7) {
            endIndex = i;
            break;
          }
          if (b == 0xF0) {
            restartIndex = i;
            break;
          }
        }
        if (restartIndex != null) {
          // Previous SysEx was interrupted before 0xF7; resync at new 0xF0.
          cursor = restartIndex;
          continue;
        }
        if (endIndex == -1) {
          // Incomplete trailing SysEx; keep remaining bytes for next chunk.
          break;
        }
        final sysexBytes = Uint8List.fromList(_rxBuffer.sublist(cursor, endIndex + 1));
        _emitMessage(sysexBytes);
        cursor = endIndex + 1;
        continue;
      }

      if (status == 0xF7) {
        // Orphaned SysEx terminator outside of a SysEx block.
        cursor++;
        continue;
      }

      final expectedLength = _expectedMessageLength(status);
      if (cursor + expectedLength > _rxBuffer.length) {
        // Incomplete standard MIDI message; wait for remaining bytes.
        break;
      }

      int? unexpectedStatusOffset;
      for (int i = 1; i < expectedLength; i++) {
        if (_rxBuffer[cursor + i] >= 0x80) {
          unexpectedStatusOffset = i;
          break;
        }
      }
      if (unexpectedStatusOffset != null) {
        // Truncated channel/system message; resync at the new status byte.
        cursor += unexpectedStatusOffset;
        continue;
      }

      final messageBytes = Uint8List.fromList(
        _rxBuffer.sublist(cursor, cursor + expectedLength),
      );
      _emitMessage(messageBytes);
      cursor += expectedLength;
    }

    if (cursor > 0) {
      _rxBuffer.removeRange(0, cursor);
    }
  }

  int _expectedMessageLength(int status) {
    final statusNibble = status & 0xF0;
    if (statusNibble == 0xC0 || statusNibble == 0xD0) {
      // Program Change (0xCn) or Channel Pressure (0xDn): 2 bytes
      return 2;
    }
    if (statusNibble >= 0x80 && statusNibble <= 0xE0) {
      // Note Off, Note On, Poly Key Pressure, Control Change, Pitch Bend: 3 bytes
      return 3;
    }
    if (status == 0xF1 || status == 0xF3) {
      // MTC Quarter Frame (0xF1) or Song Select (0xF3): 2 bytes
      return 2;
    }
    if (status == 0xF2) {
      // Song Position Pointer (0xF2): 3 bytes
      return 3;
    }
    // Tune Request (0xF6) and System Real-Time (0xF8..0xFF): 1 byte
    return 1;
  }

  void _emitMessage(Uint8List bytes) {
    if (!_incomingController.isClosed) {
      _incomingController.add(MidiMessage(bytes));
    }
  }

  @override
  Future<void> disconnect() async {
    await _rxSubscription?.cancel();
    _rxSubscription = null;
    _rxBuffer.clear();
    await _commandChannel.invokeMethod('disconnect');
    _connectedPort = null;
  }

  @override
  Future<void> send(MidiMessage message) async {
    await _commandChannel.invokeMethod('send', {'data': message.data});
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _incomingController.close();
  }
}
