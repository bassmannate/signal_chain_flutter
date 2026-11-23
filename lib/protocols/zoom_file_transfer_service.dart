import 'dart:async';
import 'dart:typed_data';

import '../core/midi/midi_message.dart';
import '../core/midi/midi_transport.dart';
import '../core/zd2/flst_seq_parser.dart';
import 'sysex_codec.dart';
import 'zoom_ms_plus_protocol.dart';

/// Exception thrown when a strictly read-only Zoom `0x60` file transfer fails,
/// times out, is cancelled, or fails CRC verification.
class ZoomFileTransferException implements Exception {
  final String message;

  const ZoomFileTransferException(this.message);

  @override
  String toString() => 'ZoomFileTransferException: $message';
}

/// Immutable diagnostic record for a custom `.ZD2` file that could not be
/// downloaded or parsed during onboard hardware effect discovery.
class FailedCustomEffectDiscovery {
  /// Filename reported by `FLST_SEQ.ZT2` (e.g., `'BPM_MDL.ZD2'`).
  final String filename;

  /// Normalized uppercase `'0xXXXXXXXX'` effect ID reported by `FLST_SEQ.ZT2`.
  final String effectId;

  /// Concise human-readable reason for the failure.
  final String reason;

  const FailedCustomEffectDiscovery({
    required this.filename,
    required this.effectId,
    required this.reason,
  });

  /// Concise one-line display summary.
  String get summary => '$filename ($effectId): $reason';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FailedCustomEffectDiscovery &&
          runtimeType == other.runtimeType &&
          filename == other.filename &&
          effectId == other.effectId &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(filename, effectId, reason);

  @override
  String toString() => 'FailedCustomEffectDiscovery($summary)';
}

/// Typed outcome of a read-only onboard hardware effect discovery pass
/// (`FLST_SEQ.ZT2` + uncached custom `.ZD2` downloads).
class DeviceEffectDiscoveryResult {
  /// True when `FLST_SEQ.ZT2` was downloaded and parsed successfully.
  final bool success;

  /// Human-readable reason when [success] is false (or `null` on success).
  final String? failureReason;

  /// Authoritative installed `FLST_SEQ.ZT2` entries read from the pedal.
  final List<FlstEffectEntry> installedEntries;

  /// Normalized uppercase `'0xXXXXXXXX'` effect IDs installed on the pedal.
  final Set<String> installedEffectIds;

  /// Installed effect IDs resolved from the active pedal's stock catalog (Tier 1).
  final Set<String> stockIds;

  /// Installed effect IDs resolved from sibling cross-model catalogs (Tier 2).
  final Set<String> crossModelIds;

  /// Installed custom `.ZD2` effect IDs (both previously cached and newly cached).
  final Set<String> cachedCustomIds;

  /// Custom `.ZD2` effect IDs newly downloaded and persisted during this scan.
  final Set<String> newlyCachedCustomIds;

  /// Filenames of uncached custom `.ZD2` files that failed to download or parse.
  final List<String> failedCustomFilenames;

  /// Detailed records (`filename`, `effectId`, `reason`) for failed custom `.ZD2` files.
  final List<FailedCustomEffectDiscovery> failedCustomEffects;

  DeviceEffectDiscoveryResult({
    required this.success,
    this.failureReason,
    List<FlstEffectEntry> installedEntries = const [],
    Set<String> installedEffectIds = const {},
    Set<String> stockIds = const {},
    Set<String> crossModelIds = const {},
    Set<String> cachedCustomIds = const {},
    Set<String> newlyCachedCustomIds = const {},
    List<String> failedCustomFilenames = const [],
    List<FailedCustomEffectDiscovery> failedCustomEffects = const [],
  })  : installedEntries = List<FlstEffectEntry>.unmodifiable(installedEntries),
        installedEffectIds = Set<String>.unmodifiable(installedEffectIds),
        stockIds = Set<String>.unmodifiable(stockIds),
        crossModelIds = Set<String>.unmodifiable(crossModelIds),
        cachedCustomIds = Set<String>.unmodifiable(cachedCustomIds),
        newlyCachedCustomIds = Set<String>.unmodifiable(newlyCachedCustomIds),
        failedCustomFilenames =
            List<String>.unmodifiable(failedCustomFilenames),
        failedCustomEffects =
            List<FailedCustomEffectDiscovery>.unmodifiable(failedCustomEffects);

