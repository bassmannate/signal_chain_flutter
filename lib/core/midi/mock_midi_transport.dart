import 'dart:async';
import 'midi_message.dart';
import 'midi_port_descriptor.dart';
import 'midi_transport.dart';

typedef MidiResponderEntry = ({
  bool Function(MidiMessage) matcher,
  MidiMessage Function(MidiMessage) responder,
});

/// Deterministic in-memory [MidiTransport] implementation for unit tests and pedal simulation.
class MockMidiTransport extends MidiTransport {
  List<MidiPortDescriptor> mockPorts;

  final List<MidiMessage> _sentMessages = [];
  final StreamController<MidiMessage> _messageController =
      StreamController<MidiMessage>.broadcast();
  final List<MidiResponderEntry> _responders = [];

  bool _isConnected = false;
  MidiPortDescriptor? _connectedPort;

  MockMidiTransport({List<MidiPortDescriptor>? initialPorts})
      : mockPorts = initialPorts ?? [];

  /// Dynamically simulates plugging in a MIDI port.
  void addPort(MidiPortDescriptor port) {
    mockPorts.add(port);
  }

  /// Dynamically simulates unplugging a MIDI port by [portId].
  void removePort(String portId) {
    mockPorts.removeWhere((p) => p.id == portId);
  }

  /// All messages transmitted via [send].
  List<MidiMessage> get sentMessages => List.unmodifiable(_sentMessages);

  @override
  bool get isConnected => _isConnected;

  @override
  MidiPortDescriptor? get connectedPort => _connectedPort;

  @override
  Stream<MidiMessage> get onMessageReceived => _messageController.stream;

  @override
  Future<List<MidiPortDescriptor>> getAvailablePorts() async {
    return List.unmodifiable(mockPorts);
  }

  @override
  Future<void> connect(String portId) async {
    final portIndex = mockPorts.indexWhere((p) => p.id == portId);
    if (portIndex == -1) {
      throw ArgumentError('MidiPort with id "$portId" not found.');
    }
    _connectedPort = mockPorts[portIndex];
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPort = null;
  }

  @override
  Future<void> send(MidiMessage message) async {
    if (!_isConnected) {
      throw StateError('Cannot send message: MockMidiTransport is not connected.');
    }
    _sentMessages.add(message);

    // Evaluate auto-responders and trigger replies asynchronously
    for (final entry in _responders) {
      if (entry.matcher(message)) {
        final reply = entry.responder(message);
        scheduleMicrotask(() {
          if (!_messageController.isClosed) {
            _messageController.add(reply);
          }
        });
      }
    }
  }

  /// Registers an automatic responder for incoming [send] calls.
  ///
  /// Useful for mocking bidirectional handshakes (such as Universal Identity Requests or patch dumps).
  void registerResponder(
    bool Function(MidiMessage request) matcher,
    MidiMessage Function(MidiMessage request) responder,
  ) {
    _responders.add((matcher: matcher, responder: responder));
  }

  /// Clears all registered auto-responders.
  void clearResponders() {
    _responders.clear();
  }

  /// Clears the sent message history.
  void clearSentMessages() {
    _sentMessages.clear();
  }

  /// Simulates an incoming message received from the hardware.
  void simulateIncomingMessage(MidiMessage message) {
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _responders.clear();
    _sentMessages.clear();
    await _messageController.close();
  }
}

