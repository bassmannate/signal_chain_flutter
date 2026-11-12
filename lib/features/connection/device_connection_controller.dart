import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../core/midi/midi_port_descriptor.dart';
import '../../core/midi/midi_message.dart';
import '../../core/midi/midi_transport.dart';
import '../../models/bank_slot_descriptor.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../protocols/device_protocol.dart';
import '../../protocols/line6_bass_pod_pro_protocol.dart';
import '../../protocols/sysex_codec.dart';
import '../../protocols/zoom_ms_plus_protocol.dart';

/// Callback signature for dispatching unsolicited incoming hardware updates.
typedef HardwareUpdateHandler = void Function({
  int? slotIndex,
  int? paramIndex,
  int? value,
  int? programNumber,
  Patch? patch,
  bool? isEnabled,
});

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

  List<BankSlotDescriptor> _bankSlots = [];
  bool _isSyncingBank = false;
  double _bankSyncProgress = 0.0;
  String? _bankSyncStatus;
  bool _cancelBankSync = false;
  bool _isDisposed = false;

  HardwareUpdateHandler? _hardwareUpdateHandler;
  StreamSubscription<MidiMessage>? _transportSubscription;
  Timer? _hotPlugTimer;
  bool _isHotPlugChecking = false;

  // Track incoming Bank Select (CC 0 MSB and CC 32 LSB) from hardware
  int _incomingBankMsb = 0;
  int _incomingBankLsb = 0;

  /// Current incoming bank index tracked from CC 0 and CC 32 messages.
  int get currentIncomingBank => (_incomingBankMsb << 7) | _incomingBankLsb;

  /// Known hardware identification patterns for auto-discovery.
  static const List<String> knownHardwarePatterns = [
    'zoom',
    'ms plus',
    'ms-60b',
    'ms-50g',
    'ms-70cdr',
    'ms-200d',
    'bass pod',
    'line 6',
  ];

  DeviceConnectionController({
    required this.transport,
    DeviceFamily defaultFamily = DeviceFamily.zoomMs60bPlus,
    bool enableHotPlugPolling = true,
  })  : _activeFamily = defaultFamily,
        _activeProtocol = _resolveProtocolForFamily(defaultFamily) {
    _transportSubscription = transport.onMessageReceived.listen(_handleIncomingHardwareEvent);
    final isTest = const bool.fromEnvironment('FLUTTER_TEST') ||
        (Platform.environment['FLUTTER_TEST'] == 'true');
    if (enableHotPlugPolling && !isTest) {
      _startHotPlugPolling();
    }
  }

  void _startHotPlugPolling() {
    _hotPlugTimer?.cancel();
    _hotPlugTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      checkHotPlug();
    });
  }

  /// Lightweight periodic hot-plug check that discovers hardware connections
  /// or cleanly detects hardware unplugging.
  Future<void> checkHotPlug() async {
    if (_isDisposed || _isHotPlugChecking || _isScanning || _isConnecting) {
      return;
    }
    _isHotPlugChecking = true;
    try {
      if (!isConnectedToRealHardware) {
        await refreshPorts(autoConnect: true);
      } else if (_connectedPort != null) {
        final available = await transport.getAvailablePorts();
        final stillConnected = available.any((p) => p.id == _connectedPort!.id);
        if (!stillConnected) {
          await disconnect();
        }
      }
    } catch (_) {
      // Ignore background hot-plug query errors
    } finally {
      _isHotPlugChecking = false;
    }
  }

  /// Sets the external update handler (e.g. from PatchEditorController).
  void setHardwareUpdateHandler(HardwareUpdateHandler? handler) {
    _hardwareUpdateHandler = handler;
  }

  /// Binds a controller implementing [applyExternalHardwareUpdate].
  void setEditorController(dynamic editor) {
    if (editor == null) {
      _hardwareUpdateHandler = null;
    } else {
      _hardwareUpdateHandler = editor.applyExternalHardwareUpdate;
    }
  }

  /// Tests whether [port] matches known Zoom or Line 6 hardware patterns.
  static bool isKnownHardwarePort(MidiPortDescriptor port) {
    final nameLower = port.name.toLowerCase();
    if (nameLower.contains('(simulated)') || port.id.startsWith('sim_')) {
      return false;
    }
    for (final pattern in knownHardwarePatterns) {
      if (nameLower.contains(pattern)) return true;
    }
    return false;
  }

  /// Resolves the best matching [DeviceFamily] from port name heuristics.
  static DeviceFamily? identifyFamilyFromPortName(String portName) {
    final nameLower = portName.toLowerCase();
    if (nameLower.contains('pod') || nameLower.contains('line 6') || nameLower.contains('line6')) {
      return DeviceFamily.line6BassPodPro;
    } else if (nameLower.contains('50g') || nameLower.contains('ms-50g')) {
      return DeviceFamily.zoomMs50gPlus;
    } else if (nameLower.contains('70cdr') || nameLower.contains('ms-70cdr')) {
      return DeviceFamily.zoomMs70cdrPlus;
    } else if (nameLower.contains('200d') || nameLower.contains('ms-200d')) {
      return DeviceFamily.zoomMs200dPlus;
    } else if (nameLower.contains('60b') || nameLower.contains('ms-60b')) {
      return DeviceFamily.zoomMs60bPlus;
    } else if (nameLower.contains('zoom') || nameLower.contains('ms plus')) {
      return DeviceFamily.zoomMs60bPlus;
    }
    return null;
  }

  /// Returns true if currently connected to a recognized physical hardware device.
  bool get isConnectedToRealHardware =>
      isConnected && _connectedPort != null && isKnownHardwarePort(_connectedPort!);

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

  /// Current snapshot of hardware memory bank slots (0 to 99).
  List<BankSlotDescriptor> get bankSlots => List.unmodifiable(_bankSlots);

  /// True while a bank sync operation is in progress.
  bool get isSyncingBank => _isSyncingBank;

  /// Normalized progress of bank sync operation (0.0 to 1.0).
  double get bankSyncProgress => _bankSyncProgress;

  /// Status description of the bank sync operation, or null.
  String? get bankSyncStatus => _bankSyncStatus;

  /// Scans for available MIDI ports from [transport] and auto-selects known hardware ports.
  Future<void> refreshPorts({bool autoConnect = true}) async {
    _isScanning = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _availablePorts = await transport.getAvailablePorts();

      if (autoConnect && !isConnectedToRealHardware) {
        final match = _availablePorts.cast<MidiPortDescriptor?>().firstWhere(
          (p) => p != null && isKnownHardwarePort(p),
          orElse: () => null,
        );

        if (match != null) {
          final matchedFamily = identifyFamilyFromPortName(match.name);
          await connect(match, explicitFamily: matchedFamily);

          // Request active patch from hardware
          try {
            final request = _activeProtocol.buildRequestCurrentPatchMessage();
            await transport.send(request);
          } catch (_) {}

          // Trigger background bank sync
          unawaited(syncDeviceBank());
        }
      }
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
      _ensureBankSlotsInitialized();
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
    cancelBankSync();
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

  /// Cancels an active bank sync operation.
  void cancelBankSync() {
    if (_isSyncingBank) {
      _cancelBankSync = true;
      _isSyncingBank = false;
      _bankSyncStatus = 'Bank sync canceled';
      notifyListeners();
    }
  }

  /// Safely fetches the names/descriptors of hardware persistent memory slots (0–99)
  /// without locking the UI.
  ///
  /// Incremental updates notify listeners as each slot resolves, enabling real-time
  /// UI progress without blocking user interactions.
  Future<void> syncDeviceBank({
    int? slotCount,
    Duration perSlotTimeout = const Duration(milliseconds: 350),
  }) async {
    if (!transport.isConnected) {
      _errorMessage = 'Cannot sync hardware bank: MIDI device is not connected.';
      notifyListeners();
      return;
    }

    final totalSlots = slotCount ?? _activeFamily.totalMemorySlots;
    if (_bankSlots.length != totalSlots) {
      _bankSlots = List.generate(
        totalSlots,
        (i) => BankSlotDescriptor(
          index: i,
          name: 'Slot ${i.toString().padLeft(2, '0')}',
          deviceFamily: _activeFamily,
          isLoaded: false,
        ),
      );
    }

    _isSyncingBank = true;
    _cancelBankSync = false;
    _bankSyncProgress = 0.0;
    _bankSyncStatus = 'Syncing hardware bank (0/$totalSlots)...';
    _errorMessage = null;
    notifyListeners();

    try {
      final activeProto = _activeProtocol;

      for (int i = 0; i < totalSlots; i++) {
        if (_cancelBankSync || !transport.isConnected) {
          break;
        }

        _bankSyncStatus = 'Fetching slot ${i + 1}/$totalSlots...';
        _bankSyncProgress = i / totalSlots;

        try {
          final request = activeProto.buildPatchSlotRequest(i);
          final response = await transport.sendSysExAndWait(
            request,
            responseMatcher: (m) =>
                activeProto.isSlotPatchDump(m) &&
                activeProto.extractSlotIndex(m) == i,
            timeout: perSlotTimeout,
          );

          final decoded = activeProto.decodePatch(response);
          _bankSlots[i] = BankSlotDescriptor(
            index: i,
            name: decoded.name.trim().isNotEmpty
                ? decoded.name.trim()
                : 'Slot ${i.toString().padLeft(2, '0')}',
            deviceFamily: _activeFamily,
            isLoaded: true,
            isEmpty: decoded.slots.isEmpty,
            patch: decoded,
          );
        } catch (_) {
          // If a slot read times out or is uninitialized, record slot as loaded but empty
          if (!_bankSlots[i].isLoaded) {
            _bankSlots[i] = BankSlotDescriptor(
              index: i,
              name: 'Slot ${i.toString().padLeft(2, '0')}',
              deviceFamily: _activeFamily,
              isLoaded: true,
              isEmpty: true,
            );
          }
        }

        // Incremental notification and micro-yield to keep UI responsive
        notifyListeners();
        await Future<void>.value();
      }

      _bankSyncProgress = 1.0;
      _bankSyncStatus = _cancelBankSync
          ? 'Sync canceled'
          : 'Sync complete ($totalSlots slots)';

      // Guardrail: Ensure Parameter Edit Enable (0x50) remains active after slot dumps
      // so physical knobs, bypass, and patch switches stream live in real time.
      if (transport.isConnected) {
        try {
          final enableEditMsg = activeProto.buildEditorModeMessage(enable: true);
          if (enableEditMsg != null) {
            await transport.send(enableEditMsg);
          }
        } catch (_) {}
      }
    } catch (e) {
      _errorMessage = 'Hardware bank sync error: $e';
    } finally {
      _isSyncingBank = false;
      notifyListeners();
    }
  }

  void _ensureBankSlotsInitialized() {
    if (_bankSlots.length != _activeFamily.totalMemorySlots) {
      _bankSlots = List.generate(
        _activeFamily.totalMemorySlots,
        (i) => BankSlotDescriptor(
          index: i,
          name: 'Slot ${i.toString().padLeft(2, '0')}',
          deviceFamily: _activeFamily,
          isLoaded: false,
        ),
      );
    }
  }

  /// Updates a specific bank slot in local memory (e.g. after writing a patch to hardware).
  void updateBankSlot(
    int index, {
    required String patchName,
    Patch? patch,
  }) {
    _ensureBankSlotsInitialized();
    if (index >= 0 && index < _bankSlots.length) {
      _bankSlots[index] = _bankSlots[index].copyWith(
        name: patchName,
        isLoaded: true,
        isEmpty: false,
        patch: patch,
      );
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

  /// Routes unsolicited incoming MIDI events from hardware to registered editor controllers.
  void _handleIncomingHardwareEvent(MidiMessage message) {
    // Persistent memory slot dumps (0x45 / 0x08) strictly update bank slots only, never the editor buffer!
    if (_activeProtocol.isSlotPatchDump(message)) {
      final slotIndex = _activeProtocol.extractSlotIndex(message);
      if (slotIndex != null && slotIndex >= 0 && slotIndex < _bankSlots.length) {
        try {
          final decoded = _activeProtocol.decodePatch(message);
          updateBankSlot(
            slotIndex,
            patchName: decoded.name.trim().isNotEmpty
                ? decoded.name.trim()
                : 'Slot ${slotIndex.toString().padLeft(2, '0')}',
            patch: decoded,
          );
        } catch (_) {}
      }
      return;
    }

    // Track Bank Select CC messages from hardware (CC 0 = MSB, CC 32 = LSB)
    if (message.isControlChange) {
      final ccNum = message.data[1];
      final ccVal = message.data[2];
      if (ccNum == 0x00) {
        _incomingBankMsb = ccVal & 0x7F;
      } else if (ccNum == 0x20) {
        _incomingBankLsb = ccVal & 0x7F;
      }
      return;
    }

    // Zoom MS Plus bankAndProgramNumberV2 (SysEx 64 26 00 00)
    if (_activeProtocol.isSlotChange(message)) {
      final slotIndex = _activeProtocol.parseSlotChange(message);
      if (slotIndex != null) {
        _incomingBankMsb = 0;
        _incomingBankLsb = slotIndex ~/ 10;
        _hardwareUpdateHandler?.call(programNumber: slotIndex);
      }
      return;
    }

    // Program Change: combined with tracked Bank Select (10 patches/bank on MS Plus)
    if (message.isProgramChange) {
      final prog = message.data.length > 1 ? (message.data[1] & 0x7F) : 0;
      final slotIndex = (currentIncomingBank * 10) + prog;
      _hardwareUpdateHandler?.call(programNumber: slotIndex);
      return;
    }

    // Real-time Slot Focus / Cursor navigation from pedal Left/Right buttons
    if (_activeProtocol.isSlotFocusChange(message)) {
      final slotIndex = _activeProtocol.parseSlotFocusChange(message);
      if (slotIndex != null) {
        _hardwareUpdateHandler?.call(slotIndex: slotIndex);
      }
      return;
    }

    // Real-time Slot Bypass toggle from physical pedal footswitch
    if (_activeProtocol.isSlotBypass(message)) {
      final bypass = _activeProtocol.parseSlotBypass(message);
      if (bypass != null) {
        _hardwareUpdateHandler?.call(
          slotIndex: bypass.slotIndex,
          isEnabled: bypass.isEnabled,
        );
      }
      return;
    }

    // Real-time Parameter Edit from physical pedal knob
    if (_activeProtocol.isParameterEdit(message)) {
      final edit = _activeProtocol.parseParameterEdit(message);
      if (edit != null) {
        _hardwareUpdateHandler?.call(
          slotIndex: edit.slotIndex,
          paramIndex: edit.paramIndex,
          value: edit.value,
        );
      }
      return;
    }

    // Only active edit buffer dumps update the live editor!
    if (_activeProtocol.isCurrentPatchDump(message)) {
      try {
        final decoded = _activeProtocol.decodePatch(message);
        _hardwareUpdateHandler?.call(patch: decoded);
      } catch (_) {}
      return;
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _hotPlugTimer?.cancel();
    cancelBankSync();
    _transportSubscription?.cancel();
    super.dispose();
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