  factory DeviceEffectDiscoveryResult.failure(String reason) {
    return DeviceEffectDiscoveryResult(
      success: false,
      failureReason: reason,
    );
  }
}

/// Active strictly read-only PC-Mode session handle passed to the callback of
/// [ZoomFileTransferService.runReadSession].
///
/// Allows downloading `FLST_SEQ.ZT2` and multiple uncached `.ZD2` files within
/// a single PC-Mode (`0x52` ... `0x53`) transaction to avoid repeated mode switches.
class ZoomReadSession {
  final ZoomFileTransferService _service;
  final bool Function()? _isCancelled;
  bool _closed = false;

  ZoomReadSession._(this._service, this._isCancelled);

  void _ensureActive() {
    if (_closed) {
      throw const ZoomFileTransferException(
        'ZoomReadSession is already closed.',
      );
    }
    if (_isCancelled?.call() == true || !_service.transport.isConnected) {
      throw const ZoomFileTransferException(
        'File transfer cancelled because the device disconnected.',
      );
    }
  }

  /// Downloads a single file (e.g., `'FLST_SEQ.ZT2'` or `'MY_NAM.ZD2'`) from the
  /// connected Zoom pedal in read-only mode.
  ///
  /// Always closes the opened file handle (`0x60 0x21 0x40 ...` + `0x60 0x09`)
  /// in `finally` even if a chunk read times out or fails CRC verification.
  Future<Uint8List> downloadFile(String filename) async {
    _ensureActive();
    final tail = ZoomFileTransferService.basename(filename);
    if (tail.isEmpty) {
      throw const ZoomFileTransferException('Filename cannot be empty.');
    }

    final openRequest = ZoomFileTransferService.buildOpenForReadMessage(
      tail,
      modelId: _service.modelId,
    );

    bool openDispatched = false;
    bool openSucceeded = false;
    MidiMessage? lastReply;

    try {
      // Drain any late/stale SysEx frame before issuing openForRead so
      // consecutive downloads in one session never drift off by one reply.
      await _service._drainStaleReplies();
      _ensureActive();

      // 1. Open file for read:
      //    F0 52 00 <modelId> 60 20 02 <9x 00> <ASCII filename> 00 F7
      //    Consume immediate ACK (e.g. 60 00 ...).
      openDispatched = true;
      _service._logControl('TX open("$tail")', openRequest);
      lastReply = await _service._sendAndAwaitZoomReply(
        openRequest,
        timeout: _service.packetTimeout,
        isCancelled: _isCancelled,
      );
      _service._logControl('RX open("$tail")', lastReply);
      openSucceeded = true;

      final openErr = ZoomFileTransferService.parseErrorReply(
        lastReply,
        modelId: _service.modelId,
      );
      if (openErr != null) {
        final msg =
            '${openErr.description} while opening "$tail". '
            'Reply: ${ZoomFileTransferService.formatSysExSummary(lastReply)}';
        _service._logMessage('ERR $msg');
        throw ZoomFileTransferException(msg);
      }

      _ensureActive();

      // 2. Poll open result ONCE:
      //    F0 52 00 <modelId> 60 05 00 F7 -> consumes open status (60 04 20 ... or 60 03 error).
      final openPollReq =
          ZoomFileTransferService.buildPollMessage(modelId: _service.modelId);
      _service._logControl('TX open-poll("$tail")', openPollReq);
      lastReply = await _service._sendAndAwaitZoomReply(
        openPollReq,
        timeout: _service.packetTimeout,
        isCancelled: _isCancelled,
      );
      _service._logControl('RX open-poll("$tail")', lastReply);

      final pollErr = ZoomFileTransferService.parseErrorReply(
        lastReply,
        modelId: _service.modelId,
      );
      if (pollErr != null) {
        final msg =
            '${pollErr.description} for "$tail". '
            'Reply: ${ZoomFileTransferService.formatSysExSummary(lastReply)}';
        _service._logMessage('ERR $msg');
        throw ZoomFileTransferException(msg);
      }

      final buffer = BytesBuilder(copy: false);
      int chunkIndex = 0;

      // 3. Chunk read loop (strict 1-to-1 request/reply lockstep):
      //    a) 60 22 14 2F 60 00 0C 00 04 00 00 00 -> consume immediate ACK (60 00 ...)
      //    b) 60 05 00 -> read 60 04 22 ... data chunk (or EOF / 60 03 error)
      while (chunkIndex < _service.maxChunksPerFile) {
        _ensureActive();

        // a) Request next 512-byte chunk & consume immediate ACK
        lastReply = await _service._sendAndAwaitZoomReply(
          ZoomFileTransferService.buildReadChunkRequestMessage(
            modelId: _service.modelId,
          ),
          timeout: _service.packetTimeout,
          isCancelled: _isCancelled,
        );
        final readAckErr = ZoomFileTransferService.parseErrorReply(
          lastReply,
          modelId: _service.modelId,
        );
        if (readAckErr != null) {
          final msg =
              '${readAckErr.description} requesting chunk $chunkIndex of "$tail". '
              'Reply: ${ZoomFileTransferService.formatSysExSummary(lastReply)}';
          _service._logMessage('ERR $msg');
          throw ZoomFileTransferException(msg);
        }

        _ensureActive();

        // b) Pull chunk payload: F0 52 00 <modelId> 60 05 00 F7
        final chunkReply = await _service._sendAndAwaitZoomReply(
          ZoomFileTransferService.buildPollMessage(modelId: _service.modelId),
          timeout: _service.packetTimeout,
          isCancelled: _isCancelled,
        );
        lastReply = chunkReply;

        final chunkErr = ZoomFileTransferService.parseErrorReply(
          chunkReply,
          modelId: _service.modelId,
        );
        if (chunkErr != null) {
          final msg =
              '${chunkErr.description} reading chunk $chunkIndex of "$tail". '
              'Reply: ${ZoomFileTransferService.formatSysExSummary(chunkReply)}';
          _service._logMessage('ERR $msg');
          throw ZoomFileTransferException(msg);
        }

        final decoded = ZoomFileTransferService.decodeChunkResponseMessage(
          chunkReply,
          modelId: _service.modelId,
          filename: tail,
          chunkIndex: chunkIndex,
        );

        if (decoded.isEof) {
          _service._logControl(
            'RX EOF("$tail" after $chunkIndex chunks, ${buffer.length} bytes)',
            chunkReply,
          );
          break;
        }

        buffer.add(decoded.bytes);
        chunkIndex++;
      }

      if (chunkIndex >= _service.maxChunksPerFile) {
        final msg =
            'Aborted reading "$tail": exceeded maximum chunk limit '
            '(${_service.maxChunksPerFile} chunks). '
            'Last reply: ${ZoomFileTransferService.formatSysExSummary(lastReply)}';
        _service._logMessage('ERR $msg');
        throw ZoomFileTransferException(msg);
      }

      final bytes = buffer.toBytes();
      if (bytes.isEmpty) {
        final msg =
            'File "$tail" returned 0 bytes (not found or unreadable on pedal). '
            'Last reply: ${ZoomFileTransferService.formatSysExSummary(lastReply)}';
        _service._logMessage('ERR $msg');
        throw ZoomFileTransferException(msg);
      }
      return bytes;
    } finally {
      if (openDispatched && _service.transport.isConnected) {
        await _service._closeOpenFileHandle(
          filename: tail,
          awaitReplies: openSucceeded,
        );
      }
    }
  }
}

