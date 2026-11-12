import 'dart:async';
import 'midi_message.dart';
import 'midi_port_descriptor.dart';

/// Abstract interface for cross-platform MIDI input/output transport.
abstract class MidiTransport {
  /// Queries available hardware and virtual MIDI ports.
  Future<List<MidiPortDescriptor>> getAvailablePorts();

  /// Connects to a MIDI port by its unique [portId].
  Future<void> connect(String portId);

  /// Disconnects from the currently connected MIDI port.
  Future<void> disconnect();

  /// Returns true if currently connected to a port.
  bool get isConnected;

  /// Returns the currently connected port descriptor, or null if disconnected.
  MidiPortDescriptor? get connectedPort;

  /// Stream of all incoming MIDI messages received from the connected device.
  Stream<MidiMessage> get onMessageReceived;

  /// Sends a [MidiMessage] to the connected device.
  Future<void> send(MidiMessage message);

  /// Sends a SysEx [MidiMessage] to the connected device.
  Future<void> sendSysEx(MidiMessage message) => send(message);

  /// Helper to send a request (typically SysEx) and await a matching response.
  ///
  /// Subscribes to [onMessageReceived] prior to dispatching [request] to avoid
  /// race conditions with synchronous or fast hardware responses.
  Future<MidiMessage> sendRequest(
    MidiMessage request, {
    required bool Function(MidiMessage message) responseMatcher,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return sendSysExAndWait(
      request,
      responseMatcher: responseMatcher,
      timeout: timeout,
    );
  }

  /// Helper to send a request (typically SysEx) and await a matching response.
  ///
  /// Subscribes to [onMessageReceived] prior to dispatching [request] to avoid
  /// race conditions with synchronous or fast hardware responses.
  Future<MidiMessage> sendSysExAndWait(
    MidiMessage request, {
    required bool Function(MidiMessage message) responseMatcher,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final responseFuture =
        onMessageReceived.firstWhere(responseMatcher).timeout(timeout);
    await send(request);
    return await responseFuture;
  }

  /// Releases resources, timers, and stream controllers associated with the transport.
  Future<void> dispose();
}

