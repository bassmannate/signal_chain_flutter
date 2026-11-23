import 'dart:async';
import 'dart:typed_data';

import '../../protocols/zoom_file_transfer_service.dart';
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

  // Optional simulated read-only Zoom 0x60 virtual filesystem (off by default
  // so existing mock-transport tests stay fast and unaffected).
  bool _virtualZoomFilesEnabled = false;

  /// When true, signals [DeviceConnectionController.connect] to exercise the
  /// Zoom `0x60` discovery handshake even without virtual files so timeout
  /// recovery paths can be tested deterministically.
  bool simulateZoomFileTransferTimeout = false;

  int _virtualZoomModelId = ZoomFileTransferService.defaultModelId;
  int _virtualZoomChunkSize = ZoomFileTransferService.defaultChunkSize;
  final Map<String, Uint8List> _virtualZoomFiles = {};
  final List<String> _virtualZoomDownloadedFiles = [];
  Uint8List? _openVirtualFileBytes;
  int _openVirtualFileOffset = 0;
  bool _pendingVirtualOpenPoll = false;
  bool _pendingVirtualChunkRead = false;

  /// Returns true when this mock transport is configured to respond to (or
  /// explicitly simulate timeouts for) Zoom `0x60` read-only file transfers.
  bool get hasZoomFileTransferHandler {
    if (_virtualZoomFilesEnabled || simulateZoomFileTransferTimeout) {
      return true;
    }
    final probe = ZoomFileTransferService.buildOpenForReadMessage(
      'FLST_SEQ.ZT2',
      modelId: _virtualZoomModelId,
    );
    return _responders.any((entry) => entry.matcher(probe));
  }

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

  /// Configures a simulated read-only Zoom `0x60` virtual filesystem for
  /// `FLST_SEQ.ZT2` and `.ZD2` download tests.
  ///
  /// Filenames are matched case-insensitively. Pass an empty map or call
  /// [clearVirtualZoomFiles] to disable virtual file responses.
  void setVirtualZoomFiles(
    Map<String, Uint8List> files, {
    int modelId = ZoomFileTransferService.defaultModelId,
    int chunkSize = ZoomFileTransferService.defaultChunkSize,
  }) {
    _virtualZoomFiles.clear();
    for (final entry in files.entries) {
      _virtualZoomFiles[entry.key.trim().toUpperCase()] = entry.value;
    }
    _virtualZoomModelId = modelId & 0x7F;
    _virtualZoomChunkSize = chunkSize > 0
        ? chunkSize
        : ZoomFileTransferService.defaultChunkSize;
    _virtualZoomFilesEnabled = _virtualZoomFiles.isNotEmpty;
    _resetVirtualFileCursor();
  }

  /// Disables simulated Zoom `0x60` virtual file responses and clears history.
  void clearVirtualZoomFiles() {
    _virtualZoomFiles.clear();
    _virtualZoomFilesEnabled = false;
    _virtualZoomDownloadedFiles.clear();
    _resetVirtualFileCursor();
  }

  /// Ordered list of virtual filenames opened for download via `0x60 0x20 0x02`.
  List<String> get virtualZoomDownloadedFiles =>
      List.unmodifiable(_virtualZoomDownloadedFiles);

  /// Clears [virtualZoomDownloadedFiles] without removing virtual files.
  void clearVirtualZoomDownloadHistory() {
    _virtualZoomDownloadedFiles.clear();
  }

  void _resetVirtualFileCursor() {
    _openVirtualFileBytes = null;
    _openVirtualFileOffset = 0;
    _pendingVirtualOpenPoll = false;
    _pendingVirtualChunkRead = false;
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
    _resetVirtualFileCursor();
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPort = null;
    _resetVirtualFileCursor();
  }

  @override
  Future<void> send(MidiMessage message) async {
    if (!_isConnected) {
      throw StateError('Cannot send message: MockMidiTransport is not connected.');
    }
    _sentMessages.add(message);

    // Optional simulated Zoom read-only 0x60 filesystem responder
    if (_virtualZoomFilesEnabled) {
      final virtualReply = _handleVirtualZoomFileRequest(message);
      if (virtualReply != null) {
        scheduleMicrotask(() {
          if (!_messageController.isClosed) {
            _messageController.add(virtualReply);
          }
        });
      }
    }

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

  MidiMessage? _handleVirtualZoomFileRequest(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx || data.length < 6) return null;
    if (data[1] != ZoomFileTransferService.manufacturerId ||
        data[2] != 0x00 ||
        data[3] != _virtualZoomModelId) {
      return null;
    }

    final opcode = data[4];
    if (opcode == ZoomFileTransferService.cmdPcModeEnable) {
      _resetVirtualFileCursor();
      return MidiMessage.sysEx([
        ZoomFileTransferService.manufacturerId,
        0x00,
        _virtualZoomModelId,
        0x00,
        0x00,
      ]);
    }
    if (opcode == ZoomFileTransferService.cmdPcModeDisable) {
      _resetVirtualFileCursor();
      return MidiMessage.sysEx([
        ZoomFileTransferService.manufacturerId,
        0x00,
        _virtualZoomModelId,
        0x00,
        0x00,
      ]);
    }
    if (opcode != ZoomFileTransferService.cmdFileTransfer || data.length < 7) {
      return null;
    }

    final subCmd = data[5];
    switch (subCmd) {
      case ZoomFileTransferService.subCmdOpen:
        // Open file for read: F0 52 00 <modelId> 60 20 02 <9x 00> <ASCII filename> 00 F7
        _resetVirtualFileCursor();
        if (data.length > 16) {
          final filenameBytes = data.sublist(16, data.length - 1);
          final name = ZoomFileTransferService.decodeOpenFilename(
            filenameBytes,
          ).toUpperCase();
          _virtualZoomDownloadedFiles.add(name);
          _openVirtualFileBytes = _virtualZoomFiles[name];
          _openVirtualFileOffset = 0;
          _pendingVirtualOpenPoll = true;
        }
        return MidiMessage.sysEx([
          ZoomFileTransferService.manufacturerId,
          0x00,
          _virtualZoomModelId,
          ZoomFileTransferService.cmdFileTransfer,
          0x00,
        ]);

      case ZoomFileTransferService.subCmdReadChunk:
        _pendingVirtualChunkRead = true;
        return MidiMessage.sysEx([
          ZoomFileTransferService.manufacturerId,
          0x00,
          _virtualZoomModelId,
          ZoomFileTransferService.cmdFileTransfer,
          0x00,
        ]);

      case ZoomFileTransferService.subCmdPoll:
        if (_pendingVirtualOpenPoll) {
          _pendingVirtualOpenPoll = false;
          if (_openVirtualFileBytes == null) {
            // Match real MS-60B+ hardware rejection: 60 03 7F 7F 7F 7F 0F (-1)
            return ZoomFileTransferService.buildErrorReplyMessage(
              code: -1,
              modelId: _virtualZoomModelId,
            );
          }
          // Match real MS-60B+ hardware open-poll status reply:
          // F0 52 00 6E 60 03 00 00 00 00 00 F7 (code 0 = OK)
          return ZoomFileTransferService.buildStatusReplyMessage(
            code: 0,
            modelId: _virtualZoomModelId,
          );
        }
        if (_pendingVirtualChunkRead) {
          _pendingVirtualChunkRead = false;
          final fileBytes = _openVirtualFileBytes;
          if (fileBytes == null || _openVirtualFileOffset >= fileBytes.length) {
            return ZoomFileTransferService.encodeChunkResponseMessage(
              Uint8List(0),
              modelId: _virtualZoomModelId,
            );
          }
          final end = (_openVirtualFileOffset + _virtualZoomChunkSize)
              .clamp(0, fileBytes.length);
          final chunk = Uint8List.sublistView(
            fileBytes,
            _openVirtualFileOffset,
            end,
          );
          _openVirtualFileOffset = end;
          return ZoomFileTransferService.encodeChunkResponseMessage(
            chunk,
            modelId: _virtualZoomModelId,
          );
        }
        return MidiMessage.sysEx([
          ZoomFileTransferService.manufacturerId,
          0x00,
          _virtualZoomModelId,
          ZoomFileTransferService.cmdFileTransfer,
          0x00,
        ]);

      case ZoomFileTransferService.subCmdCloseHandle:
        _resetVirtualFileCursor();
        return ZoomFileTransferService.buildStatusReplyMessage(
          code: 0,
          modelId: _virtualZoomModelId,
        );

      case ZoomFileTransferService.subCmdCloseFinalize:
        // Real MS-60B+ hardware does not send a reply to 60 09.
        _resetVirtualFileCursor();
        return null;

      case ZoomFileTransferService.subCmdCheckClose:
        _resetVirtualFileCursor();
        return MidiMessage.sysEx([
          ZoomFileTransferService.manufacturerId,
          0x00,
          _virtualZoomModelId,
          ZoomFileTransferService.cmdFileTransfer,
          0x00,
        ]);

      default:
        return null;
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