/// Strictly READ-ONLY Zoom USB-MIDI `0x60` file transfer client for Zoom MS+
/// and Zoom Four (`0x6E` family) pedals.
///
/// Verified against real Zoom MS-60B+ hardware captures and `mungewell/zoom-zt2`:
/// - Enter PC Mode: `F0 52 00 <modelId> 52 F7`
/// - Open file for read (9 zero bytes + plain ASCII filename + single `0x00`):
///   `F0 52 00 <modelId> 60 20 02 00 00 00 00 00 00 00 00 00 <ASCII> 00 F7`
///   followed by one open-status poll: `F0 52 00 <modelId> 60 05 00 F7` -> `60 04 20 ...`
/// - Chunk loop:
///   1. `F0 52 00 <modelId> 60 22 14 2F 60 00 0C 00 04 00 00 00 F7` -> consume ACK (`60 00 ...`)
///   2. `F0 52 00 <modelId> 60 05 00 F7` -> receives `60 04 22 01 00` data block:
///      - `unpackedLength = (frame[10] * 128) + frame[9]`
///      - 7-bit packed payload at `frame[11 .. frame.length - 7]` unpacked via [SysexCodec.unpack7BitTo8Bit]
///      - 5-byte inverted CRC32 verified at `frame[frame.length - 6 .. frame.length - 2]`
///   - Stops on `frame[5] != 0x04` or `unpackedLength == 0` (EOF).
/// - Close open file handle (`finally`):
///   1. `F0 52 00 <modelId> 60 21 40 00 00 00 00 F7`
///   2. `F0 52 00 <modelId> 60 09 F7`
/// - Exit PC Mode & restore Parameter Edit Mode (`finally`):
///   1. `F0 52 00 <modelId> 53 F7`
///   2. `F0 52 00 <modelId> 50 F7`
///
/// Write/upload/delete operations are intentionally NOT implemented.
class ZoomFileTransferService {
  static const int manufacturerId = ZoomMsPlusProtocol.manufacturerId; // 0x52
  static const int defaultModelId = ZoomMsPlusProtocol.familyIdByte; // 0x6E

