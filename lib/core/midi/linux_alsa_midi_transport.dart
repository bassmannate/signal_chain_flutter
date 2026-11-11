import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'midi_message.dart';
import 'midi_port_descriptor.dart';
import 'midi_transport.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  bool runInShell,
});

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  bool runInShell,
  ProcessStartMode mode,
});

/// Zero-dependency Linux ALSA RawMIDI transport communicating via ALSA `amidi`.
///
/// Discovers hardware ports via `amidi -l` (with fallback to `/proc/asound/cards`),
/// streams raw MIDI bytes using background `amidi -p <port> -d` processes,
/// and transmits outbound messages via `amidi -p <port> -S <hex>`.
class LinuxAlsaMidiTransport extends MidiTransport {
  final ProcessRunner _processRunner;
  final ProcessStarter _processStarter;
  final bool _isLinux;
  final File? asoundCardsOverride;

  final StreamController<MidiMessage> _incomingController =
      StreamController<MidiMessage>.broadcast(sync: true);

  bool _isConnected = false;
  MidiPortDescriptor? _connectedPort;
  Process? _listenerProcess;
  StreamSubscription<List<int>>? _stdoutSubscription;

  // Stream reassembly buffers
  String _pendingText = '';
  bool _inSysEx = false;
  final List<int> _sysexBuffer = [];
  final List<int> _channelBuffer = [];
  int _expectedChannelLength = 0;

  LinuxAlsaMidiTransport({
    ProcessRunner? processRunner,
    ProcessStarter? processStarter,
    bool? isLinux,
    this.asoundCardsOverride,
  })  : _processRunner = processRunner ?? Process.run,
        _processStarter = processStarter ?? Process.start,
        _isLinux = isLinux ?? Platform.isLinux;

  @override
  bool get isConnected => _isConnected;

  @override
  MidiPortDescriptor? get connectedPort => _connectedPort;

  @override
  Stream<MidiMessage> get onMessageReceived => _incomingController.stream;

  @override
  Future<List<MidiPortDescriptor>> getAvailablePorts() async {
    if (!_isLinux) {
      return const [];
    }

    try {
      final result = await _processRunner('amidi', ['-l']);
      if (result.exitCode == 0) {
        final ports = parseAmidiListOutput(result.stdout.toString());
        if (ports.isNotEmpty) {
          return ports;
        }
      }
    } catch (_) {
      // amidi execution failed or binary not found; fall back to /proc/asound/cards
    }

    return _fallbackDiscoverPorts();
  }

  /// Parses the stdout output of `amidi -l` into a list of [MidiPortDescriptor].
  static List<MidiPortDescriptor> parseAmidiListOutput(String stdout) {
    final ports = <MidiPortDescriptor>[];
    final lines = LineSplitter.split(stdout);

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.toLowerCase().startsWith('dir')) {
        continue;
      }

