// ignore_for_file: camel_case_types, constant_identifier_names, non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'midi_message.dart';
import 'midi_port_descriptor.dart';
import 'midi_transport.dart';

/// Standard WinMM success result code.
const int MMSYSERR_NOERROR = 0;

/// WinMM callback flags.
const int CALLBACK_NULL = 0x00000000;
const int CALLBACK_FUNCTION = 0x00030000;

/// WinMM `MIDIIN` callback message identifiers.
const int MIM_OPEN = 0x3C1;
const int MIM_CLOSE = 0x3C2;
const int MIM_DATA = 0x3C3;
const int MIM_LONGDATA = 0x3C4;
const int MIM_ERROR = 0x3C5;
const int MIM_LONGERROR = 0x3C6;

/// WinMM `MIDIHDR.dwFlags` bitmasks.
const int MHDR_DONE = 0x00000001;
const int MHDR_PREPARED = 0x00000002;
const int MHDR_INQUEUE = 0x00000004;

/// Kernel32 `HeapAlloc` zero-initialization flag.
const int HEAP_ZERO_MEMORY = 0x00000008;

/// Maximum UTF-16 code units in `MIDIINCAPSW.szPname` / `MIDIOUTCAPSW.szPname`.
const int MAXPNAMELEN = 32;

/// Win32 `MIDIINCAPSW` structure layout for `midiInGetDevCapsW`.
final class MIDIINCAPSW extends Struct {
  @Uint16()
  external int wMid;

  @Uint16()
  external int wPid;

  @Uint32()
  external int vDriverVersion;

  @Array(MAXPNAMELEN)
  external Array<Uint16> szPname;

  @Uint32()
  external int dwSupport;
}

/// Win32 `MIDIOUTCAPSW` structure layout for `midiOutGetDevCapsW`.
final class MIDIOUTCAPSW extends Struct {
  @Uint16()
  external int wMid;

  @Uint16()
  external int wPid;

  @Uint32()
  external int vDriverVersion;

  @Array(MAXPNAMELEN)
  external Array<Uint16> szPname;

  @Uint16()
  external int wTechnology;

  @Uint16()
  external int wVoices;

  @Uint16()
  external int wNotes;

  @Uint16()
  external int wChannelMask;

  @Uint32()
  external int dwSupport;
}

/// Win32 `MIDIHDR` structure layout for SysEx input/output buffers.
final class MIDIHDR extends Struct {
  external Pointer<Uint8> lpData;

  @Uint32()
  external int dwBufferLength;

  @Uint32()
  external int dwBytesRecorded;

  @IntPtr()
  external int dwUser;

  @Uint32()
  external int dwFlags;

  external Pointer<MIDIHDR> lpNext;

  @IntPtr()
  external int reserved;

  @Uint32()
  external int dwOffset;

  @Array(8)
  external Array<IntPtr> dwReserved;
}

/// Native C signature for WinMM `MidiInProc`.
typedef MidiInProcNative = Void Function(
  IntPtr hMidiIn,
  Uint32 wMsg,
  IntPtr dwInstance,
  IntPtr dwParam1,
  IntPtr dwParam2,
);

/// Dart signature corresponding to [MidiInProcNative].
typedef MidiInProcDart = void Function(
  int hMidiIn,
  int wMsg,
  int dwInstance,
  int dwParam1,
  int dwParam2,
);

/// Decodes a null-terminated UTF-16 `szPname` fixed array from WinMM caps structs.
String decodeWinMmPname(Array<Uint16> szPname, {int maxLen = MAXPNAMELEN}) {
  final codeUnits = <int>[];
  for (int i = 0; i < maxLen; i++) {
    final unit = szPname[i];
    if (unit == 0) {
      break;
    }
    codeUnits.add(unit);
  }
  return String.fromCharCodes(codeUnits).trim();
}

/// Abstract native binding contract for WinMM and Win32 heap calls.
///
/// Injecting a fake implementation enables deterministic, leak-checked unit
/// tests on non-Windows hosts without loading `winmm.dll` or `kernel32.dll`.
abstract class WinMmNativeBindings {
  Pointer<Void> heapAlloc(int byteCount);
  bool heapFree(Pointer<Void> ptr);

  int midiInGetNumDevs();
  int midiOutGetNumDevs();
  int midiInGetDevCaps(int uDeviceID, Pointer<MIDIINCAPSW> pmic, int cbmic);
  int midiOutGetDevCaps(int uDeviceID, Pointer<MIDIOUTCAPSW> pmoc, int cbmoc);

  int midiInOpen(
    Pointer<IntPtr> phmi,
    int uDeviceID,
    Pointer<NativeFunction<MidiInProcNative>> dwCallback,
    int dwInstance,
    int fdwOpen,
  );
  int midiInPrepareHeader(int hmi, Pointer<MIDIHDR> pmh, int cbmh);
  int midiInUnprepareHeader(int hmi, Pointer<MIDIHDR> pmh, int cbmh);
  int midiInAddBuffer(int hmi, Pointer<MIDIHDR> pmh, int cbmh);
  int midiInStart(int hmi);
  int midiInStop(int hmi);
  int midiInReset(int hmi);
  int midiInClose(int hmi);

