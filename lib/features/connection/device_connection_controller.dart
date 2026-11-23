import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../core/midi/composite_midi_transport.dart';
import '../../core/midi/midi_port_descriptor.dart';
import '../../core/midi/midi_message.dart';
import '../../core/midi/midi_transport.dart';
import '../../core/midi/mock_midi_transport.dart';
import '../../core/storage/custom_effect_repository.dart';
import '../../core/zd2/flst_seq_parser.dart';
import '../../core/zd2/zd2_parser.dart';
import '../../models/bank_slot_descriptor.dart';
import '../../models/device_family.dart';
import '../../models/patch.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../../protocols/device_protocol.dart';
import '../../protocols/line6_bass_pod_pro_protocol.dart';
import '../../protocols/sysex_codec.dart';
import '../../protocols/zoom_file_transfer_service.dart';
import '../../protocols/zoom_ms_plus_protocol.dart';

/// Callback signature for dispatching unsolicited incoming hardware updates.
typedef HardwareUpdateHandler = void Function({
  int? slotIndex,
  int? paramIndex,
  int? value,
  int? programNumber,
  Patch? patch,
  bool? isEnabled,
  int? rightOutputTapCode,
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
  bool _isTunerActive = false;

  HardwareUpdateHandler? _hardwareUpdateHandler;
  dynamic _editor;
  CustomEffectRepository? _customEffectRepository;
  StreamSubscription<MidiMessage>? _transportSubscription;
  Timer? _hotPlugTimer;
  bool _isHotPlugChecking = false;

  int? _activeHardwareSlotIndex;

  // Live hardware onboard effect inventory (populated via read-only FLST_SEQ.ZT2
  // discovery on Zoom MS+ and Zoom Four hardware; cleared on disconnect / Line 6).
  Set<String>? _installedEffectIds;
  List<FlstEffectEntry> _installedFlstEntries = const [];
  Set<String> _discoveredStockIds = const {};
  Set<String> _discoveredCrossModelIds = const {};
  Set<String> _discoveredCustomIds = const {};
  DeviceEffectDiscoveryResult? _lastEffectDiscoveryResult;
  bool _isScanningEffects = false;
  String? _effectScanStatusMessage;
  String? _effectScanError;
  bool _suppressIncomingHardwareEvents = false;
  int _discoverySessionToken = 0;

  // Track incoming Bank Select (CC 0 MSB and CC 32 LSB) from hardware
  int _incomingBankMsb = 0;
  int _incomingBankLsb = 0;

  /// Current incoming bank index tracked from CC 0 and CC 32 messages.
  int get currentIncomingBank => (_incomingBankMsb << 7) | _incomingBankLsb;

  final Duration? pacingDelayOverride;
  final Duration? currentPatchTimeoutOverride;
  final Duration? effectDiscoveryTimeoutOverride;
  final bool _isTest;

  /// Known hardware identification patterns for auto-discovery.
  static const List<String> knownHardwarePatterns = [
    'zoom',
    'b1x four',
    'b1 four',
    'g1x four',
    'g1 four',
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
    this.pacingDelayOverride,
    this.currentPatchTimeoutOverride,
    this.effectDiscoveryTimeoutOverride,
    CustomEffectRepository? customEffectRepository,
    bool? isTest,
  })  : _isTest = isTest ??
            (const bool.fromEnvironment('FLUTTER_TEST') ||
                (Platform.environment['FLUTTER_TEST'] == 'true')),
        _activeFamily = defaultFamily,
        _activeProtocol = _resolveProtocolForFamily(defaultFamily) {
    _customEffectRepository = customEffectRepository;
    _transportSubscription = transport.onMessageReceived.listen(_handleIncomingHardwareEvent);
    if (enableHotPlugPolling && !_isTest) {
      _startHotPlugPolling();
    }
  }

  /// Pacing delay between sequential initialization commands and requests.
  Duration get pacingDelay =>
      pacingDelayOverride ?? (_isTest ? Duration.zero : const Duration(milliseconds: 25));

  /// Timeout for current patch request.
  Duration get currentPatchTimeout =>
      currentPatchTimeoutOverride ??
      (_isTest ? const Duration(milliseconds: 50) : const Duration(milliseconds: 800));

  /// Per-packet timeout used during read-only Zoom `0x60` effect discovery.
  Duration get effectDiscoveryPacketTimeout =>
      effectDiscoveryTimeoutOverride ??
      (_isTest ? const Duration(milliseconds: 25) : const Duration(milliseconds: 1200));

  /// Currently bound [CustomEffectRepository], falling back to the bound editor's repository.
  CustomEffectRepository? get customEffectRepository {
    if (_customEffectRepository != null) return _customEffectRepository;
    try {
      final repo = _editor?.customEffectRepository;
      if (repo is CustomEffectRepository) return repo;
    } catch (_) {}
    return null;
  }

  /// Binds a [CustomEffectRepository] used to cache newly discovered custom `.ZD2` effects.
  void setCustomEffectRepository(CustomEffectRepository? repository) {
    _customEffectRepository = repository;
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

  /// Currently active hardware memory slot index (0 to 99), or null if not yet determined.
  int? get activeHardwareSlotIndex => _activeHardwareSlotIndex;

  /// Explicitly sets the active hardware slot index, optionally synchronizing the
  /// bound editor patch's [Patch.programNumber] metadata, and updates listeners.
  void setActiveHardwareSlotIndex(
    int? slotIndex, {
    bool syncEditorPatchProgramNumber = true,
  }) {
    if (_activeHardwareSlotIndex != slotIndex) {
      _activeHardwareSlotIndex = slotIndex;
      if (syncEditorPatchProgramNumber && slotIndex != null && _editor != null) {
        try {
          _editor.setHardwareSlotIndex(slotIndex);
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  /// Searches loaded bank slots for one matching [currentPatch]'s effect signature.
  int? findMatchingBankSlot(Patch currentPatch) {
    if (currentPatch.slots.isEmpty && currentPatch.name.trim().isEmpty) {
      return null;
    }

    // Pass 1: Exact signature match (name + effect IDs + bypass + parameter values)
    for (final slot in _bankSlots) {
      if (slot.isLoaded && !slot.isEmpty && slot.patch != null) {
        if (Patch.isSignatureMatch(currentPatch, slot.patch!, matchParameters: true)) {
          return slot.index;
        }
      }
    }

    // Pass 2: Signature match without parameter values (name + effect IDs + bypass)
    if (currentPatch.name.trim().isNotEmpty && currentPatch.slots.isNotEmpty) {
      for (final slot in _bankSlots) {
        if (slot.isLoaded && !slot.isEmpty && slot.patch != null) {
          if (Patch.isSignatureMatch(currentPatch, slot.patch!, matchParameters: false)) {
            return slot.index;
          }
        }
      }
    }

    return null;
  }

  /// Sets the external update handler (e.g. from PatchEditorController).
  void setHardwareUpdateHandler(HardwareUpdateHandler? handler) {
    _hardwareUpdateHandler = handler;
  }

  /// Binds a controller implementing [applyExternalHardwareUpdate].
  void setEditorController(dynamic editor) {
    _editor = editor;
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

  /// Resolves the best matching [DeviceFamily] from a [MidiPortDescriptor]
  /// by checking `port.name`, `port.id`, and `port.manufacturer`.
  static DeviceFamily? identifyFamilyFromPort(MidiPortDescriptor port) {
    return identifyFamilyFromPortName(port.name) ??
        identifyFamilyFromPortName(port.id) ??
        (port.manufacturer != null
            ? identifyFamilyFromPortName(port.manufacturer!)
            : null);
  }

  /// Resolves the best matching [DeviceFamily] from port name heuristics.
  static DeviceFamily? identifyFamilyFromPortName(String portName) {
    final nameLower = portName.toLowerCase();
    if (nameLower.contains('pod') || nameLower.contains('line 6') || nameLower.contains('line6')) {
      return DeviceFamily.line6BassPodPro;
    }
    final zoomFour = ZoomFourProfile.fromPortName(portName);
    if (zoomFour != null) {
      return zoomFour.deviceFamily;
    }
    if (nameLower.contains('50g') || nameLower.contains('ms-50g')) {
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

  /// Connected hardware device family, or null when disconnected.
  DeviceFamily? get connectedDeviceFamily => isConnected ? _activeFamily : null;

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

  /// True when the hardware tuner is currently engaged.
  bool get isTunerActive => _isTunerActive;

  /// Authoritative set of normalized uppercase `'0xXXXXXXXX'` effect IDs
  /// verified installed on the connected Zoom pedal, or `null` when offline,
  /// non-Zoom, or discovery failed/unsupported.
  Set<String>? get installedEffectIds =>
      _installedEffectIds == null ? null : Set.unmodifiable(_installedEffectIds!);

  /// Installed `FLST_SEQ.ZT2` entries verified on the connected Zoom pedal.
  List<FlstEffectEntry> get installedFlstEntries =>
      List.unmodifiable(_installedFlstEntries);

  /// Stock effect IDs confirmed installed on the connected Zoom pedal.
  Set<String> get discoveredStockIds => Set.unmodifiable(_discoveredStockIds);

  /// Cross-model sibling effect IDs confirmed installed on the connected Zoom pedal.
  Set<String> get discoveredCrossModelIds =>
      Set.unmodifiable(_discoveredCrossModelIds);

  /// Custom `.ZD2` effect IDs confirmed installed on the connected Zoom pedal.
  Set<String> get discoveredCustomIds => Set.unmodifiable(_discoveredCustomIds);

  /// Result object from the most recent onboard effect discovery pass, or null.
  DeviceEffectDiscoveryResult? get lastEffectDiscoveryResult =>
      _lastEffectDiscoveryResult;

  /// True while a read-only Zoom onboard effect discovery scan is running.
  bool get isScanningEffects => _isScanningEffects;

  /// Human-readable status message during an active onboard effect scan.
  String? get effectScanStatusMessage => _effectScanStatusMessage;

  /// Non-fatal warning/error message from the most recent effect discovery scan.
  String? get effectScanError => _effectScanError;

  /// Engages or exits the hardware tuner and dispatches protocol MIDI commands.
  Future<void> setTunerActive(bool enabled) async {
    if (_isTunerActive == enabled) return;
    _isTunerActive = enabled;
    notifyListeners();

    if (!transport.isConnected) return;

    int? restoreProgramNumber = _activeHardwareSlotIndex;
    if (restoreProgramNumber == null && _editor != null) {
      try {
        restoreProgramNumber = (_editor.patch as Patch?)?.programNumber;
      } catch (_) {}
    }

    final messages = _activeProtocol.buildTunerToggleMessages(
      enabled,
      restoreProgramNumber: restoreProgramNumber,
    );
    for (final msg in messages) {
      try {
        await transport.send(msg);
      } catch (_) {}
    }
  }

  /// Toggles the hardware tuner active state.
  Future<void> toggleTuner() => setTunerActive(!_isTunerActive);

  /// Resets the local tuner indicator without dispatching MIDI.
  void resetTunerState() {
    if (_isTunerActive) {
      _isTunerActive = false;
      notifyListeners();
    }
  }

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
          final matchedFamily = identifyFamilyFromPort(match);
          await connect(
            match,
            explicitFamily: matchedFamily,
            autoSyncBank: true,
            fetchCurrentPatch: true,
          );
        }
      } else if (!isConnectedToRealHardware) {
        final match = _availablePorts.cast<MidiPortDescriptor?>().firstWhere(
          (p) => p != null && isKnownHardwarePort(p),
          orElse: () => null,
        );
        if (match != null) {
          final matchedFamily = identifyFamilyFromPort(match);
          if (matchedFamily != null && matchedFamily != DeviceFamily.unknown) {
            selectDeviceFamily(matchedFamily);
          }
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
    final switchedFamily = _activeFamily != family;
    _activeFamily = family;
    _activeProtocol = _resolveProtocolForFamily(family);
    if (!isConnected || !family.isZoom6E || switchedFamily && !isConnected) {
      _clearHardwareEffectInventory(notify: false);
    }
    notifyListeners();
  }

  void _clearHardwareEffectInventory({bool notify = true}) {
    _installedEffectIds = null;
    _installedFlstEntries = const [];
    _discoveredStockIds = const {};
    _discoveredCrossModelIds = const {};
    _discoveredCustomIds = const {};
    _lastEffectDiscoveryResult = null;
    _isScanningEffects = false;
    _effectScanStatusMessage = null;
    _effectScanError = null;
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
    if (notify) {
      notifyListeners();
    }
  }

  /// Performs a strictly READ-ONLY Zoom USB-MIDI onboard effect discovery scan:
  /// 1. Downloads and parses `FLST_SEQ.ZT2` in PC Mode (`0x52`).
  /// 2. Classifies installed entries into Tier 1 stock, Tier 2 sibling cross-model,
  ///    already-cached Tier 3 custom, or uncached custom `.ZD2` files.
  /// 3. Downloads only uncached custom `.ZD2` files (or all custom `.ZD2`s when
  ///    [forceRedownloadCustom] is true) inside the same PC-Mode session, parses
  ///    each via [Zd2Parser], persists into [CustomEffectRepository], and registers
  ///    in [EffectCatalogRegistry].
  /// 4. Applies the runtime installed cross-model overlay to [EffectCatalogRegistry]
  ///    and re-hydrates the active editor patch.
  /// 5. Guarantees exit from PC Mode (`0x53`) and re-entry into Parameter Edit
  ///    Mode (`0x50`) even on failure or timeout.
  Future<DeviceEffectDiscoveryResult> scanInstalledEffects({
    bool forceRedownloadCustom = false,
  }) async {
    if (!transport.isConnected || !_activeFamily.isZoom6E) {
      if (!_activeFamily.isZoom6E) {
        _clearHardwareEffectInventory(notify: true);
      }
      return DeviceEffectDiscoveryResult.failure(
        'Onboard effect discovery is only available when connected to a Zoom pedal.',
      );
    }

    if (_isScanningEffects) {
      return _lastEffectDiscoveryResult ??
          DeviceEffectDiscoveryResult.failure(
            'Onboard effect scan is already in progress.',
          );
    }

    final sessionToken = ++_discoverySessionToken;
    final family = _activeFamily;
    final repo = customEffectRepository;

    _isScanningEffects = true;
    _effectScanError = null;
    _effectScanStatusMessage = 'Scanning onboard effects...';
    notifyListeners();

    final service = ZoomFileTransferService(
      transport: transport,
      modelId: ZoomMsPlusProtocol.familyIdByte,
      packetTimeout: effectDiscoveryPacketTimeout,
      pcModeAckTimeout: _isTest
          ? const Duration(milliseconds: 15)
          : const Duration(milliseconds: 250),
      closeAckTimeout: _isTest
          ? const Duration(milliseconds: 15)
          : const Duration(milliseconds: 200),
      pacingDelay: pacingDelay,
      debugLogger: (kDebugMode && !_isTest)
          ? (msg) => debugPrint('[ZoomFileTransfer] $msg')
          : null,
    );

    bool isCancelled() =>
        _isDisposed ||
        sessionToken != _discoverySessionToken ||
        !transport.isConnected;

    try {
      // Load existing cached custom effects (repository + registry) so already-cached
      // .ZD2 binaries are not unnecessarily re-downloaded over MIDI.
      final cachedVersionsById = <String, String?>{};
      if (repo != null) {
        try {
          final persisted = await repo.loadAll();
          for (final entry in persisted) {
            final normId = CustomEffectEntry.normalizeEffectId(entry.effectId);
            cachedVersionsById[normId] = entry.version;
          }
        } catch (_) {}
      }
      for (final reg in EffectCatalogRegistry.getRegisteredCustomEffects()) {
        if (reg.isCompatibleWith(family)) {
          final normId =
              CustomEffectEntry.normalizeEffectId(reg.definition.effectId);
          cachedVersionsById.putIfAbsent(normId, () => reg.definition.version);
        }
      }

      late FlstParseResult flst;
      final stockIds = <String>{};
      final crossModelIds = <String>{};
      final cachedCustomIds = <String>{};
      final newlyCachedCustomIds = <String>{};
      final failedCustomFilenames = <String>[];
      final failedCustomEffects = <FailedCustomEffectDiscovery>[];
      final customToDownload = <FlstEffectEntry>[];
      bool anyCustomRegistered = false;

      await service.runReadSession<void>(
        (session) async {
          final flstBytes = await session.downloadFile('FLST_SEQ.ZT2');
          if (isCancelled()) return;

          flst = FlstSeqParser.parse(flstBytes);

          if (kDebugMode && !_isTest) {
            final expectedBpmId = family == DeviceFamily.zoomMs60bPlus
                ? '0x09000FF0'
                : '0x07000FF0';
            final hasBpmStock =
                EffectCatalogRegistry.isStockEffect(family, expectedBpmId);
            final hasBpmOnPedal =
                flst.installedEffectIds.contains(expectedBpmId);
            debugPrint(
              '[ZoomEffectDiscovery] Parsed FLST_SEQ.ZT2 '
              '(device=${flst.deviceName ?? "unknown"}, '
              'installed=${flst.installedEntries.length}/${flst.allEntries.length}, '
              '$expectedBpmId inStock=$hasBpmStock onPedal=$hasBpmOnPedal)',
            );
          }

          for (final entry in flst.installedEntries) {
            final normId = CustomEffectEntry.normalizeEffectId(entry.effectId);
            if (EffectCatalogRegistry.isStockEffect(family, normId)) {
              stockIds.add(normId);
              continue;
            }
            if (EffectCatalogRegistry.lookupCrossModelSibling(family, normId) !=
                null) {
              crossModelIds.add(normId);
              if (kDebugMode && !_isTest) {
                debugPrint(
                  '[ZoomEffectDiscovery] Non-stock entry (cross-model): '
                  'filename="${entry.filename}", effectId=$normId, '
                  'groupByte=0x${entry.groupByte.toRadixString(16).padLeft(2, '0')}, '
                  'groupName="${entry.groupName}", version="${entry.version}", '
                  'installed=${entry.installed}',
                );
              }
              continue;
            }

            final hasCacheHit = !forceRedownloadCustom &&
                cachedVersionsById.containsKey(normId) &&
                (entry.version.isEmpty ||
                    cachedVersionsById[normId] == null ||
                    cachedVersionsById[normId]!.isEmpty ||
                    cachedVersionsById[normId] == entry.version);
            if (hasCacheHit) {
              cachedCustomIds.add(normId);
              if (kDebugMode && !_isTest) {
                debugPrint(
                  '[ZoomEffectDiscovery] Non-stock entry (cached custom): '
                  'filename="${entry.filename}", effectId=$normId, '
                  'groupByte=0x${entry.groupByte.toRadixString(16).padLeft(2, '0')}, '
                  'groupName="${entry.groupName}", version="${entry.version}", '
                  'installed=${entry.installed}',
                );
              }
              continue;
            }

            if (kDebugMode && !_isTest) {
              debugPrint(
                '[ZoomEffectDiscovery] Non-stock entry (unmatched -> queued for .ZD2 download): '
                'filename="${entry.filename}", effectId=$normId, '
                'groupByte=0x${entry.groupByte.toRadixString(16).padLeft(2, '0')}, '
                'groupName="${entry.groupName}", version="${entry.version}", '
                'installed=${entry.installed}',
              );
            }
            customToDownload.add(entry);
          }

          for (int i = 0; i < customToDownload.length; i++) {
            if (isCancelled()) return;
            final entry = customToDownload[i];
            final entryNormId =
                CustomEffectEntry.normalizeEffectId(entry.effectId);
            _effectScanStatusMessage =
                'Reading custom effect ${i + 1}/${customToDownload.length}: ${entry.filename}...';
            notifyListeners();

            try {
              final zd2Bytes = await session.downloadFile(entry.filename);
              if (isCancelled()) return;

              final parsedZd2 = Zd2Parser.parse(
                zd2Bytes,
                sourceFilename: entry.filename,
              );
              var customEntry = CustomEffectEntry.fromParsedZd2(parsedZd2);
              if ((customEntry.version == null ||
                      customEntry.version!.isEmpty) &&
                  entry.version.isNotEmpty) {
                customEntry = customEntry.copyWith(version: entry.version);
              }

              if (repo != null) {
                await repo.upsert(customEntry);
              }
              EffectCatalogRegistry.registerCustomEffect(
                customEntry.toEffectDefinition(family),
                generation: customEntry.generation,
                notify: false,
              );
              anyCustomRegistered = true;

              final normId =
                  CustomEffectEntry.normalizeEffectId(customEntry.effectId);
              newlyCachedCustomIds.add(normId);
              cachedCustomIds.add(normId);
              cachedVersionsById[normId] = customEntry.version;
            } catch (err) {
              final conciseReason = err is ZoomFileTransferException
                  ? err.message
                  : err is Zd2ParseException
                      ? err.message
                      : err is TimeoutException
                          ? 'Timed out reading from pedal'
                          : err.toString();
              failedCustomFilenames.add(entry.filename);
              failedCustomEffects.add(FailedCustomEffectDiscovery(
                filename: entry.filename,
                effectId: entryNormId,
                reason: conciseReason,
              ));
              if (kDebugMode && !_isTest) {
                debugPrint(
                  '[ZoomEffectDiscovery] Failed reading "${entry.filename}" '
                  '(effectId=$entryNormId, group=${entry.groupName}/0x${entry.groupByte.toRadixString(16)}, '
                  'v${entry.version}): $err',
                );
              }
            }
          }
        },
        onSuppressLiveDispatch: (suppressed) {
          _suppressIncomingHardwareEvents = suppressed;
        },
        isCancelled: isCancelled,
      );

      if (isCancelled()) {
        return DeviceEffectDiscoveryResult.failure(
          'Effect scan cancelled during disconnect.',
        );
      }

      _installedEffectIds = Set<String>.unmodifiable(flst.installedEffectIds);
      _installedFlstEntries =
          List<FlstEffectEntry>.unmodifiable(flst.installedEntries);
      _discoveredStockIds = Set<String>.unmodifiable(stockIds);
      _discoveredCrossModelIds = Set<String>.unmodifiable(crossModelIds);
      _discoveredCustomIds = Set<String>.unmodifiable(cachedCustomIds);

      // Update runtime cross-model overlay (and notify catalog listeners if custom
      // effects were registered even when crossModelIds was unchanged).
      final revisionBefore = EffectCatalogRegistry.catalogRevision.value;
      EffectCatalogRegistry.setInstalledCrossModelEffects(
        family,
        crossModelIds,
      );
      if (anyCustomRegistered &&
          EffectCatalogRegistry.catalogRevision.value == revisionBefore) {
        EffectCatalogRegistry.catalogRevision.value = revisionBefore + 1;
      }

      // Immediately re-hydrate any open editor patch so newly discovered custom
      // effects upgrade from Unknown to their real name & parameters.
      if (_editor != null) {
        try {
          _editor.refreshEffectDefinitionsFromCatalog();
        } catch (_) {}
      }

      final warning = failedCustomEffects.isEmpty
          ? null
          : 'Could not read ${failedCustomEffects.length} custom effect '
              'file(s): ${failedCustomEffects.map((f) => f.summary).join('; ')}';

      final result = DeviceEffectDiscoveryResult(
        success: true,
        installedEntries: _installedFlstEntries,
        installedEffectIds: _installedEffectIds!,
        stockIds: _discoveredStockIds,
        crossModelIds: _discoveredCrossModelIds,
        cachedCustomIds: _discoveredCustomIds,
        newlyCachedCustomIds: newlyCachedCustomIds,
        failedCustomFilenames: failedCustomFilenames,
        failedCustomEffects: failedCustomEffects,
      );

      _lastEffectDiscoveryResult = result;
      _effectScanError = warning;
      _effectScanStatusMessage = null;
      _isScanningEffects = false;
      notifyListeners();
      return result;
    } catch (e) {
      if (!isCancelled()) {
        _installedEffectIds = null;
        _installedFlstEntries = const [];
        _discoveredStockIds = const {};
        _discoveredCrossModelIds = const {};
        _discoveredCustomIds = const {};
        EffectCatalogRegistry.clearInstalledCrossModelEffects(family);

        final reason = e is TimeoutException
            ? 'Pedal did not respond to onboard effect scan.'
            : e is FlstParseException
                ? e.message
                : e is ZoomFileTransferException
                    ? e.message
                    : 'Onboard effect discovery failed: $e';

        if (kDebugMode && !_isTest) {
          debugPrint('[ZoomEffectDiscovery] $reason');
        }

        final failure = DeviceEffectDiscoveryResult.failure(reason);
        _lastEffectDiscoveryResult = failure;
        _effectScanError = reason;
        _effectScanStatusMessage = null;
        _isScanningEffects = false;
        notifyListeners();
        return failure;
      }
      _isScanningEffects = false;
      _effectScanStatusMessage = null;
      notifyListeners();
      return DeviceEffectDiscoveryResult.failure('Effect scan cancelled.');
    }
  }

  /// Re-classifies already-downloaded [_installedFlstEntries] when the active
  /// Zoom family is refined after initial current-patch dump detection.
  void _reclassifyInstalledEffectsForActiveFamily() {
    if (_installedFlstEntries.isEmpty || !_activeFamily.isZoom6E) return;
    final family = _activeFamily;
    final stockIds = <String>{};
    final crossModelIds = <String>{};
    final customIds = <String>{};
    for (final entry in _installedFlstEntries) {
      final normId = CustomEffectEntry.normalizeEffectId(entry.effectId);
      if (EffectCatalogRegistry.isStockEffect(family, normId)) {
        stockIds.add(normId);
      } else if (EffectCatalogRegistry.lookupCrossModelSibling(family, normId) !=
          null) {
        crossModelIds.add(normId);
      } else {
        customIds.add(normId);
      }
    }
    _discoveredStockIds = Set<String>.unmodifiable(stockIds);
    _discoveredCrossModelIds = Set<String>.unmodifiable(crossModelIds);
    _discoveredCustomIds = Set<String>.unmodifiable(customIds);
    EffectCatalogRegistry.clearInstalledCrossModelEffects();
    EffectCatalogRegistry.setInstalledCrossModelEffects(family, crossModelIds);
  }

  /// Connects to [port], performs device identity inquiry handshake, runs
  /// read-only onboard effect discovery on Zoom pedals, and executes
  /// the protocol's initialization sequence.
  ///
  /// If [explicitFamily] is provided, automatic identity inquiry is bypassed in
  /// favor of the explicitly selected hardware profile.
  Future<void> connect(
    MidiPortDescriptor port, {
    DeviceFamily? explicitFamily,
    bool autoSyncBank = false,
    bool fetchCurrentPatch = true,
    bool autoDiscoverEffects = true,
  }) async {
    _isConnecting = true;
    _errorMessage = null;
    _activeHardwareSlotIndex = null;
    _isTunerActive = false;
    _discoverySessionToken++;
    _clearHardwareEffectInventory(notify: false);

    final preDetected = explicitFamily ?? identifyFamilyFromPort(port);
    if (preDetected != null && preDetected != DeviceFamily.unknown) {
      selectDeviceFamily(preDetected);
    } else {
      notifyListeners();
    }

    try {
      await transport.connect(port.id);
      _connectedPort = port;

      if (explicitFamily != null) {
        selectDeviceFamily(explicitFamily);
      } else {
        // Attempt Universal Identity Request handshake
        await _performIdentityHandshake(port);
      }

      // Strictly read-only onboard effect discovery on Zoom 0x6E pedals before
      // reading the active edit buffer so custom .ZD2 & cross-model effects
      // resolve immediately on the initial patch.
      final currentTransport = transport;
      final activeTransport = currentTransport is CompositeMidiTransport
          ? currentTransport.activeTransport
          : currentTransport;
      final shouldAutoDiscover = autoDiscoverEffects &&
          _activeFamily.isZoom6E &&
          transport.isConnected &&
          (activeTransport is! MockMidiTransport ||
              activeTransport.hasZoomFileTransferHandler);
      if (shouldAutoDiscover) {
        await scanInstalledEffects();
      }

      // Execute hardware initialization sequence with inter-command pacing
      // (guarantees 0x53 -> 0x50 Parameter Edit Mode -> 0x33 current slot query).
      final initSequence = _activeProtocol.buildInitSequence();
      for (final msg in initSequence) {
        await transport.send(msg);
        if (pacingDelay > Duration.zero) {
          await Future<void>.delayed(pacingDelay);
        }
      }
      _ensureBankSlotsInitialized();

      if (fetchCurrentPatch) {
        if (pacingDelay > Duration.zero) {
          await Future<void>.delayed(pacingDelay);
        }
        try {
          final request = _activeProtocol.buildRequestCurrentPatchMessage();
          bool received = false;
          try {
            final dumpMsg = await transport.sendSysExAndWait(
              request,
              responseMatcher: (m) => _activeProtocol.isCurrentPatchDump(m),
              timeout: currentPatchTimeout,
            );
            received = true;
            _autoDetectFamilyFromPatchDump(dumpMsg);
          } catch (_) {
            // First attempt timed out; retry once if still connected
          }

          if (!received && transport.isConnected) {
            if (pacingDelay > Duration.zero) {
              await Future<void>.delayed(pacingDelay);
            }
            try {
              final dumpMsg = await transport.sendSysExAndWait(
                request,
                responseMatcher: (m) => _activeProtocol.isCurrentPatchDump(m),
                timeout: currentPatchTimeout,
              );
              received = true;
              _autoDetectFamilyFromPatchDump(dumpMsg);
            } catch (_) {
              // Current patch request did not return a dump; proceed gracefully
            }
          }
        } catch (_) {}
      }

      if (autoSyncBank && !_isSyncingBank) {
        if (pacingDelay > Duration.zero) {
          await Future<void>.delayed(pacingDelay);
        }
        unawaited(syncDeviceBank());
      }
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _clearHardwareEffectInventory(notify: false);
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
    _discoverySessionToken++;
    _activeHardwareSlotIndex = null;
    _isTunerActive = false;
    _errorMessage = null;
    _clearHardwareEffectInventory(notify: false);
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
          name: 'Slot ${_activeFamily.formatHardwarePatchLabel(i)}',
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
          MidiMessage? response;
          try {
            response = await transport.sendSysExAndWait(
              request,
              responseMatcher: (m) =>
                  activeProto.isSlotPatchDump(m) &&
                  activeProto.extractSlotIndex(m) == i,
              timeout: perSlotTimeout,
            );
          } catch (_) {
            // First attempt timed out; retry once if still connected and not cancelled
            if (!_cancelBankSync && transport.isConnected) {
              if (pacingDelay > Duration.zero) {
                await Future<void>.delayed(pacingDelay);
              }
              response = await transport.sendSysExAndWait(
                request,
                responseMatcher: (m) =>
                    activeProto.isSlotPatchDump(m) &&
                    activeProto.extractSlotIndex(m) == i,
                timeout: perSlotTimeout,
              );
            }
          }

          if (response != null) {
            final decoded = activeProto.decodePatch(response);
            _bankSlots[i] = BankSlotDescriptor(
              index: i,
              name: decoded.name.trim().isNotEmpty
                  ? decoded.name.trim()
                  : 'Slot ${_activeFamily.formatHardwarePatchLabel(i)}',
              deviceFamily: _activeFamily,
              isLoaded: true,
              isEmpty: decoded.slots.isEmpty,
              patch: decoded,
            );
            if (_activeHardwareSlotIndex == null && _editor != null) {
              final activePatch = _editor.patch as Patch?;
              if (activePatch != null &&
                  (Patch.isSignatureMatch(activePatch, decoded, matchParameters: true) ||
                   Patch.isSignatureMatch(activePatch, decoded, matchParameters: false))) {
                setActiveHardwareSlotIndex(i);
              }
            }
          }
        } catch (_) {
          // If a slot read times out even after retry, record slot as loaded but empty
          if (!_bankSlots[i].isLoaded) {
            _bankSlots[i] = BankSlotDescriptor(
              index: i,
              name: 'Slot ${_activeFamily.formatHardwarePatchLabel(i)}',
              deviceFamily: _activeFamily,
              isLoaded: true,
              isEmpty: true,
            );
          }
        }

        // Incremental notification and pacing delay
        notifyListeners();
        if (pacingDelay > Duration.zero) {
          await Future<void>.delayed(pacingDelay);
        } else {
          await Future<void>.value();
        }
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
          name: 'Slot ${_activeFamily.formatHardwarePatchLabel(i)}',
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
        final portDetected = identifyFamilyFromPortName(port.name);
        if (portDetected != null &&
            portDetected.isZoomFour &&
            !detected.isZoomFour) {
          selectDeviceFamily(portDetected);
          return;
        }
        if (detected != DeviceFamily.unknown) {
          selectDeviceFamily(detected);
          return;
        }
        if (portDetected != null && portDetected != DeviceFamily.unknown) {
          selectDeviceFamily(portDetected);
          return;
        }
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
    final portFamily = identifyFamilyFromPort(port);
    if (portFamily != null && portFamily != DeviceFamily.unknown) {
      selectDeviceFamily(portFamily);
    }
    // Otherwise keep current activeFamily
  }

  /// Inspects an incoming current-patch dump and switches [activeFamily] to
  /// `DeviceGeneration.zoomFour` before bank sync if the PTCF target identifies
  /// a Four-series pedal while a non-Four family was active.
  void _autoDetectFamilyFromPatchDump(MidiMessage dumpMsg) {
    try {
      final decoded = _activeProtocol.decodePatch(dumpMsg);
      if (decoded.deviceFamily.isZoomFour && !_activeFamily.isZoomFour) {
        selectDeviceFamily(decoded.deviceFamily);
        _ensureBankSlotsInitialized();
        _reclassifyInstalledEffectsForActiveFamily();
      }
    } catch (_) {}
  }

  /// Routes unsolicited incoming MIDI events from hardware to registered editor controllers.
  void _handleIncomingHardwareEvent(MidiMessage message) {
    // Suppress normal live SysEx dispatch while an exclusive PC-Mode 0x60 file
    // transfer session is active so file chunks are never parsed as patch edits.
    if (_suppressIncomingHardwareEvents) {
      return;
    }
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
                : 'Slot ${_activeFamily.formatHardwarePatchLabel(slotIndex)}',
            patch: decoded,
          );
          if (_activeHardwareSlotIndex == null && _editor != null) {
            final activePatch = _editor.patch as Patch?;
            if (activePatch != null &&
                (Patch.isSignatureMatch(activePatch, decoded, matchParameters: true) ||
                 Patch.isSignatureMatch(activePatch, decoded, matchParameters: false))) {
              setActiveHardwareSlotIndex(slotIndex);
            }
          }
        } catch (_) {}
      }
      return;
    }

    // Hardware Tuner state feedback (CC #74 or SysEx 64 20 00 64 0B on Zoom; PC 37 on Line 6)
    if (_activeProtocol.isTunerStateChange(message)) {
      final tunerActive = _activeProtocol.parseTunerStateChange(message);
      if (tunerActive != null && _isTunerActive != tunerActive) {
        _isTunerActive = tunerActive;
        notifyListeners();
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
        _isTunerActive = false;
        _incomingBankMsb = 0;
        _incomingBankLsb = slotIndex ~/ 10;
        setActiveHardwareSlotIndex(
          slotIndex,
          syncEditorPatchProgramNumber: false,
        );
        _hardwareUpdateHandler?.call(programNumber: slotIndex);
      }
      return;
    }

    // Program Change: combined with tracked Bank Select (10 patches/bank on MS Plus; 1..36 on Bass POD Pro)
    if (message.isProgramChange) {
      _isTunerActive = false;
      final prog = message.data.length > 1 ? (message.data[1] & 0x7F) : 0;
      final int slotIndex;
      if (_activeFamily.isLine6BassPodPro) {
        slotIndex = prog > 0 ? (prog - 1).clamp(0, _activeFamily.totalMemorySlots - 1) : 0;
      } else {
        slotIndex = (currentIncomingBank * 10) + prog;
      }
      setActiveHardwareSlotIndex(
        slotIndex,
        syncEditorPatchProgramNumber: false,
      );
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

    // Real-time Right-Output (R-Out) routing tap change from pedal (Zoom MS+ 64 20 00 64 04)
    if (_activeProtocol.isRightOutputTapChange(message)) {
      final tapCode = _activeProtocol.parseRightOutputTapChange(message);
      if (tapCode != null) {
        _hardwareUpdateHandler?.call(rightOutputTapCode: tapCode);
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
        if (_activeHardwareSlotIndex == null) {
          final matched = findMatchingBankSlot(decoded);
          if (matched != null) {
            setActiveHardwareSlotIndex(
              matched,
              syncEditorPatchProgramNumber: false,
            );
          }
        }
        final resolvedPatch = _activeHardwareSlotIndex != null
            ? decoded.copyWith(programNumber: _activeHardwareSlotIndex)
            : decoded;
        if (_activeHardwareSlotIndex != null &&
            _activeHardwareSlotIndex! >= 0 &&
            _activeHardwareSlotIndex! < _bankSlots.length) {
          updateBankSlot(
            _activeHardwareSlotIndex!,
            patchName: resolvedPatch.name.trim().isNotEmpty
                ? resolvedPatch.name.trim()
                : 'Slot ${_activeFamily.formatHardwarePatchLabel(_activeHardwareSlotIndex!)}',
            patch: resolvedPatch,
          );
        }
        _hardwareUpdateHandler?.call(patch: resolvedPatch);
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
      case DeviceFamily.zoomB1xFour:
      case DeviceFamily.zoomB1Four:
      case DeviceFamily.zoomG1xFour:
      case DeviceFamily.zoomG1Four:
        return ZoomFourProtocol.forFamily(family);
      case DeviceFamily.zoomMs50gPlus:
      case DeviceFamily.zoomMs60bPlus:
      case DeviceFamily.zoomMs70cdrPlus:
      case DeviceFamily.zoomMs200dPlus:
      case DeviceFamily.unknown:
        return ZoomMsPlusProtocol(defaultFamily: family);
    }
  }
}
