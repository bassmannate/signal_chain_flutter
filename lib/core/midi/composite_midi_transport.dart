import 'dart:async';
import 'midi_message.dart';
import 'midi_port_descriptor.dart';
import 'midi_transport.dart';

/// Aggregates multiple child [MidiTransport] instances into a unified interface.
///
/// Port discovery queries all child transports simultaneously.
/// Connecting to a port routes messages and send operations to whichever
/// child transport owns that port.
class CompositeMidiTransport extends MidiTransport {
  final List<MidiTransport> transports;
  final StreamController<MidiMessage> _incomingController =
      StreamController<MidiMessage>.broadcast();

  final Map<String, MidiTransport> _portToTransportMap = {};
  MidiTransport? _activeTransport;
  StreamSubscription<MidiMessage>? _activeSubscription;

  CompositeMidiTransport({required this.transports});

  /// The currently active child transport handling the connected port.
  MidiTransport? get activeTransport => _activeTransport;

  @override
  bool get isConnected => _activeTransport?.isConnected ?? false;

  @override
  MidiPortDescriptor? get connectedPort => _activeTransport?.connectedPort;

  @override
  Stream<MidiMessage> get onMessageReceived => _incomingController.stream;

  @override
  Future<List<MidiPortDescriptor>> getAvailablePorts() async {
    _portToTransportMap.clear();
    final allPorts = <MidiPortDescriptor>[];

    for (final transport in transports) {
      try {
        final ports = await transport.getAvailablePorts();
        for (final port in ports) {
          _portToTransportMap[port.id] = transport;
          allPorts.add(port);
        }
      } catch (_) {
        // Gracefully ignore individual child transport failures
      }
    }

    return List.unmodifiable(allPorts);
  }

  @override
  Future<void> connect(String portId) async {
    if (!_portToTransportMap.containsKey(portId)) {
      await getAvailablePorts();
    }

    final targetTransport = _portToTransportMap[portId];
    if (targetTransport == null) {
      throw ArgumentError('Port "$portId" not found in any child transport.');
    }

    if (_activeTransport != null && _activeTransport != targetTransport) {
      await disconnect();
    }

    await targetTransport.connect(portId);
    _activeTransport = targetTransport;

    await _activeSubscription?.cancel();
    _activeSubscription = targetTransport.onMessageReceived.listen((msg) {
      if (!_incomingController.isClosed) {
        _incomingController.add(msg);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    if (_activeTransport != null) {
      await _activeTransport!.disconnect();
      _activeTransport = null;
    }
  }

  @override
  Future<void> send(MidiMessage message) async {
    if (_activeTransport == null || !_activeTransport!.isConnected) {
      throw StateError('Cannot send message: CompositeMidiTransport is not connected.');
    }
    await _activeTransport!.send(message);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    for (final transport in transports) {
      await transport.dispose();
    }
    if (!_incomingController.isClosed) {
      await _incomingController.close();
    }
  }
}