      // Regex matches: Dir (e.g. IO, I, O), Device (e.g. hw:1,0,0 or hw:2,0), Name
      final match = RegExp(r'^([IOio]+)\s+([^\s]+)\s+(.+)$').firstMatch(line);
      if (match != null) {
        final dirStr = match.group(1)!.toUpperCase();
        final portId = match.group(2)!;
        final name = match.group(3)!.trim();
        final isInput = dirStr.contains('I');
        final isOutput = dirStr.contains('O');

        String? manufacturer;
        final upperName = name.toUpperCase();
        if (upperName.contains('ZOOM')) {
          manufacturer = 'Zoom Corporation';
        } else if (upperName.contains('LINE 6') || upperName.contains('LINE6')) {
          manufacturer = 'Line 6';
        }

        ports.add(MidiPortDescriptor(
          id: portId,
          name: name,
          manufacturer: manufacturer,
          isInput: isInput,
          isOutput: isOutput,
        ));
      }
    }

    return List.unmodifiable(ports);
  }

  /// Fallback port discovery when `amidi -l` is unavailable.
  Future<List<MidiPortDescriptor>> _fallbackDiscoverPorts() async {
    final ports = <MidiPortDescriptor>[];
    try {
      final cardsFile = asoundCardsOverride ?? File('/proc/asound/cards');
      if (await cardsFile.exists()) {
        final content = await cardsFile.readAsString();
        final lines = LineSplitter.split(content);
        final cardRegex = RegExp(r'^\s*(\d+)\s+\[([^\]]+)\]:\s+(.+)$');

        for (final line in lines) {
          final match = cardRegex.firstMatch(line);
          if (match != null) {
            final cardIndex = match.group(1)!;
            final rawDetails = match.group(3)!.trim();
            final cardName = rawDetails.contains(' - ')
                ? rawDetails.split(' - ').last.trim()
                : rawDetails;

            final midiDev = File('/dev/snd/midiC${cardIndex}D0');
            final hasMidiDev = await midiDev.exists();
            if (hasMidiDev ||
                line.contains('USB-Audio') ||
                rawDetails.contains('USB-Audio') ||
                cardName.toUpperCase().contains('ZOOM')) {
              String? manufacturer;
              final upperName = cardName.toUpperCase();
              if (upperName.contains('ZOOM')) {
                manufacturer = 'Zoom Corporation';
              } else if (upperName.contains('LINE 6') || upperName.contains('LINE6')) {
                manufacturer = 'Line 6';
              }

              ports.add(MidiPortDescriptor(
                id: 'hw:$cardIndex,0,0',
                name: cardName,
                manufacturer: manufacturer,
                isInput: true,
                isOutput: true,
              ));
            }
          }
        }
      }
    } catch (_) {
      // Gracefully ignore filesystem errors in sandboxed / non-Linux environments
    }
    return List.unmodifiable(ports);
  }

  @override
  Future<void> connect(String portId) async {
    if (!_isLinux) {
      throw UnsupportedError('LinuxAlsaMidiTransport is only supported on Linux.');
    }

    if (_isConnected) {
      await disconnect();
    }

    final available = await getAvailablePorts();
    final matchingIndex = available.indexWhere((p) => p.id == portId);
    if (matchingIndex != -1) {
      _connectedPort = available[matchingIndex];
    } else {
      _connectedPort = MidiPortDescriptor(
        id: portId,
        name: portId,
        isInput: true,
        isOutput: true,
      );
    }

    _pendingText = '';
    _inSysEx = false;
    _sysexBuffer.clear();
    _channelBuffer.clear();
    _expectedChannelLength = 0;

    try {
      _listenerProcess = await _processStarter('amidi', ['-p', portId, '-d']);
      _stdoutSubscription = _listenerProcess!.stdout.listen(
        _handleRawStdoutBytes,
        onError: (err) {
          // Process error handling
        },
        onDone: () {
          // Listener terminated
        },
      );
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      _connectedPort = null;
      throw StateError('Failed to start amidi listener on port "$portId": $e');
    }
  }

  void _handleRawStdoutBytes(List<int> bytes) {
    final textChunk = utf8.decode(bytes, allowMalformed: true);
    feedHexStream(textChunk);
  }

  /// Feeds incoming text containing hex tokens (e.g. from `amidi -d`) into the message assembler.
  void feedHexStream(String chunk) {
    _pendingText += chunk;

    // Process all tokens up to the last whitespace delimiter
    final lastWs = _pendingText.lastIndexOf(RegExp(r'\s'));
    if (lastWs == -1) {
      // No complete whitespace-delimited token yet
      return;
    }

    final toProcess = _pendingText.substring(0, lastWs);
    _pendingText = _pendingText.substring(lastWs + 1);

    final tokens = toProcess.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    for (final token in tokens) {
      final byte = int.tryParse(token, radix: 16);
      if (byte == null || byte < 0 || byte > 255) {
        continue;
      }
      _consumeByte(byte);
    }
  }

  void _consumeByte(int byte) {
    if (_inSysEx) {
      _sysexBuffer.add(byte);
      if (byte == 0xF7) {
        // SysEx end
        _emitMessage(Uint8List.fromList(_sysexBuffer));
        _sysexBuffer.clear();
        _inSysEx = false;
      } else if (byte >= 0x80 && byte < 0xF8) {
        // Unexpected status byte terminating SysEx prematurely
        _sysexBuffer.clear();
        _inSysEx = false;
        _consumeByte(byte); // Re-process as new status
      }
      return;
    }

    if (byte == 0xF0) {
      _inSysEx = true;
      _sysexBuffer.clear();
      _sysexBuffer.add(byte);
      _channelBuffer.clear();
      _expectedChannelLength = 0;
      return;
    }

    if (byte >= 0x80) {
      // Status byte
      _channelBuffer.clear();
      _channelBuffer.add(byte);

      final statusNibble = byte & 0xF0;
      if (statusNibble == 0xC0 || statusNibble == 0xD0) {
        // Program Change or Channel Pressure: 2 bytes
        _expectedChannelLength = 2;
      } else if (statusNibble >= 0x80 && statusNibble <= 0xE0) {
        // Note Off, Note On, Poly Key Pressure, Control Change, Pitch Bend: 3 bytes
        _expectedChannelLength = 3;
      } else if (byte == 0xF1 || byte == 0xF3) {
        // MTC Quarter Frame, Song Select: 2 bytes
        _expectedChannelLength = 2;
      } else if (byte == 0xF2) {
        // Song Position Pointer: 3 bytes
        _expectedChannelLength = 3;
      } else if (byte == 0xF6 || (byte >= 0xF8 && byte <= 0xFF)) {
        // Tune request, Real-Time: 1 byte
        _expectedChannelLength = 1;
      } else {
        _expectedChannelLength = 1;
      }

      if (_channelBuffer.length >= _expectedChannelLength) {
        _emitMessage(Uint8List.fromList(_channelBuffer));
        _channelBuffer.clear();
        _expectedChannelLength = 0;
      }
      return;
    }

    // Data byte (< 0x80)
    if (_channelBuffer.isNotEmpty) {
      _channelBuffer.add(byte);
      if (_channelBuffer.length >= _expectedChannelLength) {
        _emitMessage(Uint8List.fromList(_channelBuffer));
        _channelBuffer.clear();
        _expectedChannelLength = 0;
      }
    }
  }

  void _emitMessage(Uint8List data) {
    if (!_incomingController.isClosed) {
      _incomingController.add(MidiMessage(data, timestamp: DateTime.now()));
    }
  }

  @override
  Future<void> send(MidiMessage message) async {
    if (!_isConnected || _connectedPort == null) {
      throw StateError('Cannot send message: LinuxAlsaMidiTransport is not connected.');
    }

    final hexString = message.data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    try {
      final result = await _processRunner(
        'amidi',
        ['-p', _connectedPort!.id, '-S', hexString],
      );
      if (result.exitCode != 0) {
        throw StateError(
          'amidi send failed with exit code ${result.exitCode}: ${result.stderr}',
        );
      }
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError('Failed to send MIDI message via amidi: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPort = null;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    if (_listenerProcess != null) {
      try {
        _listenerProcess!.kill(ProcessSignal.sigterm);
      } catch (_) {
        try {
          _listenerProcess!.kill();
        } catch (_) {}
      }
      _listenerProcess = null;
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    if (!_incomingController.isClosed) {
      await _incomingController.close();
    }
  }
}