  static const int cmdParameterEditEnable =
      ZoomMsPlusProtocol.cmdParameterEditEnable; // 0x50
  static const int cmdPcModeEnable = ZoomMsPlusProtocol.cmdPcModeEnable; // 0x52
  static const int cmdPcModeDisable =
      ZoomMsPlusProtocol.cmdPcModeDisable; // 0x53
  static const int cmdFileTransfer = 0x60;

  static const int subCmdStatus = 0x03;
  static const int subCmdError = subCmdStatus;
  static const int subCmdDataChunk = 0x04;
  static const int subCmdPoll = 0x05;
  static const int subCmdCloseFinalize = 0x09;
  static const int subCmdOpen = 0x20;
  static const int subCmdCloseHandle = 0x21;
  static const int subCmdReadChunk = 0x22;
  static const int subCmdCheckOpen = 0x25;
  static const int subCmdCheckClose = 0x27;

  static const int defaultChunkSize = 512;
  static const int defaultMaxChunksPerFile = 2048;

  final MidiTransport transport;
  final int modelId;
  final Duration packetTimeout;
  final Duration pcModeAckTimeout;
  final Duration closeAckTimeout;
  final Duration pacingDelay;
  final Duration staleDrainDuration;
  final int maxChunksPerFile;

  /// Optional debug logger receiving concise control-frame traces (open, poll,
  /// EOF, close, and error frames; never full 603-byte data chunks).
  final void Function(String message)? debugLogger;

  const ZoomFileTransferService({
    required this.transport,
    this.modelId = defaultModelId,
    this.packetTimeout = const Duration(milliseconds: 1200),
    this.pcModeAckTimeout = const Duration(milliseconds: 300),
    this.closeAckTimeout = const Duration(milliseconds: 250),
    this.pacingDelay = Duration.zero,
    this.staleDrainDuration = Duration.zero,
    this.maxChunksPerFile = defaultMaxChunksPerFile,
    this.debugLogger,
  });

  void _logMessage(String message) {
    debugLogger?.call(message);
  }

  void _logControl(String label, MidiMessage? message) {
    final logger = debugLogger;
    if (logger == null) return;
    logger('$label: ${formatSysExSummary(message)}');
  }

  /// Extracts the filename component without any directory path prefix.
  static String basename(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }

  /// Builds `F0 52 00 <modelId> 52 F7` (Enter PC Mode).
  static MidiMessage buildPcModeEnableMessage({int modelId = defaultModelId}) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdPcModeEnable,
    ]);
  }

  /// Builds `F0 52 00 <modelId> 53 F7` (Exit PC Mode).
  static MidiMessage buildPcModeDisableMessage({int modelId = defaultModelId}) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdPcModeDisable,
    ]);
  }

  /// Builds `F0 52 00 <modelId> 50 F7` (Re-enable Parameter Edit Mode).
  static MidiMessage buildParameterEditEnableMessage({
    int modelId = defaultModelId,
  }) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdParameterEditEnable,
    ]);
  }

  /// Builds the `0x60 0x20 0x02` read-only file-open SysEx command:
  /// `F0 52 00 <modelId> 60 20 02 <9x 00> <ASCII bytes> 00 F7`.
  static MidiMessage buildOpenForReadMessage(
    String filename, {
    int modelId = defaultModelId,
  }) {
    final tail = basename(filename);
    final payload = <int>[
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdOpen,
      0x02,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    for (final unit in tail.codeUnits) {
      payload.add(unit & 0x7F);
    }
    payload.add(0x00);
    return MidiMessage.sysEx(payload);
  }

  /// Builds `F0 52 00 <modelId> 60 05 00 F7` (Poll / pull file transfer status or chunk).
  static MidiMessage buildPollMessage({int modelId = defaultModelId}) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdPoll,
      0x00,
    ]);
  }

  /// Builds `F0 52 00 <modelId> 60 22 14 2F 60 00 0C 00 04 00 00 00 F7`
  /// (Request next 512-byte chunk from opened read handle).
  static MidiMessage buildReadChunkRequestMessage({
    int modelId = defaultModelId,
  }) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdReadChunk,
      0x14,
      0x2F,
      0x60,
      0x00,
      0x0C,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
    ]);
  }

  /// Builds `F0 52 00 <modelId> 60 21 40 00 00 00 00 F7` (Close file handle step 1).
  static MidiMessage buildCloseHandleMessage({int modelId = defaultModelId}) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdCloseHandle,
      0x40,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
  }

  /// Builds `F0 52 00 <modelId> 60 09 F7` (Close file handle finalize step 2).
  static MidiMessage buildCloseFinalizeMessage({int modelId = defaultModelId}) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdCloseFinalize,
    ]);
  }

  /// Builds `F0 52 00 <modelId> 60 27 F7` (Close file-check handle).
  static MidiMessage buildFileCheckCloseMessage({
    int modelId = defaultModelId,
  }) {
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdCheckClose,
    ]);
  }

  /// Decodes a NUL-terminated ASCII filename (`<ASCII bytes> 00`) from an
  /// outgoing `0x60 0x20 0x02` or `0x60 0x25` packet.
  static String decodeOpenFilename(List<int> bytes) {
    final chars = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x00) break;
      if (b >= 0x20 && b <= 0x7E) {
        chars.add(b);
      }
    }
    return String.fromCharCodes(chars).trim();
  }

  /// Parses a Zoom `0x60 0x03` file-operation status SysEx reply
  /// (`F0 52 00 <modelId> 60 03 <5-byte 7-bit signed int32> F7`).
  ///
  /// Returns the decoded signed 32-bit status code (`0` = OK/success,
  /// `-1` / `7F 7F 7F 7F 0F` = not found / not readable, etc.), or `null` when
  /// [message] is not a `0x60 0x03` status reply.
  static int? parseStatusReply(
    MidiMessage message, {
    int modelId = defaultModelId,
  }) {
    final data = message.data;
    if (!message.isSysEx || data.length < 12) return null;
    if (data[1] != manufacturerId ||
        data[2] != 0x00 ||
        data[3] != (modelId & 0x7F) ||
        data[4] != cmdFileTransfer ||
        data[5] != subCmdStatus) {
      return null;
    }

    final raw = (data[6] & 0x7F) |
        ((data[7] & 0x7F) << 7) |
        ((data[8] & 0x7F) << 14) |
        ((data[9] & 0x7F) << 21) |
        ((data[10] & 0x0F) << 28);
    return raw.toSigned(32);
  }

  /// Parses a Zoom `0x60 0x03` status reply and returns an error record ONLY
  /// when the status code is non-zero (e.g., `-1` / `7F 7F 7F 7F 0F`).
  ///
  /// Returns `null` when [message] is not a `0x60 0x03` status reply OR when
  /// the status code is `0` (`F0 52 00 <modelId> 60 03 00 00 00 00 00 F7` = OK).
  static ({int code, String description})? parseErrorReply(
    MidiMessage message, {
    int modelId = defaultModelId,
  }) {
    final code = parseStatusReply(message, modelId: modelId);
    if (code == null || code == 0) return null;

    final desc = code == -1
        ? 'Pedal rejected open/read (code -1 / not readable)'
        : 'Pedal rejected open/read (code $code)';
    return (code: code, description: desc);
  }

  /// Builds a Zoom `0x60 0x03` status reply frame (`0` = `00 00 00 00 00` OK,
  /// `-1` = `7F 7F 7F 7F 0F` error) for deterministic testing and mock simulation.
  static MidiMessage buildStatusReplyMessage({
    required int code,
    int modelId = defaultModelId,
  }) {
    final unsigned = code & 0xFFFFFFFF;
    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdStatus,
      unsigned & 0x7F,
      (unsigned >> 7) & 0x7F,
      (unsigned >> 14) & 0x7F,
      (unsigned >> 21) & 0x7F,
      (unsigned >> 28) & 0x0F,
    ]);
  }

  /// Builds a Zoom `0x60 0x03` error reply frame (default `-1` = `7F 7F 7F 7F 0F`).
  static MidiMessage buildErrorReplyMessage({
    int code = -1,
    int modelId = defaultModelId,
  }) =>
      buildStatusReplyMessage(code: code, modelId: modelId);

  /// Formats a concise hex summary of a SysEx [message] for hardware diagnostics.
  static String formatSysExSummary(MidiMessage? message) {
    if (message == null) return '<none>';
    final data = message.data;
    String hexSlice(Iterable<int> bytes) => bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    if (data.length <= 32) {
      return '${hexSlice(data)} (${data.length} bytes)';
    }
    final head = hexSlice(data.sublist(0, 20));
    final tail = hexSlice(data.sublist(data.length - 6));
    return '$head ... $tail (${data.length} bytes)';
  }

  /// Encodes an 8-bit data [chunk] into a Zoom `0x60 0x04` file-download chunk
  /// SysEx response frame matching real MS-60B+ / Zoom Four hardware:
  /// `F0 52 00 <modelId> 60 04 22 01 00 <lenLsb> <lenMsb> <packed7Bit> <crc5> F7`.
  ///
  /// Passing an empty [chunk] produces an EOF (`unpackedLength == 0`) response frame.
  static MidiMessage encodeChunkResponseMessage(
    Uint8List chunk, {
    int modelId = defaultModelId,
  }) {
    final length = chunk.length;
    final lenLsb = length & 0x7F;
    final lenMsb = (length >> 7) & 0x7F;

    if (length == 0) {
      return MidiMessage.sysEx([
        manufacturerId,
        0x00,
        modelId & 0x7F,
        cmdFileTransfer,
        subCmdDataChunk,
        subCmdReadChunk,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
    }

    final packed = SysexCodec.pack8BitTo7Bit(chunk);
    final crc5 = SysexCodec.calculateZoom7BitCrc(chunk);

    return MidiMessage.sysEx([
      manufacturerId,
      0x00,
      modelId & 0x7F,
      cmdFileTransfer,
      subCmdDataChunk,
      subCmdReadChunk,
      0x01,
      0x00,
      lenLsb,
      lenMsb,
      ...packed,
      ...crc5,
    ]);
  }

  /// Decodes and CRC-verifies an incoming Zoom `0x60 0x04` file chunk SysEx reply.
  ///
  /// Returns `isEof: true` when `frame[5] != 0x04` or `unpackedLength == 0`.
  /// Throws [ZoomFileTransferException] when header is invalid, payload length
  /// is truncated, or the trailing 5-byte inverted CRC32 does not match.
  static ({bool isEof, Uint8List bytes}) decodeChunkResponseMessage(
    MidiMessage message, {
    int modelId = defaultModelId,
    String filename = '',
    int chunkIndex = 0,
  }) {
    final data = message.data;
    if (!message.isSysEx || data.length < 7) {
      return (isEof: true, bytes: Uint8List(0));
    }

    // Frame layout (with F0 at index 0, F7 at index data.length - 1):
    // [0..3]:  F0 52 00 <modelId>
    // [4..5]:  60 04
    // [6..8]:  22 01 00 (3 header bytes)
    // [9..10]: lenLsb, lenMsb -> unpackedLength = lenMsb * 128 + lenLsb
    // [11 .. data.length - 7]: 7-bit packed payload
    // [data.length - 6 .. data.length - 2]: 5-byte inverted CRC32
    // [data.length - 1]: F7
    final bodyLen = data.length - 2;
    if (bodyLen < 5 ||
        data[1] != manufacturerId ||
        data[2] != 0x00 ||
        data[3] != (modelId & 0x7F) ||
        data[4] != cmdFileTransfer) {
      throw ZoomFileTransferException(
        'Unexpected SysEx header while reading "$filename" chunk $chunkIndex: '
        '${formatSysExSummary(message)}',
      );
    }

    if (data[5] != subCmdDataChunk || bodyLen < 15) {
      return (isEof: true, bytes: Uint8List(0));
    }

    final length = ((data[10] & 0x7F) * 128) + (data[9] & 0x7F);
    if (length == 0) {
      return (isEof: true, bytes: Uint8List(0));
    }

    final expectedPackedLen = length + ((length + 6) ~/ 7);
    const payloadStart = 11;
    final crcStart = data.length - 6; // last 5 bytes before trailing 0xF7
    final availablePackedLen = crcStart - payloadStart;

    if (availablePackedLen < expectedPackedLen) {
      throw ZoomFileTransferException(
        'Truncated chunk $chunkIndex while reading "$filename": '
        'expected $expectedPackedLen packed bytes, got $availablePackedLen. '
        'Frame: ${formatSysExSummary(message)}',
      );
    }

    final unpacked = SysexCodec.unpack7BitTo8Bit(
      data,
      start: payloadStart,
      end: payloadStart + expectedPackedLen - 1,
    );
    final block = unpacked.length == length
        ? unpacked
        : Uint8List.sublistView(unpacked, 0, length);

    final receivedCrc = (data[crcStart] & 0x7F) |
        ((data[crcStart + 1] & 0x7F) << 7) |
        ((data[crcStart + 2] & 0x7F) << 14) |
        ((data[crcStart + 3] & 0x7F) << 21) |
        ((data[crcStart + 4] & 0x0F) << 28);
    final expectedCrc = (SysexCodec.calculateCrc32(block) ^ 0xFFFFFFFF) >>> 0;

    if ((receivedCrc >>> 0) != expectedCrc) {
      throw ZoomFileTransferException(
        'CRC32 mismatch on "$filename" chunk $chunkIndex '
        '(received 0x${(receivedCrc >>> 0).toRadixString(16)}, '
        'expected 0x${expectedCrc.toRadixString(16)}). '
        'Frame: ${formatSysExSummary(message)}',
      );
    }

    return (isEof: false, bytes: block);
  }

  /// Returns true when [message] is a Zoom SysEx reply matching [modelId],
  /// filtering out echoed host-to-pedal `60 05 00` poll commands so stray
  /// echoed polls can never shift request/response lockstep off by one.
  bool isZoomReply(MidiMessage message) {
    final data = message.data;
    if (!message.isSysEx ||
        data.length < 6 ||
        data[1] != manufacturerId ||
        data[2] != 0x00 ||
        data[3] != (modelId & 0x7F)) {
      return false;
    }
    // Host-to-pedal poll command (F0 52 00 <modelId> 60 05 00 F7) is never a
    // valid pedal reply; ignore it if echoed or delayed on the wire.
    if (data.length == 8 &&
        data[4] == cmdFileTransfer &&
        data[5] == subCmdPoll &&
        data[6] == 0x00) {
      _logControl('DROP stray poll echo', message);
      return false;
    }
    return true;
  }

  /// Runs [action] inside an exclusive, `try/finally`-protected PC-Mode (`0x52`)
  /// read-only transaction.
  ///
  /// Guarantees:
  /// 1. Live incoming SysEx dispatch is suppressed via [onSuppressLiveDispatch]
  ///    for the entire duration of the transaction.
  /// 2. Enters PC Mode (`0x52`) before invoking [action].
  /// 3. In `finally`, ALWAYS exits PC Mode (`0x53`), re-enters Parameter Edit
  ///    Mode (`0x50`), and restores live incoming SysEx dispatch — even when
  ///    a read fails, times out, or is cancelled.
  Future<T> runReadSession<T>(
    Future<T> Function(ZoomReadSession session) action, {
    void Function(bool suppressed)? onSuppressLiveDispatch,
    bool Function()? isCancelled,
  }) async {
    if (!transport.isConnected) {
      throw const ZoomFileTransferException(
        'Cannot start Zoom file transfer: MIDI transport is not connected.',
      );
    }

    onSuppressLiveDispatch?.call(true);
    final session = ZoomReadSession._(this, isCancelled);
    bool pcModeEntered = false;

    try {
      // Enter PC Mode (0x52) and await optional ACK reply briefly.
      final pcOn = buildPcModeEnableMessage(modelId: modelId);
      pcModeEntered = true;
      try {
        await _sendAndAwaitZoomReply(
          pcOn,
          timeout: pcModeAckTimeout,
          isCancelled: isCancelled,
        );
      } on TimeoutException {
        // Some firmware revisions accept 0x52 silently without an ACK frame.
      }

      if (pacingDelay > Duration.zero) {
        await Future<void>.delayed(pacingDelay);
      }

      return await action(session);
    } finally {
      session._closed = true;
      if (pcModeEntered && transport.isConnected) {
        // Send 60 09 once at session teardown (fire-and-forget, never between
        // consecutive files) before exiting PC Mode (0x53).
        try {
          final finalize = buildCloseFinalizeMessage(modelId: modelId);
          _logControl('TX session-finalize', finalize);
          await transport.send(finalize);
        } catch (_) {}
        if (pacingDelay > Duration.zero) {
          await Future<void>.delayed(pacingDelay);
        }
        if (transport.isConnected) {
          try {
            await transport.send(buildPcModeDisableMessage(modelId: modelId));
          } catch (_) {}
        }
        if (pacingDelay > Duration.zero) {
          await Future<void>.delayed(pacingDelay);
        }
        if (transport.isConnected) {
          try {
            await transport.send(
              buildParameterEditEnableMessage(modelId: modelId),
            );
          } catch (_) {}
          if (pacingDelay > Duration.zero) {
            await Future<void>.delayed(pacingDelay);
          }
        }
      }
      onSuppressLiveDispatch?.call(false);
    }
  }

  /// Convenience helper that downloads a single file inside its own
  /// [runReadSession] transaction.
  Future<Uint8List> downloadFile(
    String filename, {
    void Function(bool suppressed)? onSuppressLiveDispatch,
    bool Function()? isCancelled,
  }) {
    return runReadSession(
      (session) => session.downloadFile(filename),
      onSuppressLiveDispatch: onSuppressLiveDispatch,
      isCancelled: isCancelled,
    );
  }

  Future<void> _drainStaleReplies() async {
    final drain = staleDrainDuration > Duration.zero
        ? staleDrainDuration
        : pacingDelay;
    if (drain <= Duration.zero || !transport.isConnected) return;
    final sub = transport.onMessageReceived.listen((msg) {
      _logControl('DROP stale RX before open', msg);
    });
    try {
      await Future<void>.delayed(drain);
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _closeOpenFileHandle({
    required String filename,
    required bool awaitReplies,
  }) async {
    final closeHandle = buildCloseHandleMessage(modelId: modelId);

    if (awaitReplies) {
      try {
        _logControl('TX close-handle("$filename")', closeHandle);
        final closeAck = await _sendAndAwaitZoomReply(
          closeHandle,
          timeout: closeAckTimeout,
        );
        _logControl('RX close-handle("$filename")', closeAck);
      } catch (e) {
        _logMessage('WARN close-handle("$filename") failed: $e');
      }
      if (pacingDelay > Duration.zero && transport.isConnected) {
        await Future<void>.delayed(pacingDelay);
      }
    } else {
      try {
        _logControl('TX close-handle(fire-and-forget, "$filename")', closeHandle);
        await transport.send(closeHandle);
      } catch (_) {}
    }
  }

  Future<MidiMessage> _sendAndAwaitZoomReply(
    MidiMessage request, {
    required Duration timeout,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true || !transport.isConnected) {
      throw const ZoomFileTransferException(
        'File transfer cancelled because the device disconnected.',
      );
    }

    try {
      return await transport.sendSysExAndWait(
        request,
        responseMatcher: isZoomReply,
        timeout: timeout,
      );
    } on TimeoutException {
      rethrow;
    } catch (e) {
      if (e is ZoomFileTransferException) rethrow;
      throw ZoomFileTransferException('MIDI send/receive error: $e');
    }
  }
}

