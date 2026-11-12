import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/linux_alsa_midi_transport.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  bool wasKilled = false;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    return true;
  }

  void emitStdout(String text) {
    _stdoutController.add(utf8.encode(text));
  }

  Future<void> close() async {
    await _stdoutController.close();
    await _stderrController.close();
  }
}

void main() {
  group('LinuxAlsaMidiTransport Unit Tests', () {
    test('parseAmidiListOutput correctly parses standard amidi -l tables', () {
      const sampleOutput = '''
Dir Device    Name
IO  hw:1,0,0  ZOOM MS-60B+ MIDI 1
IO  hw:2,0,0  USB MIDI Interface MIDI 1
I   hw:3,0,0  Line 6 Bass Pod Pro In
O   hw:3,0,1  Line 6 Bass Pod Pro Out
''';

      final ports = LinuxAlsaMidiTransport.parseAmidiListOutput(sampleOutput);

      expect(ports.length, 4);

      // Port 1: Zoom MS-60B+
      expect(ports[0].id, 'hw:1,0,0');
      expect(ports[0].name, 'ZOOM MS-60B+ MIDI 1');
      expect(ports[0].manufacturer, 'Zoom Corporation');
      expect(ports[0].isInput, isTrue);
      expect(ports[0].isOutput, isTrue);

      // Port 2: Generic USB MIDI
      expect(ports[1].id, 'hw:2,0,0');
      expect(ports[1].name, 'USB MIDI Interface MIDI 1');
      expect(ports[1].manufacturer, isNull);
      expect(ports[1].isInput, isTrue);
      expect(ports[1].isOutput, isTrue);

      // Port 3: Line 6 Input only
      expect(ports[2].id, 'hw:3,0,0');
      expect(ports[2].name, 'Line 6 Bass Pod Pro In');
      expect(ports[2].manufacturer, 'Line 6');
      expect(ports[2].isInput, isTrue);
      expect(ports[2].isOutput, isFalse);

      // Port 4: Line 6 Output only
      expect(ports[3].id, 'hw:3,0,1');
      expect(ports[3].name, 'Line 6 Bass Pod Pro Out');
      expect(ports[3].manufacturer, 'Line 6');
      expect(ports[3].isInput, isFalse);
      expect(ports[3].isOutput, isTrue);
    });

    test('getAvailablePorts returns empty list when platform is not Linux', () async {
      final transport = LinuxAlsaMidiTransport(isLinux: false);
      final ports = await transport.getAvailablePorts();
      expect(ports, isEmpty);
    });

    test('getAvailablePorts queries amidi -l via injected processRunner', () async {
      String? executedCommand;
      List<String>? executedArgs;

      final transport = LinuxAlsaMidiTransport(
        isLinux: true,
        processRunner: (executable, args, {environment, runInShell = false}) async {
          executedCommand = executable;
          executedArgs = args;
          return ProcessResult(
            100,
            0,
            'Dir Device    Name\nIO  hw:1,0,0  ZOOM MS-60B+ MIDI 1\n',
            '',
          );
        },
      );

      final ports = await transport.getAvailablePorts();
      expect(executedCommand, 'amidi');
      expect(executedArgs, ['-l']);
      expect(ports.length, 1);
      expect(ports.first.id, 'hw:1,0,0');
      expect(ports.first.name, 'ZOOM MS-60B+ MIDI 1');
    });

    test('getAvailablePorts falls back to /proc/asound/cards when amidi fails', () async {
      final tempDir = await Directory.systemTemp.createTemp('asound_test_');
      final tempCardsFile = File('${tempDir.path}/cards');
      await tempCardsFile.writeAsString('''
 0 [PCH            ]: HDA-Intel - HDA Intel PCH
                      HDA Intel PCH at 0x...
 1 [MS60BPLUS      ]: USB-Audio - ZOOM MS-60B+
                      ZOOM Corporation ZOOM MS-60B+ at ...
''');

      final transport = LinuxAlsaMidiTransport(
        isLinux: true,
        asoundCardsOverride: tempCardsFile,
        processRunner: (executable, args, {environment, runInShell = false}) async {
          throw const ProcessException('amidi', ['-l'], 'amidi: not found');
        },
      );

      final ports = await transport.getAvailablePorts();
      expect(ports.length, 1);
      expect(ports.first.id, 'hw:1,0,0');
      expect(ports.first.name, 'ZOOM MS-60B+');
      expect(ports.first.manufacturer, 'Zoom Corporation');

      await tempDir.delete(recursive: true);
    });

    test('feedHexStream parses single-line and multi-line SysEx dumps correctly', () async {
      final transport = LinuxAlsaMidiTransport(isLinux: true);
      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      // 1. Single-line SysEx: Identity Request
      transport.feedHexStream('F0 7E 7F 06 01 F7\n');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(
        received[0].data,
        Uint8List.fromList([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]),
      );

      // 2. Multi-line SysEx dump
      transport.feedHexStream('F0 52 00 6E ');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1); // Not finished yet
      transport.feedHexStream('64 12 01 05 00\n');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      transport.feedHexStream('01 02 03 04 05 F7\n');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);
      expect(
        received[1].data,
        Uint8List.fromList([
          0xF0, 0x52, 0x00, 0x6E, 0x64, 0x12, 0x01, 0x05, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0xF7,
        ]),
      );

      // 3. SysEx without trailing whitespace or newline (critical for live amidi -d real-time events)
      transport.feedHexStream('F0 52 00 6E 64 20 00 01 00 01 00 00 00 00 F7');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 3);
      expect(
        received[2].data,
        Uint8List.fromList([
          0xF0, 0x52, 0x00, 0x6E, 0x64, 0x20, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xF7,
        ]),
      );

      // 4. Incomplete 1-char token buffering across chunk boundaries
      transport.feedHexStream('F0 52 00 6E F');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 3); // Still 3, 'F' is incomplete tail
      transport.feedHexStream('7');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 4);
      expect(received[3].data, Uint8List.fromList([0xF0, 0x52, 0x00, 0x6E, 0xF7]));

      await sub.cancel();
      await transport.dispose();
    });

    test('feedHexStream parses Control Change (CC) and Program Change (PC)', () async {
      final transport = LinuxAlsaMidiTransport(isLinux: true);
      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      // CC message (Drive CC#4, value 75 on channel 0)
      transport.feedHexStream('B0 04 4B\n');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(received[0].isControlChange, isTrue);
      expect(received[0].data, Uint8List.fromList([0xB0, 0x04, 0x4B]));

      // PC message (Program 5 on channel 0)
      transport.feedHexStream('C0 05\n');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);
      expect(received[1].isProgramChange, isTrue);
      expect(received[1].data, Uint8List.fromList([0xC0, 0x05]));

      // Mixed stream on one line
      transport.feedHexStream('B0 0E 40 C0 01\n');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 4);
      expect(received[2].data, Uint8List.fromList([0xB0, 0x0E, 0x40]));
      expect(received[3].data, Uint8List.fromList([0xC0, 0x01]));

      await sub.cancel();
      await transport.dispose();
    });

    test('connect spawns amidi background listener and streams stdout events', () async {
      final fakeProcess = _FakeProcess();
      String? startedExecutable;
      List<String>? startedArgs;

      final transport = LinuxAlsaMidiTransport(
        isLinux: true,
        processRunner: (exe, args, {environment, runInShell = false}) async {
          return ProcessResult(1, 0, 'Dir Device Name\nIO hw:1,0,0 ZOOM MS-60B+\n', '');
        },
        processStarter: (exe, args, {environment, runInShell = false, mode = ProcessStartMode.normal}) async {
          startedExecutable = exe;
          startedArgs = args;
          return fakeProcess;
        },
      );

      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      await transport.connect('hw:1,0,0');
      expect(transport.isConnected, isTrue);
      expect(transport.connectedPort?.id, 'hw:1,0,0');
      expect(startedExecutable, 'amidi');
      expect(startedArgs, ['-p', 'hw:1,0,0', '-d']);

      // Push stdout from background process
      fakeProcess.emitStdout('F0 7E 00 06 02 52 6E 00 27 00 F7\n');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received.length, 1);
      expect(received.first.isSysEx, isTrue);

      // Disconnect kills the process
      await transport.disconnect();
      expect(transport.isConnected, isFalse);
      expect(fakeProcess.wasKilled, isTrue);

      await fakeProcess.close();
      await sub.cancel();
      await transport.dispose();
    });

    test('send formats hex string and invokes amidi -p port -S', () async {
      String? sendCmd;
      List<String>? sendArgs;
      final fakeProcess = _FakeProcess();

      final transport = LinuxAlsaMidiTransport(
        isLinux: true,
        processRunner: (exe, args, {environment, runInShell = false}) async {
          if (args.contains('-S')) {
            sendCmd = exe;
            sendArgs = args;
            return ProcessResult(2, 0, '', '');
          }
          return ProcessResult(1, 0, 'Dir Device Name\nIO hw:1,0,0 MS-60B+\n', '');
        },
        processStarter: (exe, args, {environment, runInShell = false, mode = ProcessStartMode.normal}) async {
          return fakeProcess;
        },
      );

      await transport.connect('hw:1,0,0');

      final msg = MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x50]);
      await transport.send(msg);

      expect(sendCmd, 'amidi');
      expect(sendArgs, ['-p', 'hw:1,0,0', '-S', 'F0 52 00 6E 50 F7']);

      await fakeProcess.close();
      await transport.dispose();
    });

    test('send throws StateError when not connected', () async {
      final transport = LinuxAlsaMidiTransport(isLinux: true);
      expect(
        () => transport.send(MidiMessage.sysEx([0x00])),
        throwsStateError,
      );
    });

    test('send throws StateError when amidi process returns non-zero exit code', () async {
      final fakeProcess = _FakeProcess();
      final transport = LinuxAlsaMidiTransport(
        isLinux: true,
        processRunner: (exe, args, {environment, runInShell = false}) async {
          if (args.contains('-S')) {
            return ProcessResult(2, 1, '', 'Device or resource busy');
          }
          return ProcessResult(1, 0, 'Dir Device Name\nIO hw:1,0,0 MS-60B+\n', '');
        },
        processStarter: (exe, args, {environment, runInShell = false, mode = ProcessStartMode.normal}) async {
          return fakeProcess;
        },
      );

      await transport.connect('hw:1,0,0');
      expect(
        () => transport.send(MidiMessage.controlChange(channel: 0, controller: 4, value: 50)),
        throwsStateError,
      );

      await fakeProcess.close();
      await transport.dispose();
    });
  });
}