  int midiOutOpen(
    Pointer<IntPtr> phmo,
    int uDeviceID,
    int dwCallback,
    int dwInstance,
    int fdwOpen,
  );
  int midiOutShortMsg(int hmo, int dwMsg);
  int midiOutPrepareHeader(int hmo, Pointer<MIDIHDR> pmh, int cbmh);
  int midiOutUnprepareHeader(int hmo, Pointer<MIDIHDR> pmh, int cbmh);
  int midiOutLongMsg(int hmo, Pointer<MIDIHDR> pmh, int cbmh);
  int midiOutReset(int hmo);
  int midiOutClose(int hmo);
}

// Native FFI signatures for kernel32.dll and winmm.dll.
typedef _GetProcessHeapNative = IntPtr Function();
typedef _GetProcessHeapDart = int Function();

typedef _HeapAllocNative = Pointer<Void> Function(
  IntPtr hHeap,
  Uint32 dwFlags,
  IntPtr dwBytes,
);
typedef _HeapAllocDart = Pointer<Void> Function(
  int hHeap,
  int dwFlags,
  int dwBytes,
);

typedef _HeapFreeNative = Int32 Function(
  IntPtr hHeap,
  Uint32 dwFlags,
  Pointer<Void> lpMem,
);
typedef _HeapFreeDart = int Function(
  int hHeap,
  int dwFlags,
  Pointer<Void> lpMem,
);

typedef _MidiGetNumDevsNative = Uint32 Function();
typedef _MidiGetNumDevsDart = int Function();

typedef _MidiInGetDevCapsWNative = Uint32 Function(
  UintPtr uDeviceID,
  Pointer<MIDIINCAPSW> pmic,
  Uint32 cbmic,
);
typedef _MidiInGetDevCapsWDart = int Function(
  int uDeviceID,
  Pointer<MIDIINCAPSW> pmic,
  int cbmic,
);

typedef _MidiOutGetDevCapsWNative = Uint32 Function(
  UintPtr uDeviceID,
  Pointer<MIDIOUTCAPSW> pmoc,
  Uint32 cbmoc,
);
typedef _MidiOutGetDevCapsWDart = int Function(
  int uDeviceID,
  Pointer<MIDIOUTCAPSW> pmoc,
  int cbmoc,
);

typedef _MidiInOpenNative = Uint32 Function(
  Pointer<IntPtr> phmi,
  Uint32 uDeviceID,
  Pointer<NativeFunction<MidiInProcNative>> dwCallback,
  IntPtr dwInstance,
  Uint32 fdwOpen,
);
typedef _MidiInOpenDart = int Function(
  Pointer<IntPtr> phmi,
  int uDeviceID,
  Pointer<NativeFunction<MidiInProcNative>> dwCallback,
  int dwInstance,
  int fdwOpen,
);

typedef _MidiInHeaderOpNative = Uint32 Function(
  IntPtr hmi,
  Pointer<MIDIHDR> pmh,
  Uint32 cbmh,
);
typedef _MidiInHeaderOpDart = int Function(
  int hmi,
  Pointer<MIDIHDR> pmh,
  int cbmh,
);

typedef _MidiHandleOpNative = Uint32 Function(IntPtr handle);
typedef _MidiHandleOpDart = int Function(int handle);

typedef _MidiOutOpenNative = Uint32 Function(
  Pointer<IntPtr> phmo,
  Uint32 uDeviceID,
  IntPtr dwCallback,
  IntPtr dwInstance,
  Uint32 fdwOpen,
);
typedef _MidiOutOpenDart = int Function(
  Pointer<IntPtr> phmo,
  int uDeviceID,
  int dwCallback,
  int dwInstance,
  int fdwOpen,
);

typedef _MidiOutShortMsgNative = Uint32 Function(IntPtr hmo, Uint32 dwMsg);
typedef _MidiOutShortMsgDart = int Function(int hmo, int dwMsg);

typedef _MidiOutHeaderOpNative = Uint32 Function(
  IntPtr hmo,
  Pointer<MIDIHDR> pmh,
  Uint32 cbmh,
);
typedef _MidiOutHeaderOpDart = int Function(
  int hmo,
  Pointer<MIDIHDR> pmh,
  int cbmh,
);

/// Pure `dart:ffi` implementation of [WinMmNativeBindings] backed by
/// `winmm.dll` and `kernel32.dll`.
class FfiWinMmNativeBindings implements WinMmNativeBindings {
  late final DynamicLibrary _kernel32;
  late final DynamicLibrary _winmm;
  late final int _processHeap;

  late final _HeapAllocDart _heapAlloc;
  late final _HeapFreeDart _heapFree;

  late final _MidiGetNumDevsDart _midiInGetNumDevs;
  late final _MidiGetNumDevsDart _midiOutGetNumDevs;
  late final _MidiInGetDevCapsWDart _midiInGetDevCapsW;
  late final _MidiOutGetDevCapsWDart _midiOutGetDevCapsW;
  late final _MidiInOpenDart _midiInOpen;
  late final _MidiInHeaderOpDart _midiInPrepareHeader;
  late final _MidiInHeaderOpDart _midiInUnprepareHeader;
  late final _MidiInHeaderOpDart _midiInAddBuffer;
  late final _MidiHandleOpDart _midiInStart;
  late final _MidiHandleOpDart _midiInStop;
  late final _MidiHandleOpDart _midiInReset;
  late final _MidiHandleOpDart _midiInClose;
  late final _MidiOutOpenDart _midiOutOpen;
  late final _MidiOutShortMsgDart _midiOutShortMsg;
  late final _MidiOutHeaderOpDart _midiOutPrepareHeader;
  late final _MidiOutHeaderOpDart _midiOutUnprepareHeader;
  late final _MidiOutHeaderOpDart _midiOutLongMsg;
  late final _MidiHandleOpDart _midiOutReset;
  late final _MidiHandleOpDart _midiOutClose;

