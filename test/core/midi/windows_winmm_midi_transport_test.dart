import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/windows_winmm_midi_transport.dart';

typedef _CallocNative = Pointer<Void> Function(IntPtr num, IntPtr size);
typedef _CallocDart = Pointer<Void> Function(int num, int size);
typedef _FreeNative = Void Function(Pointer<Void> ptr);
typedef _FreeDart = void Function(Pointer<Void> ptr);

class FakeWinMmNativeBindings implements WinMmNativeBindings {
  late final _CallocDart _calloc;
  late final _FreeDart _free;

  final Map<int, int> allocatedBlocks = {};
  final List<String> callLog = [];

  List<String> inputDeviceNames = [];
  List<String> outputDeviceNames = [];

  int midiInOpenResult = MMSYSERR_NOERROR;
  int midiOutOpenResult = MMSYSERR_NOERROR;
  int midiOutShortMsgResult = MMSYSERR_NOERROR;
  int midiOutLongMsgResult = MMSYSERR_NOERROR;

  bool autoCompleteOutSysEx = true;
  Duration? asyncOutSysExDelay;
  bool flushBuffersOnReset = false;

  int nextHandle = 0x1000;
  int? openMidiInHandle;
  int? openMidiOutHandle;
  MidiInProcDart? midiInCallback;

  final List<Pointer<MIDIHDR>> queuedInputHeaders = [];
  final Set<int> preparedInputHeaders = {};
  final Set<int> preparedOutputHeaders = {};
  final List<int> sentShortMessages = [];
  final List<Uint8List> sentSysExPayloads = [];
  int midiInAddBufferCountDuringClosing = 0;

  FakeWinMmNativeBindings() {
    final DynamicLibrary lib = Platform.isWindows
        ? DynamicLibrary.open('msvcrt.dll')
        : DynamicLibrary.process();
    _calloc = lib.lookupFunction<_CallocNative, _CallocDart>('calloc');
    _free = lib.lookupFunction<_FreeNative, _FreeDart>('free');
  }

  @override
  Pointer<Void> heapAlloc(int byteCount) {
    final size = byteCount <= 0 ? 1 : byteCount;
    final ptr = _calloc(1, size);
    if (ptr.address != 0) {
      allocatedBlocks[ptr.address] = size;
    }
    return ptr;
  }

  @override
  bool heapFree(Pointer<Void> ptr) {
    if (ptr.address == 0) {
      return false;
    }
    if (!allocatedBlocks.containsKey(ptr.address)) {
      throw StateError(
        'Double-free or invalid heapFree at 0x${ptr.address.toRadixString(16)}',
      );
    }
    allocatedBlocks.remove(ptr.address);
    _free(ptr);
    return true;
  }

  @override
  int midiInGetNumDevs() {
    callLog.add('midiInGetNumDevs');
    return inputDeviceNames.length;
  }

  @override
  int midiOutGetNumDevs() {
    callLog.add('midiOutGetNumDevs');
    return outputDeviceNames.length;
  }

  static void _writePname(Array<Uint16> szPname, String name) {
    final units = name.codeUnits;
    final limit = units.length < MAXPNAMELEN ? units.length : MAXPNAMELEN;
    for (int i = 0; i < MAXPNAMELEN; i++) {
      szPname[i] = i < limit ? units[i] : 0;
    }
  }

