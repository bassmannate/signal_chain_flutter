import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../core/midi/midi_port_descriptor.dart';
import '../../core/midi/midi_transport.dart';
import '../../models/device_family.dart';
import '../../protocols/device_protocol.dart';
import '../../protocols/line6_bass_pod_pro_protocol.dart';
import '../../protocols/sysex_codec.dart';
import '../../protocols/zoom_ms_plus_protocol.dart';

/// Controller managing MIDI port discovery, device connection lifecycle,
/// hardware identity handshake, and active protocol resolution.
class DeviceConnectionController extends ChangeNotifier {
  final MidiTransport transport;

  List<MidiPortDescriptor> _availablePorts = [];
  MidiPortDescriptor? _connectedPort;
  DeviceFamily _activeFamily;
  DeviceProtocol _activeProtocol;
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _errorMessage;

  DeviceConnectionController({
    required this.transport,
    DeviceFamily defaultFamily = DeviceFamily.zoomMs60bPlus,
  })  : _activeFamily = defaultFamily,
        _activeProtocol = _resolveProtocolForFamily(defaultFamily);

  /// Available MIDI input/output ports discovered via [refreshPorts].
  List<MidiPortDescriptor> get availablePorts =>
      List.unmodifiable(_availablePorts);

  /// Currently connected MIDI port, or null if disconnected.
  MidiPortDescriptor? get connectedPort => _connectedPort;

  /// Returns true if the underlying transport is currently connected.
  bool get isConnected => transport.isConnected;

  /// Active hardware family.
  DeviceFamily get activeFamily => _activeFamily;

  /// Resolved protocol engine for [activeFamily].
  DeviceProtocol get activeProtocol => _activeProtocol;

  /// True while querying available MIDI ports.
  bool get isScanning => _isScanning;

  /// True while performing connection and identity handshakes.
  bool get isConnecting => _isConnecting;

  /// Error message from the most recent connection attempt, or null.
  String? get errorMessage => _errorMessage;

  /// Scans for available MIDI ports from [transport].
  Future<void> refreshPorts() async {
    _isScanning = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _availablePorts = await transport.getAvailablePorts();
    } catch (e) {
      _errorMessage = 'Failed to scan ports: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Explicitly selects a [DeviceFamily] and resolves the matching [DeviceProtocol].
  void selectDeviceFamily(DeviceFamily family) {
    _activeFamily = family;
    _activeProtocol = _resolveProtocolForFamily(family);
    notifyListeners();
  }

  /// Connects to [port], performs device identity inquiry handshake, and executes
  /// the protocol's initialization sequence.
  ///
  /// If [explicitFamily] is provided, automatic identity inquiry is bypassed in
  /// favor of the explicitly selected hardware profile.
  Future<void> connect(
    MidiPortDescriptor port, {
    DeviceFamily? explicitFamily,
  }) async {
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await transport.connect(port.id);
      _connectedPort = port;

      if (explicitFamily != null) {
        selectDeviceFamily(explicitFamily);
      } else {
        // Attempt Universal Identity Request handshake
        await _performIdentityHandshake(port);
      }

      // Execute hardware initialization sequence
      final initSequence = _activeProtocol.buildInitSequence();
      for (final msg in initSequence) {
        await transport.send(msg);
      }
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      try {
        await transport.disconnect();
      } catch (_) {}
      _connectedPort = null;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  /// Disconnects from the currently connected MIDI device.
  Future<void> disconnect() async {
    _errorMessage = null;
    try {
      if (transport.isConnected) {
        final disableEditor =
            _activeProtocol.buildEditorModeMessage(enable: false);
        if (disableEditor != null) {
          try {
            await transport.send(disableEditor);
          } catch (_) {}
        }
      }
      await transport.disconnect();
    } catch (e) {
      _errorMessage = 'Disconnection error: $e';
    } finally {
      _connectedPort = null;
      notifyListeners();
    }
  }

  /// Clears any active error message.
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Attempts Universal Non-Real-Time Identity Request handshake.
  /// Falls back to port name heuristic if device does not reply.
  Future<void> _performIdentityHandshake(MidiPortDescriptor port) async {
    const zoomProto = ZoomMsPlusProtocol();
    const line6Proto = Line6BassPodProProtocol();

    final identityReq = zoomProto.buildIdentityRequest();

    try {
      final reply = await transport.sendSysExAndWait(
        identityReq,
        responseMatcher: (msg) => SysexCodec.isIdentityReply(msg.data),
        timeout: const Duration(milliseconds: 600),
      );

      if (zoomProto.matchesIdentityResponse(reply)) {
        final detected = zoomProto.parseDeviceFamily(reply);
        selectDeviceFamily(detected);
        return;
      }

      if (line6Proto.matchesIdentityResponse(reply)) {
        selectDeviceFamily(DeviceFamily.line6BassPodPro);
        return;
      }
    } catch (_) {
      // Identity handshake timed out or not supported by endpoint;
      // proceed to port name heuristics.
    }

    // Port name heuristic fallback
    final nameLower = port.name.toLowerCase();
    if (nameLower.contains('pod') || nameLower.contains('line 6')) {
      selectDeviceFamily(DeviceFamily.line6BassPodPro);
    } else if (nameLower.contains('50g+') || nameLower.contains('ms-50g')) {
      selectDeviceFamily(DeviceFamily.zoomMs50gPlus);
    } else if (nameLower.contains('70cdr+') || nameLower.contains('ms-70cdr')) {
      selectDeviceFamily(DeviceFamily.zoomMs70cdrPlus);
    } else if (nameLower.contains('200d+') || nameLower.contains('ms-200d')) {
      selectDeviceFamily(DeviceFamily.zoomMs200dPlus);
    } else if (nameLower.contains('zoom') || nameLower.contains('60b+') || nameLower.contains('ms-')) {
      selectDeviceFamily(DeviceFamily.zoomMs60bPlus);
    }
    // Otherwise keep current activeFamily
  }

  static DeviceProtocol _resolveProtocolForFamily(DeviceFamily family) {
    switch (family) {
      case DeviceFamily.line6BassPodPro:
        return const Line6BassPodProProtocol();
      case DeviceFamily.zoomMs50gPlus:
      case DeviceFamily.zoomMs60bPlus:
      case DeviceFamily.zoomMs70cdrPlus:
      case DeviceFamily.zoomMs200dPlus:
      case DeviceFamily.unknown:
        return ZoomMsPlusProtocol(defaultFamily: family);
    }
  }
}