  FfiWinMmNativeBindings() {
    if (!Platform.isWindows) {
      throw UnsupportedError('FfiWinMmNativeBindings is only supported on Windows.');
    }

    _kernel32 = DynamicLibrary.open('kernel32.dll');
    _winmm = DynamicLibrary.open('winmm.dll');

    final getProcessHeap = _kernel32
        .lookupFunction<_GetProcessHeapNative, _GetProcessHeapDart>('GetProcessHeap');
    _processHeap = getProcessHeap();

    _heapAlloc =
        _kernel32.lookupFunction<_HeapAllocNative, _HeapAllocDart>('HeapAlloc');
    _heapFree =
        _kernel32.lookupFunction<_HeapFreeNative, _HeapFreeDart>('HeapFree');

    _midiInGetNumDevs =
        _winmm.lookupFunction<_MidiGetNumDevsNative, _MidiGetNumDevsDart>(
            'midiInGetNumDevs');
    _midiOutGetNumDevs =
        _winmm.lookupFunction<_MidiGetNumDevsNative, _MidiGetNumDevsDart>(
            'midiOutGetNumDevs');
    _midiInGetDevCapsW =
        _winmm.lookupFunction<_MidiInGetDevCapsWNative, _MidiInGetDevCapsWDart>(
            'midiInGetDevCapsW');
    _midiOutGetDevCapsW =
        _winmm.lookupFunction<_MidiOutGetDevCapsWNative, _MidiOutGetDevCapsWDart>(
            'midiOutGetDevCapsW');
    _midiInOpen = _winmm
        .lookupFunction<_MidiInOpenNative, _MidiInOpenDart>('midiInOpen');
    _midiInPrepareHeader =
        _winmm.lookupFunction<_MidiInHeaderOpNative, _MidiInHeaderOpDart>(
            'midiInPrepareHeader');
    _midiInUnprepareHeader =
        _winmm.lookupFunction<_MidiInHeaderOpNative, _MidiInHeaderOpDart>(
            'midiInUnprepareHeader');
    _midiInAddBuffer =
        _winmm.lookupFunction<_MidiInHeaderOpNative, _MidiInHeaderOpDart>(
            'midiInAddBuffer');
    _midiInStart = _winmm
        .lookupFunction<_MidiHandleOpNative, _MidiHandleOpDart>('midiInStart');
    _midiInStop = _winmm
        .lookupFunction<_MidiHandleOpNative, _MidiHandleOpDart>('midiInStop');
    _midiInReset = _winmm
        .lookupFunction<_MidiHandleOpNative, _MidiHandleOpDart>('midiInReset');
    _midiInClose = _winmm
        .lookupFunction<_MidiHandleOpNative, _MidiHandleOpDart>('midiInClose');
    _midiOutOpen = _winmm
        .lookupFunction<_MidiOutOpenNative, _MidiOutOpenDart>('midiOutOpen');
    _midiOutShortMsg =
        _winmm.lookupFunction<_MidiOutShortMsgNative, _MidiOutShortMsgDart>(
            'midiOutShortMsg');
    _midiOutPrepareHeader =
        _winmm.lookupFunction<_MidiOutHeaderOpNative, _MidiOutHeaderOpDart>(
            'midiOutPrepareHeader');
    _midiOutUnprepareHeader =
        _winmm.lookupFunction<_MidiOutHeaderOpNative, _MidiOutHeaderOpDart>(
            'midiOutUnprepareHeader');
    _midiOutLongMsg =
        _winmm.lookupFunction<_MidiOutHeaderOpNative, _MidiOutHeaderOpDart>(
            'midiOutLongMsg');
    _midiOutReset = _winmm
        .lookupFunction<_MidiHandleOpNative, _MidiHandleOpDart>('midiOutReset');
    _midiOutClose = _winmm
        .lookupFunction<_MidiHandleOpNative, _MidiHandleOpDart>('midiOutClose');
  }

  @override
  Pointer<Void> heapAlloc(int byteCount) =>
      _heapAlloc(_processHeap, HEAP_ZERO_MEMORY, byteCount);

  @override
  bool heapFree(Pointer<Void> ptr) => _heapFree(_processHeap, 0, ptr) != 0;

  @override
  int midiInGetNumDevs() => _midiInGetNumDevs();

  @override
  int midiOutGetNumDevs() => _midiOutGetNumDevs();

  @override
  int midiInGetDevCaps(int uDeviceID, Pointer<MIDIINCAPSW> pmic, int cbmic) =>
      _midiInGetDevCapsW(uDeviceID, pmic, cbmic);

  @override
  int midiOutGetDevCaps(int uDeviceID, Pointer<MIDIOUTCAPSW> pmoc, int cbmoc) =>
      _midiOutGetDevCapsW(uDeviceID, pmoc, cbmoc);