  @override
  int midiInGetDevCaps(int uDeviceID, Pointer<MIDIINCAPSW> pmic, int cbmic) {
    callLog.add('midiInGetDevCaps($uDeviceID)');
    if (uDeviceID < 0 || uDeviceID >= inputDeviceNames.length) {
      return 2; // MMSYSERR_BADDEVICEID
    }
    _writePname(pmic.ref.szPname, inputDeviceNames[uDeviceID]);
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutGetDevCaps(int uDeviceID, Pointer<MIDIOUTCAPSW> pmoc, int cbmoc) {
    callLog.add('midiOutGetDevCaps($uDeviceID)');
    if (uDeviceID < 0 || uDeviceID >= outputDeviceNames.length) {
      return 2;
    }
    _writePname(pmoc.ref.szPname, outputDeviceNames[uDeviceID]);
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInOpen(
    Pointer<IntPtr> phmi,
    int uDeviceID,
    Pointer<NativeFunction<MidiInProcNative>> dwCallback,
    int dwInstance,
    int fdwOpen,
  ) {
    callLog.add('midiInOpen($uDeviceID)');
    if (midiInOpenResult != MMSYSERR_NOERROR) {
      return midiInOpenResult;
    }
    final handle = nextHandle++;
    openMidiInHandle = handle;
    phmi.value = handle;
    midiInCallback = dwCallback.asFunction<MidiInProcDart>();
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInPrepareHeader(int hmi, Pointer<MIDIHDR> pmh, int cbmh) {
    callLog.add('midiInPrepareHeader');
    preparedInputHeaders.add(pmh.address);
    pmh.ref.dwFlags |= MHDR_PREPARED;
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInUnprepareHeader(int hmi, Pointer<MIDIHDR> pmh, int cbmh) {
    callLog.add('midiInUnprepareHeader');
    preparedInputHeaders.remove(pmh.address);
    pmh.ref.dwFlags &= ~MHDR_PREPARED;
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInAddBuffer(int hmi, Pointer<MIDIHDR> pmh, int cbmh) {
    callLog.add('midiInAddBuffer');
    if (openMidiInHandle == null) {
      midiInAddBufferCountDuringClosing++;
    }
    pmh.ref.dwFlags = (pmh.ref.dwFlags & ~MHDR_DONE) | MHDR_INQUEUE;
    queuedInputHeaders.add(pmh);
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInStart(int hmi) {
    callLog.add('midiInStart');
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInStop(int hmi) {
    callLog.add('midiInStop');
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInReset(int hmi) {
    callLog.add('midiInReset');
    if (flushBuffersOnReset && midiInCallback != null) {
      final toFlush = List<Pointer<MIDIHDR>>.from(queuedInputHeaders);
      queuedInputHeaders.clear();
      for (final hdr in toFlush) {
        hdr.ref.dwBytesRecorded = 0;
        hdr.ref.dwFlags = (hdr.ref.dwFlags & ~MHDR_INQUEUE) | MHDR_DONE;
        midiInCallback!(hmi, MIM_LONGDATA, 0, hdr.address, 0);
      }
    } else {
      queuedInputHeaders.clear();
    }
    return MMSYSERR_NOERROR;
  }

  @override
  int midiInClose(int hmi) {
    callLog.add('midiInClose');
    openMidiInHandle = null;
    midiInCallback = null;
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutOpen(
    Pointer<IntPtr> phmo,
    int uDeviceID,
    int dwCallback,
    int dwInstance,
    int fdwOpen,
  ) {
    callLog.add('midiOutOpen($uDeviceID)');
    if (midiOutOpenResult != MMSYSERR_NOERROR) {
      return midiOutOpenResult;
    }
    final handle = nextHandle++;
    openMidiOutHandle = handle;
    phmo.value = handle;
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutShortMsg(int hmo, int dwMsg) {
    callLog.add('midiOutShortMsg(0x${dwMsg.toRadixString(16)})');
    if (midiOutShortMsgResult != MMSYSERR_NOERROR) {
      return midiOutShortMsgResult;
    }
    sentShortMessages.add(dwMsg);
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutPrepareHeader(int hmo, Pointer<MIDIHDR> pmh, int cbmh) {
    callLog.add('midiOutPrepareHeader');
    preparedOutputHeaders.add(pmh.address);
    pmh.ref.dwFlags |= MHDR_PREPARED;
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutUnprepareHeader(int hmo, Pointer<MIDIHDR> pmh, int cbmh) {
    callLog.add('midiOutUnprepareHeader');
    preparedOutputHeaders.remove(pmh.address);
    pmh.ref.dwFlags &= ~MHDR_PREPARED;
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutLongMsg(int hmo, Pointer<MIDIHDR> pmh, int cbmh) {
    callLog.add('midiOutLongMsg');
    if (midiOutLongMsgResult != MMSYSERR_NOERROR) {
      return midiOutLongMsgResult;
    }
    final len = pmh.ref.dwBufferLength;
    final payload = Uint8List.fromList(pmh.ref.lpData.asTypedList(len));
    sentSysExPayloads.add(payload);

    if (autoCompleteOutSysEx) {
      if (asyncOutSysExDelay != null) {
        Future<void>.delayed(asyncOutSysExDelay!, () {
          pmh.ref.dwFlags |= MHDR_DONE;
        });
      } else {
        pmh.ref.dwFlags |= MHDR_DONE;
      }
    }
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutReset(int hmo) {
    callLog.add('midiOutReset');
    return MMSYSERR_NOERROR;
  }

  @override
  int midiOutClose(int hmo) {
    callLog.add('midiOutClose');
    openMidiOutHandle = null;
    return MMSYSERR_NOERROR;
  }

  void simulateIncomingShortMessage(int b0, [int b1 = 0, int b2 = 0]) {
    final packed = (b0 & 0xFF) | ((b1 & 0xFF) << 8) | ((b2 & 0xFF) << 16);
    midiInCallback!(openMidiInHandle!, MIM_DATA, 0, packed, 0);
  }

  void simulateIncomingLongDataChunk(List<int> bytes) {
    if (queuedInputHeaders.isEmpty) {
      throw StateError('No queued input MIDIHDR available for simulation.');
    }
    final hdr = queuedInputHeaders.removeAt(0);
    hdr.ref.lpData.asTypedList(bytes.length).setAll(0, bytes);
    hdr.ref.dwBytesRecorded = bytes.length;
    hdr.ref.dwFlags = (hdr.ref.dwFlags & ~MHDR_INQUEUE) | MHDR_DONE;
    midiInCallback!(openMidiInHandle!, MIM_LONGDATA, 0, hdr.address, 0);
  }
}

void main() {
  group('WinMmMidiTransport Unit Tests', () {
    late FakeWinMmNativeBindings fakeBindings;
    late WinMmMidiTransport transport;

    setUp(() {
      fakeBindings = FakeWinMmNativeBindings();
      transport = WinMmMidiTransport(
        bindings: fakeBindings,
        isWindows: true,
        inputBufferCount: 4,
        inputBufferSize: 256,
        sysexPollInterval: Duration.zero,
        sysexSendTimeout: const Duration(milliseconds: 250),
      );
    });

    tearDown(() async {
      await transport.dispose();
      expect(fakeBindings.allocatedBlocks, isEmpty);
      expect(fakeBindings.preparedInputHeaders, isEmpty);
      expect(fakeBindings.preparedOutputHeaders, isEmpty);
    });

    test('returns empty ports and rejects connect on non-Windows hosts', () async {
      final nonWin = WinMmMidiTransport(
        bindings: fakeBindings,
        isWindows: false,
      );
      expect(await nonWin.getAvailablePorts(), isEmpty);
      await expectLater(
        () => nonWin.connect('winmm:in:0|out:0'),
        throwsUnsupportedError,
      );
      await nonWin.dispose();
    });

    test('pairs exact, duplicate, prefix-wrapped, unpaired, and 32-char UTF-16 endpoints',
        () async {
      final maxLenName = 'ZOOM_MS_60B_PLUS_32_CHARS_123456'; // exactly 32 chars
      expect(maxLenName.length, 32);

      fakeBindings.inputDeviceNames = [
        'ZOOM MS-60B+',
        'MIDIIN2 (ZOOM MS-60B+)',
        'MIDIIN3: Line 6 Bass POD Pro',
        'Controller Keyboard In',
        maxLenName,
      ];
      fakeBindings.outputDeviceNames = [
        'Microsoft GS Wavetable Synth',
        'ZOOM MS-60B+',
        'MIDIOUT2 (ZOOM MS-60B+)',
        'MIDIOUT3: Line 6 Bass POD Pro',
        maxLenName,
      ];

      final ports = await transport.getAvailablePorts();

      expect(ports.length, 6);

      // Duplicate pedal #1: input 0 + output 1
      expect(ports[0].id, 'winmm:in:0|out:1');
      expect(ports[0].name, 'ZOOM MS-60B+');
      expect(ports[0].manufacturer, 'Zoom Corporation');
      expect(ports[0].isInput, isTrue);
      expect(ports[0].isOutput, isTrue);

      // Duplicate pedal #2 with MIDIIN2/MIDIOUT2 prefix: input 1 + output 2
      expect(ports[1].id, 'winmm:in:1|out:2');
      expect(ports[1].name, 'ZOOM MS-60B+');
      expect(ports[1].manufacturer, 'Zoom Corporation');
      expect(ports[1].isInput, isTrue);
      expect(ports[1].isOutput, isTrue);

      // Prefix-normalized Line 6 pair: input 2 + output 3
      expect(ports[2].id, 'winmm:in:2|out:3');
      expect(ports[2].name, 'Line 6 Bass POD Pro');
      expect(ports[2].manufacturer, 'Line 6');
      expect(ports[2].isInput, isTrue);
      expect(ports[2].isOutput, isTrue);

      // Unpaired input-only endpoint: input 3
      expect(ports[3].id, 'winmm:in:3');
      expect(ports[3].name, 'Controller Keyboard In');
      expect(ports[3].isInput, isTrue);
      expect(ports[3].isOutput, isFalse);

      // Full 32-char UTF-16 szPname without null terminator: input 4 + output 4
      expect(ports[4].id, 'winmm:in:4|out:4');
      expect(ports[4].name, maxLenName);
      expect(ports[4].isInput, isTrue);
      expect(ports[4].isOutput, isTrue);

      // Unpaired output-only endpoint: output 0
      expect(ports[5].id, 'winmm:out:0');
      expect(ports[5].name, 'Microsoft GS Wavetable Synth');
      expect(ports[5].isInput, isFalse);
      expect(ports[5].isOutput, isTrue);
    });

    test('rolls back input handle and buffers cleanly when midiOutOpen fails',
        () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.midiOutOpenResult = 4; // MMSYSERR_ALLOCATED

      await expectLater(
        () => transport.connect('winmm:in:0|out:0'),
        throwsStateError,
      );

      expect(transport.isConnected, isFalse);
      expect(transport.connectedPort, isNull);
      expect(fakeBindings.openMidiInHandle, isNull);
      expect(fakeBindings.openMidiOutHandle, isNull);
      expect(fakeBindings.callLog, contains('midiInStop'));
      expect(fakeBindings.callLog, contains('midiInReset'));
      expect(fakeBindings.callLog, contains('midiInUnprepareHeader'));
      expect(fakeBindings.callLog, contains('midiInClose'));
      expect(fakeBindings.allocatedBlocks, isEmpty);
    });

    test('packs 1-, 2-, and 3-byte short messages for midiOutShortMsg',
        () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];

      await transport.connect('winmm:in:0|out:0');

      // 3-byte CC: B0 04 4B -> 0x004B04B0
      await transport.send(
        MidiMessage.controlChange(channel: 0, controller: 4, value: 0x4B),
      );
      // 2-byte PC: C0 05 -> 0x000005C0
      await transport.send(
        MidiMessage.programChange(channel: 0, program: 5),
      );
      // 1-byte Timing Clock: F8 -> 0x000000F8
      await transport.send(MidiMessage(Uint8List.fromList([0xF8])));

      expect(fakeBindings.sentShortMessages, [
        0x004B04B0,
        0x000005C0,
        0x000000F8,
      ]);
    });

    test('sends SysEx via MIDIHDR lifecycle and frees native buffers', () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.asyncOutSysExDelay = const Duration(milliseconds: 5);

      await transport.connect('winmm:in:0|out:0');

      final sysex = MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x33]);
      await transport.send(sysex);

      expect(fakeBindings.sentSysExPayloads.length, 1);
      expect(fakeBindings.sentSysExPayloads.first, sysex.data);
      expect(fakeBindings.preparedOutputHeaders, isEmpty);

      final prepIdx = fakeBindings.callLog.indexOf('midiOutPrepareHeader');
      final longIdx = fakeBindings.callLog.indexOf('midiOutLongMsg');
      final unprepIdx = fakeBindings.callLog.indexOf('midiOutUnprepareHeader');
      expect(prepIdx, greaterThanOrEqualTo(0));
      expect(longIdx, greaterThan(prepIdx));
      expect(unprepIdx, greaterThan(longIdx));
    });

    test('frees SysEx buffers when midiOutLongMsg fails', () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.midiOutLongMsgResult = 1;

      await transport.connect('winmm:in:0|out:0');

      await expectLater(
        () => transport.send(MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x50])),
        throwsStateError,
      );

      expect(fakeBindings.preparedOutputHeaders, isEmpty);
      expect(fakeBindings.callLog, contains('midiOutUnprepareHeader'));
    });

    test('receives 1-, 2-, and 3-byte MIM_DATA short messages via NativeCallable',
        () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];

      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      await transport.connect('winmm:in:0|out:0');

      fakeBindings.simulateIncomingShortMessage(0xB0, 0x0E, 0x40);
      fakeBindings.simulateIncomingShortMessage(0xC2, 0x1A);
      fakeBindings.simulateIncomingShortMessage(0xF8);
      await pumpEventQueue();

      expect(received.length, 3);
      expect(received[0].data, Uint8List.fromList([0xB0, 0x0E, 0x40]));
      expect(received[1].data, Uint8List.fromList([0xC2, 0x1A]));
      expect(received[2].data, Uint8List.fromList([0xF8]));

      await sub.cancel();
    });

    test('reassembles multi-buffer 989-byte MIM_LONGDATA SysEx and re-queues buffers',
        () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];

      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      await transport.connect('winmm:in:0|out:0');
      expect(fakeBindings.queuedInputHeaders.length, 4);

      final fullPayload = Uint8List(989);
      fullPayload[0] = 0xF0;
      for (int i = 1; i < 988; i++) {
        fullPayload[i] = i & 0x7F;
      }
      fullPayload[988] = 0xF7;

      // Split into 256-byte chunks (256, 256, 256, 221) matching inputBufferSize
      const chunkSize = 256;
      for (int offset = 0; offset < fullPayload.length; offset += chunkSize) {
        final end = (offset + chunkSize < fullPayload.length)
            ? offset + chunkSize
            : fullPayload.length;
        fakeBindings.simulateIncomingLongDataChunk(
          fullPayload.sublist(offset, end),
        );
        await pumpEventQueue();
      }

      expect(received.length, 1);
      expect(received.first.isSysEx, isTrue);
      expect(received.first.data.length, 989);
      expect(received.first.data, fullPayload);

      // Every processed input buffer should have been re-queued while active
      expect(fakeBindings.queuedInputHeaders.length, 4);

      await sub.cancel();
    });

    test('teardown during midiInReset buffer flush never re-queues buffers or leaks',
        () async {
      fakeBindings.inputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.outputDeviceNames = ['ZOOM MS-60B+'];
      fakeBindings.flushBuffersOnReset = true;

      final received = <MidiMessage>[];
      final sub = transport.onMessageReceived.listen(received.add);

      await transport.connect('winmm:in:0|out:0');
      final addCallsBeforeDisconnect =
          fakeBindings.callLog.where((c) => c == 'midiInAddBuffer').length;
      expect(addCallsBeforeDisconnect, 4);

      await transport.disconnect();
      await pumpEventQueue();

      expect(transport.isConnected, isFalse);
      expect(received, isEmpty);

      final addCallsAfterDisconnect =
          fakeBindings.callLog.where((c) => c == 'midiInAddBuffer').length;
      expect(addCallsAfterDisconnect, addCallsBeforeDisconnect);
      expect(fakeBindings.midiInAddBufferCountDuringClosing, 0);
      expect(fakeBindings.queuedInputHeaders, isEmpty);
      expect(fakeBindings.preparedInputHeaders, isEmpty);
      expect(fakeBindings.allocatedBlocks, isEmpty);

      await sub.cancel();
    });
  });
}