  @override
  int midiInOpen(
    Pointer<IntPtr> phmi,
    int uDeviceID,
    Pointer<NativeFunction<MidiInProcNative>> dwCallback,
    int dwInstance,
    int fdwOpen,
  ) =>
      _midiInOpen(phmi, uDeviceID, dwCallback, dwInstance, fdwOpen);

  @override
  int midiInPrepareHeader(int hmi, Pointer<MIDIHDR> pmh, int cbmh) =>
      _midiInPrepareHeader(hmi, pmh, cbmh);

  @override
  int midiInUnprepareHeader(int hmi, Pointer<MIDIHDR> pmh, int cbmh) =>
      _midiInUnprepareHeader(hmi, pmh, cbmh);

  @override
  int midiInAddBuffer(int hmi, Pointer<MIDIHDR> pmh, int cbmh) =>
      _midiInAddBuffer(hmi, pmh, cbmh);

  @override
  int midiInStart(int hmi) => _midiInStart(hmi);

  @override
  int midiInStop(int hmi) => _midiInStop(hmi);

  @override
  int midiInReset(int hmi) => _midiInReset(hmi);

  @override
  int midiInClose(int hmi) => _midiInClose(hmi);

  @override
  int midiOutOpen(
    Pointer<IntPtr> phmo,
    int uDeviceID,
    int dwCallback,
    int dwInstance,
    int fdwOpen,
  ) =>
      _midiOutOpen(phmo, uDeviceID, dwCallback, dwInstance, fdwOpen);

  @override
  int midiOutShortMsg(int hmo, int dwMsg) => _midiOutShortMsg(hmo, dwMsg);

  @override
  int midiOutPrepareHeader(int hmo, Pointer<MIDIHDR> pmh, int cbmh) =>
      _midiOutPrepareHeader(hmo, pmh, cbmh);

  @override
  int midiOutUnprepareHeader(int hmo, Pointer<MIDIHDR> pmh, int cbmh) =>
      _midiOutUnprepareHeader(hmo, pmh, cbmh);

  @override
  int midiOutLongMsg(int hmo, Pointer<MIDIHDR> pmh, int cbmh) =>
      _midiOutLongMsg(hmo, pmh, cbmh);

  @override
  int midiOutReset(int hmo) => _midiOutReset(hmo);

  @override
  int midiOutClose(int hmo) => _midiOutClose(hmo);
}

class _WinMmEndpoint {
  final int deviceId;
  final String rawName;
  final String displayName;
  final String normalizedKey;

  const _WinMmEndpoint({
    required this.deviceId,
    required this.rawName,
    required this.displayName,
    required this.normalizedKey,
  });
}

class _WinMmInputBuffer {
  final Pointer<MIDIHDR> header;
  final Pointer<Uint8> data;
  bool isPrepared = false;

  _WinMmInputBuffer({required this.header, required this.data});
}

class _ParsedWinMmPortId {
  final int? inputDeviceId;
  final int? outputDeviceId;

  const _ParsedWinMmPortId({this.inputDeviceId, this.outputDeviceId});
}

/// Convenience alias matching the milestone naming convention.
typedef WindowsWinMmMidiTransport = WinMmMidiTransport;

/// Zero-dependency Windows native MIDI transport backed by `winmm.dll` via `dart:ffi`.
///
/// Discovers WinMM input/output endpoints, pairs matching endpoints into unified
/// bidirectional [MidiPortDescriptor]s, streams incoming short and multi-buffer SysEx
/// messages via `NativeCallable.listener`, and sends outgoing short and SysEx frames.
class WinMmMidiTransport extends MidiTransport {
  final WinMmNativeBindings? _bindingsOverride;
  WinMmNativeBindings? _cachedBindings;
  final bool _isWindows;
  final int inputBufferCount;
  final int inputBufferSize;
  final Duration sysexPollInterval;
  final Duration sysexSendTimeout;

  final StreamController<MidiMessage> _incomingController =
      StreamController<MidiMessage>.broadcast(sync: true);

  bool _isConnected = false;
  bool _isClosing = false;
  MidiPortDescriptor? _connectedPort;

  int? _hMidiIn;
  int? _hMidiOut;
  NativeCallable<MidiInProcNative>? _midiInCallable;
  final List<_WinMmInputBuffer> _inputBuffers = [];
  final Map<int, _WinMmInputBuffer> _inputBufferByAddr = {};
  final List<int> _sysexRxBuffer = [];
  Future<void> _sendLock = Future<void>.value();

  WinMmMidiTransport({
    WinMmNativeBindings? bindings,
    bool? isWindows,
    this.inputBufferCount = 8,
    this.inputBufferSize = 2048,
    this.sysexPollInterval = const Duration(milliseconds: 1),
    this.sysexSendTimeout = const Duration(seconds: 2),
  })  : _bindingsOverride = bindings,
        _isWindows = isWindows ?? Platform.isWindows;

  WinMmNativeBindings get _bindings {
    if (_bindingsOverride != null) {
      return _bindingsOverride;
    }
    return _cachedBindings ??= FfiWinMmNativeBindings();
  }

  @override
  bool get isConnected => _isConnected;

  @override
  MidiPortDescriptor? get connectedPort => _connectedPort;

  @override
  Stream<MidiMessage> get onMessageReceived => _incomingController.stream;

  /// Normalizes Windows WinMM endpoint names by removing `MIDIIN<n>` / `MIDIOUT<n>`
  /// driver wrapper prefixes so matching input and output endpoints pair cleanly.
  @visibleForTesting
  static String normalizeDeviceName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final wrappedMatch = RegExp(
      r'^MIDI(?:IN|OUT)\d*\s*\((.+)\)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (wrappedMatch != null) {
      final inner = wrappedMatch.group(1)!.trim();
      if (inner.isNotEmpty) {
        return inner;
      }
    }

    final prefixMatch = RegExp(
      r'^MIDI(?:IN|OUT)\d+[\s:_-]+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (prefixMatch != null) {
      final rest = prefixMatch.group(1)!.trim();
      if (rest.isNotEmpty) {
        return rest;
      }
    }

    return trimmed;
  }

  static String? _inferManufacturer(String name) {
    final upper = name.toUpperCase();
    if (upper.contains('ZOOM')) {
      return 'Zoom Corporation';
    }
    if (upper.contains('LINE 6') ||
        upper.contains('LINE6') ||
        upper.contains('BASS POD')) {
      return 'Line 6';
    }
    return null;
  }

  static _ParsedWinMmPortId? _parsePortId(String portId) {
    final bothMatch = RegExp(r'^winmm:in:(\d+)\|out:(\d+)$').firstMatch(portId);
    if (bothMatch != null) {
      return _ParsedWinMmPortId(
        inputDeviceId: int.parse(bothMatch.group(1)!),
        outputDeviceId: int.parse(bothMatch.group(2)!),
      );
    }

    final inMatch = RegExp(r'^winmm:in:(\d+)$').firstMatch(portId);
    if (inMatch != null) {
      return _ParsedWinMmPortId(
        inputDeviceId: int.parse(inMatch.group(1)!),
      );
    }

    final outMatch = RegExp(r'^winmm:out:(\d+)$').firstMatch(portId);
    if (outMatch != null) {
      return _ParsedWinMmPortId(
        outputDeviceId: int.parse(outMatch.group(1)!),
      );
    }

    return null;
  }

  @override
  Future<List<MidiPortDescriptor>> getAvailablePorts() async {
    if (!_isWindows) {
      return const [];
    }

    final bindings = _bindings;
    final inputs = _enumerateInputEndpoints(bindings);
    final outputs = _enumerateOutputEndpoints(bindings);

    final matchedOutputs = List<bool>.filled(outputs.length, false);
    final descriptors = <MidiPortDescriptor>[];

    for (final input in inputs) {
      int matchIndex = -1;
      for (int i = 0; i < outputs.length; i++) {
        if (!matchedOutputs[i] &&
            outputs[i].normalizedKey.isNotEmpty &&
            outputs[i].normalizedKey == input.normalizedKey) {
          matchIndex = i;
          break;
        }
      }

      if (matchIndex != -1) {
        matchedOutputs[matchIndex] = true;
        final output = outputs[matchIndex];
        final displayName = output.displayName.isNotEmpty
            ? output.displayName
            : input.displayName;
        descriptors.add(MidiPortDescriptor(
          id: 'winmm:in:${input.deviceId}|out:${output.deviceId}',
          name: displayName,
          manufacturer: _inferManufacturer(displayName),
          isInput: true,
          isOutput: true,
        ));
      } else {
        descriptors.add(MidiPortDescriptor(
          id: 'winmm:in:${input.deviceId}',
          name: input.displayName,
          manufacturer: _inferManufacturer(input.displayName),
          isInput: true,
          isOutput: false,
        ));
      }
    }

    for (int i = 0; i < outputs.length; i++) {
      if (!matchedOutputs[i]) {
        final output = outputs[i];
        descriptors.add(MidiPortDescriptor(
          id: 'winmm:out:${output.deviceId}',
          name: output.displayName,
          manufacturer: _inferManufacturer(output.displayName),
          isInput: false,
          isOutput: true,
        ));
      }
    }

    return List.unmodifiable(descriptors);
  }

  List<_WinMmEndpoint> _enumerateInputEndpoints(WinMmNativeBindings bindings) {
    final count = bindings.midiInGetNumDevs();
    if (count <= 0) {
      return const [];
    }

    final capsPtr = bindings.heapAlloc(sizeOf<MIDIINCAPSW>()).cast<MIDIINCAPSW>();
    if (capsPtr.address == 0) {
      return const [];
    }

    final endpoints = <_WinMmEndpoint>[];
    try {
      for (int id = 0; id < count; id++) {
        final res = bindings.midiInGetDevCaps(id, capsPtr, sizeOf<MIDIINCAPSW>());
        if (res == MMSYSERR_NOERROR) {
          final rawName = decodeWinMmPname(capsPtr.ref.szPname);
          final displayName = normalizeDeviceName(rawName);
          final fallbackName =
              displayName.isNotEmpty ? displayName : 'WinMM MIDI In $id';
          endpoints.add(_WinMmEndpoint(
            deviceId: id,
            rawName: rawName,
            displayName: fallbackName,
            normalizedKey: fallbackName.toLowerCase(),
          ));
        }
      }
    } finally {
      bindings.heapFree(capsPtr.cast<Void>());
    }
    return endpoints;
  }

  List<_WinMmEndpoint> _enumerateOutputEndpoints(WinMmNativeBindings bindings) {
    final count = bindings.midiOutGetNumDevs();
    if (count <= 0) {
      return const [];
    }

    final capsPtr =
        bindings.heapAlloc(sizeOf<MIDIOUTCAPSW>()).cast<MIDIOUTCAPSW>();
    if (capsPtr.address == 0) {
      return const [];
    }

    final endpoints = <_WinMmEndpoint>[];
    try {
      for (int id = 0; id < count; id++) {
        final res =
            bindings.midiOutGetDevCaps(id, capsPtr, sizeOf<MIDIOUTCAPSW>());
        if (res == MMSYSERR_NOERROR) {
          final rawName = decodeWinMmPname(capsPtr.ref.szPname);
          final displayName = normalizeDeviceName(rawName);
          final fallbackName =
              displayName.isNotEmpty ? displayName : 'WinMM MIDI Out $id';
          endpoints.add(_WinMmEndpoint(
            deviceId: id,
            rawName: rawName,
            displayName: fallbackName,
            normalizedKey: fallbackName.toLowerCase(),
          ));
        }
      }
    } finally {
      bindings.heapFree(capsPtr.cast<Void>());
    }
    return endpoints;
  }

  @override
  Future<void> connect(String portId) async {
    if (!_isWindows) {
      throw UnsupportedError(
        'WinMmMidiTransport is only supported on Windows.',
      );
    }

    if (_isConnected) {
      await disconnect();
    }

    final available = await getAvailablePorts();
    MidiPortDescriptor? descriptor;
    for (final port in available) {
      if (port.id == portId) {
        descriptor = port;
        break;
      }
    }

    final parsed = _parsePortId(portId);
    if (descriptor == null || parsed == null) {
      throw ArgumentError('WinMM MIDI port "$portId" not found.');
    }

    _isClosing = false;
    _sysexRxBuffer.clear();
    final bindings = _bindings;

    try {
      if (parsed.inputDeviceId != null) {
        _openInputDevice(bindings, parsed.inputDeviceId!);
      }
      if (parsed.outputDeviceId != null) {
        _openOutputDevice(bindings, parsed.outputDeviceId!);
      }

      _connectedPort = descriptor;
      _isConnected = true;
    } catch (e) {
      await _teardownNativeResources();
      _isConnected = false;
      _connectedPort = null;
      if (e is StateError) {
        rethrow;
      }
      throw StateError('Failed to connect WinMM port "$portId": $e');
    }
  }

  void _openInputDevice(WinMmNativeBindings bindings, int deviceId) {
    final handlePtr = bindings.heapAlloc(sizeOf<IntPtr>()).cast<IntPtr>();
    if (handlePtr.address == 0) {
      throw StateError('Failed to allocate WinMM input handle storage.');
    }

    try {
      _midiInCallable = NativeCallable<MidiInProcNative>.listener(
        _handleMidiInCallback,
      );
      final openResult = bindings.midiInOpen(
        handlePtr,
        deviceId,
        _midiInCallable!.nativeFunction,
        0,
        CALLBACK_FUNCTION,
      );
      if (openResult != MMSYSERR_NOERROR) {
        throw StateError(
          'midiInOpen($deviceId) failed with MMRESULT $openResult.',
        );
      }
      _hMidiIn = handlePtr.value;
    } finally {
      bindings.heapFree(handlePtr.cast<Void>());
    }

    for (int i = 0; i < inputBufferCount; i++) {
      final dataPtr = bindings.heapAlloc(inputBufferSize).cast<Uint8>();
      if (dataPtr.address == 0) {
        throw StateError('Failed to allocate WinMM input SysEx data buffer.');
      }
      final hdrPtr = bindings.heapAlloc(sizeOf<MIDIHDR>()).cast<MIDIHDR>();
      if (hdrPtr.address == 0) {
        bindings.heapFree(dataPtr.cast<Void>());
        throw StateError('Failed to allocate WinMM input MIDIHDR.');
      }

      hdrPtr.ref.lpData = dataPtr;
      hdrPtr.ref.dwBufferLength = inputBufferSize;
      hdrPtr.ref.dwBytesRecorded = 0;
      hdrPtr.ref.dwFlags = 0;

      final entry = _WinMmInputBuffer(header: hdrPtr, data: dataPtr);
      _inputBuffers.add(entry);
      _inputBufferByAddr[hdrPtr.address] = entry;

      final prepRes =
          bindings.midiInPrepareHeader(_hMidiIn!, hdrPtr, sizeOf<MIDIHDR>());
      if (prepRes != MMSYSERR_NOERROR) {
        throw StateError(
          'midiInPrepareHeader failed with MMRESULT $prepRes.',
        );
      }
      entry.isPrepared = true;

      final addRes =
          bindings.midiInAddBuffer(_hMidiIn!, hdrPtr, sizeOf<MIDIHDR>());
      if (addRes != MMSYSERR_NOERROR) {
        throw StateError('midiInAddBuffer failed with MMRESULT $addRes.');
      }
    }

    final startRes = bindings.midiInStart(_hMidiIn!);
    if (startRes != MMSYSERR_NOERROR) {
      throw StateError('midiInStart failed with MMRESULT $startRes.');
    }
  }

  void _openOutputDevice(WinMmNativeBindings bindings, int deviceId) {
    final handlePtr = bindings.heapAlloc(sizeOf<IntPtr>()).cast<IntPtr>();
    if (handlePtr.address == 0) {
      throw StateError('Failed to allocate WinMM output handle storage.');
    }

    try {
      final openResult = bindings.midiOutOpen(
        handlePtr,
        deviceId,
        0,
        0,
        CALLBACK_NULL,
      );
      if (openResult != MMSYSERR_NOERROR) {
        throw StateError(
          'midiOutOpen($deviceId) failed with MMRESULT $openResult.',
        );
      }
      _hMidiOut = handlePtr.value;
    } finally {
      bindings.heapFree(handlePtr.cast<Void>());
    }
  }

  void _handleMidiInCallback(
    int hMidiIn,
    int wMsg,
    int dwInstance,
    int dwParam1,
    int dwParam2,
  ) {
    if (_isClosing) {
      return;
    }

    if (wMsg == MIM_DATA) {
      final status = dwParam1 & 0xFF;
      final data1 = (dwParam1 >> 8) & 0xFF;
      final data2 = (dwParam1 >> 16) & 0xFF;

      final expectedLen = _expectedShortMessageLength(status);
      if (expectedLen == 1) {
        _emitMessage(Uint8List.fromList([status]));
      } else if (expectedLen == 2) {
        _emitMessage(Uint8List.fromList([status, data1]));
      } else if (expectedLen == 3) {
        _emitMessage(Uint8List.fromList([status, data1, data2]));
      }
      return;
    }

    if (wMsg == MIM_LONGDATA || wMsg == MIM_LONGERROR) {
      if (dwParam1 == 0 || !_inputBufferByAddr.containsKey(dwParam1)) {
        return;
      }

      final hdrPtr = Pointer<MIDIHDR>.fromAddress(dwParam1);
      final bytesRecorded = hdrPtr.ref.dwBytesRecorded;
      if (wMsg == MIM_LONGDATA && bytesRecorded > 0 && hdrPtr.ref.lpData.address != 0) {
        final chunk = hdrPtr.ref.lpData.asTypedList(bytesRecorded);
        _sysexRxBuffer.addAll(chunk);
        _drainCompletedSysExMessages();
      }

      if (!_isClosing && _hMidiIn != null) {
        hdrPtr.ref.dwBytesRecorded = 0;
        hdrPtr.ref.dwFlags &= ~MHDR_DONE;
        _bindings.midiInAddBuffer(_hMidiIn!, hdrPtr, sizeOf<MIDIHDR>());
      }
    }
  }

  static int _expectedShortMessageLength(int status) {
    if (status < 0x80) {
      return 0;
    }
    final statusNibble = status & 0xF0;
    if (statusNibble == 0xC0 || statusNibble == 0xD0) {
      return 2;
    }
    if (statusNibble >= 0x80 && statusNibble <= 0xE0) {
      return 3;
    }
    if (status == 0xF1 || status == 0xF3) {
      return 2;
    }
    if (status == 0xF2) {
      return 3;
    }
    if (status == 0xF6 || (status >= 0xF8 && status <= 0xFF)) {
      return 1;
    }
    return 0;
  }

  void _drainCompletedSysExMessages() {
    int cursor = 0;
    while (cursor < _sysexRxBuffer.length) {
      if (_sysexRxBuffer[cursor] != 0xF0) {
        cursor++;
        continue;
      }

      int endIndex = -1;
      int? restartIndex;
      for (int i = cursor + 1; i < _sysexRxBuffer.length; i++) {
        final byte = _sysexRxBuffer[i];
        if (byte == 0xF7) {
          endIndex = i;
          break;
        }
        if (byte == 0xF0) {
          restartIndex = i;
          break;
        }
      }

      if (restartIndex != null) {
        cursor = restartIndex;
        continue;
      }
      if (endIndex == -1) {
        break;
      }

      final frame = Uint8List.fromList(_sysexRxBuffer.sublist(cursor, endIndex + 1));
      _emitMessage(frame);
      cursor = endIndex + 1;
    }

    if (cursor > 0) {
      _sysexRxBuffer.removeRange(0, cursor);
    }
  }

  void _emitMessage(Uint8List bytes) {
    if (!_incomingController.isClosed) {
      _incomingController.add(MidiMessage(bytes, timestamp: DateTime.now()));
    }
  }

  @override
  Future<void> send(MidiMessage message) async {
    if (!_isConnected || _isClosing || _hMidiOut == null) {
      throw StateError(
        'Cannot send message: WinMmMidiTransport output is not connected.',
      );
    }

    final data = message.data;
    if (data.isEmpty) {
      throw ArgumentError('Cannot send an empty MIDI message.');
    }

    if (message.isSysEx || data.first == 0xF0) {
      await _sendSysExSerialized(data);
      return;
    }

    if (data.length > 3) {
      throw ArgumentError(
        'Non-SysEx MIDI message exceeds 3 bytes (${data.length} bytes).',
      );
    }

    int packed = data[0] & 0xFF;
    if (data.length >= 2) {
      packed |= (data[1] & 0xFF) << 8;
    }
    if (data.length >= 3) {
      packed |= (data[2] & 0xFF) << 16;
    }

    final result = _bindings.midiOutShortMsg(_hMidiOut!, packed);
    if (result != MMSYSERR_NOERROR) {
      throw StateError('midiOutShortMsg failed with MMRESULT $result.');
    }
  }

  Future<void> _sendSysExSerialized(Uint8List data) {
    final previous = _sendLock.catchError((_) {});
    final completer = Completer<void>();
    _sendLock = completer.future;

    return previous.then((_) => _sendSysEx(data)).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }

  Future<void> _sendSysEx(Uint8List data) async {
    if (!_isConnected || _isClosing || _hMidiOut == null) {
      throw StateError(
        'Cannot send SysEx: WinMmMidiTransport output is not connected.',
      );
    }

    final bindings = _bindings;
    final hOut = _hMidiOut!;
    Pointer<Uint8> dataPtr = Pointer<Uint8>.fromAddress(0);
    Pointer<MIDIHDR> hdrPtr = Pointer<MIDIHDR>.fromAddress(0);
    bool prepared = false;

    try {
      dataPtr = bindings.heapAlloc(data.length).cast<Uint8>();
      if (dataPtr.address == 0) {
        throw StateError('Failed to allocate WinMM SysEx payload buffer.');
      }
      dataPtr.asTypedList(data.length).setAll(0, data);

      hdrPtr = bindings.heapAlloc(sizeOf<MIDIHDR>()).cast<MIDIHDR>();
      if (hdrPtr.address == 0) {
        throw StateError('Failed to allocate WinMM SysEx MIDIHDR.');
      }

      hdrPtr.ref.lpData = dataPtr;
      hdrPtr.ref.dwBufferLength = data.length;
      hdrPtr.ref.dwBytesRecorded = data.length;
      hdrPtr.ref.dwFlags = 0;

      final prepRes =
          bindings.midiOutPrepareHeader(hOut, hdrPtr, sizeOf<MIDIHDR>());
      if (prepRes != MMSYSERR_NOERROR) {
        throw StateError(
          'midiOutPrepareHeader failed with MMRESULT $prepRes.',
        );
      }
      prepared = true;

      final sendRes = bindings.midiOutLongMsg(hOut, hdrPtr, sizeOf<MIDIHDR>());
      if (sendRes != MMSYSERR_NOERROR) {
        throw StateError('midiOutLongMsg failed with MMRESULT $sendRes.');
      }

      final deadline = DateTime.now().add(sysexSendTimeout);
      while ((hdrPtr.ref.dwFlags & MHDR_DONE) == 0) {
        if (_isClosing || _hMidiOut == null) {
          throw StateError(
            'WinMmMidiTransport disconnected while waiting for SysEx completion.',
          );
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            'Timed out waiting for WinMM SysEx transmission completion.',
            sysexSendTimeout,
          );
        }
        await Future<void>.delayed(sysexPollInterval);
      }
    } finally {
      if (prepared && _hMidiOut != null) {
        bindings.midiOutUnprepareHeader(_hMidiOut!, hdrPtr, sizeOf<MIDIHDR>());
      }
      if (hdrPtr.address != 0) {
        bindings.heapFree(hdrPtr.cast<Void>());
      }
      if (dataPtr.address != 0) {
        bindings.heapFree(dataPtr.cast<Void>());
      }
    }
  }

  Future<void> _teardownNativeResources() async {
    _isClosing = true;
    final bindings = _bindingsOverride ?? _cachedBindings;

    if (bindings != null) {
      final hIn = _hMidiIn;
      if (hIn != null) {
        bindings.midiInStop(hIn);
        bindings.midiInReset(hIn);
      }

      // Allow any already-posted NativeCallable.listener callbacks from
      // midiInReset to drain harmlessly while _isClosing == true before
      // closing the callable and freeing native MIDIHDR memory.
      await Future<void>.delayed(Duration.zero);

      _midiInCallable?.close();
      _midiInCallable = null;

      if (hIn != null) {
        for (final entry in _inputBuffers) {
          if (entry.isPrepared) {
            bindings.midiInUnprepareHeader(hIn, entry.header, sizeOf<MIDIHDR>());
            entry.isPrepared = false;
          }
          bindings.heapFree(entry.data.cast<Void>());
          bindings.heapFree(entry.header.cast<Void>());
        }
        _inputBuffers.clear();
        _inputBufferByAddr.clear();

        bindings.midiInClose(hIn);
        _hMidiIn = null;
      } else {
        for (final entry in _inputBuffers) {
          bindings.heapFree(entry.data.cast<Void>());
          bindings.heapFree(entry.header.cast<Void>());
        }
        _inputBuffers.clear();
        _inputBufferByAddr.clear();
      }

      final hOut = _hMidiOut;
      if (hOut != null) {
        bindings.midiOutReset(hOut);
        bindings.midiOutClose(hOut);
        _hMidiOut = null;
      }
    } else {
      _midiInCallable?.close();
      _midiInCallable = null;
      _inputBuffers.clear();
      _inputBufferByAddr.clear();
      _hMidiIn = null;
      _hMidiOut = null;
    }

    _sysexRxBuffer.clear();
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPort = null;
    await _teardownNativeResources();
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    if (!_incomingController.isClosed) {
      await _incomingController.close();
    }
  }
}
