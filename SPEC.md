# Technical Architecture Specification: `signal_chain_flutter`

## 1. Architectural Overview & Layering

The codebase is organized strictly under Clean Architecture principles to ensure complete platform independence, full unit-testability of protocol logic without hardware or plugins, and predictable state transitions.

```
lib/
├── core/
│   ├── export/             # ExportAdapter registry, format serializers & file writer
│   ├── import/             # ImportAdapter decoders, PatchImporter & ImportFileSystem
│   ├── midi/               # Abstract transport contracts & testing doubles
│   └── storage/            # Pure dart:io preset library & preferences repositories
├── protocols/              # Pure Dart SysEx encoders, decoders, bit-packers
├── models/                 # Immutable domain models (devices, patches, FX, params)
└── features/               # Presentation layer & Riverpod state controllers
    ├── connection/         # Device discovery & port lifecycle
    ├── editor/             # Active patch editing & real-time sync
    └── library/            # Local preset banks & storage persistence
```

---

## 2. Core MIDI Abstraction Layer (`lib/core/midi/`)

The MIDI layer decouples all protocol encoders/decoders and UI logic from platform-specific MIDI APIs (ALSA, WinMM, CoreMIDI, Android USB/BLE).

### 2.1 Core Contracts

#### `MidiPortDescriptor`
```dart
class MidiPortDescriptor {
  final String id;
  final String name;
  final String? manufacturer;
  final MidiPortType type; // input, output
  final bool isConnected;
  
  const MidiPortDescriptor({
    required this.id,
    required this.name,
    this.manufacturer,
    required this.type,
    this.isConnected = false,
  });
}
```

#### `MidiMessage`
```dart
class MidiMessage {
  final Uint8List data;
  final DateTime timestamp;

  const MidiMessage(this.data, {required this.timestamp});
}
```

#### `MidiTransport` (Abstract Interface)
```dart
abstract class MidiTransport {
  Stream<List<MidiPortDescriptor>> get availablePorts;
  Stream<MidiMessage> get incomingMessages;
  Stream<MidiConnectionState> get connectionState;

  Future<void> initialize();
  Future<void> connect(MidiPortDescriptor inputPort, MidiPortDescriptor outputPort);
  Future<void> disconnect();
  Future<void> send(Uint8List data);
  Future<void> dispose();
}
```

### 2.2 Test Doubles (`MockMidiTransport`)
- **Deterministic Loopback & Fixture Playback:** Allows feeding pre-recorded raw SysEx messages into `incomingMessages` on demand.
- **Outgoing Buffer Assertion:** Stores transmitted byte frames in a history log for unit test verification (verifying correct handshake byte strings, parameter change messages, etc.).
- **Latency / Error Simulation:** Simulates dropped packets, fragmented SysEx chunks, and disconnection events.

### 2.3 Zero-Dependency Linux ALSA RawMIDI Transport (`LinuxAlsaMidiTransport`)
- **Port Discovery (`getAvailablePorts()`):**
  * Parses `amidi -l` stdout into `MidiPortDescriptor` hardware ports with device ID (`hw:X,Y,Z`), hardware labels, and `I`/`O`/`IO` direction flags.
  * Gracefully falls back to `/proc/asound/cards` and `/dev/snd/midiC*D*` when `amidi` is uninstalled or restricted.
- **Background Stream Reassembly:**
  * Background `amidi -p <port> -d` process streaming hex bytes from stdout.
  * Reassembles fragmented multi-line SysEx (`F0 ... F7`), Continuous Controller (`B0 cc vv`), and Program Change (`C0 pp`) messages without data loss.
  * Real-Time Stream Tokenization (`feedHexStream`): Immediately processes complete 2-hex-digit tokens without waiting for trailing whitespace or newlines. Only 1-character fragments at stream boundaries are retained, eliminating the single-action lag where terminating `F7` bytes would otherwise remain buffered until subsequent hardware events.
- **Outbound Transmission:**
  * Formats byte payloads into uppercase hex strings dispatched via `amidi -p <port> -S "<hex>"`.
- **Process Lifecycle Safety:**
  * Cleanly kills background listener process on `disconnect()` or `dispose()`.
  * Fully injectable `ProcessRunner` and `ProcessStarter` enabling deterministic offline unit tests.

### 2.4 Zero-Dependency Windows Native WinMM Transport (`WinMmMidiTransport`)
- **Pure `dart:ffi` Native Bindings (`WinMmNativeBindings` / `FfiWinMmNativeBindings`):**
  * Uses only `dart:ffi`, `dart:io`, and `package:flutter/foundation.dart` (zero third-party `pub.dev` packages).
  * Opens `winmm.dll` and `kernel32.dll` (`GetProcessHeap`, `HeapAlloc` with `HEAP_ZERO_MEMORY`, `HeapFree`) lazily only on Windows.
  * Defines Win32 `MIDIINCAPSW`, `MIDIOUTCAPSW`, and `MIDIHDR` structs and decodes UTF-16 `szPname` (`MAXPNAMELEN = 32`) up to the null terminator.
- **Endpoint Enumeration & Pairing (`getAvailablePorts()`):**
  * Queries `midiInGetNumDevs`/`midiInGetDevCapsW` and `midiOutGetNumDevs`/`midiOutGetDevCapsW`.
  * Normalizes `MIDIIN<n>` / `MIDIOUT<n>` driver prefixes and pairs matching input and output endpoints 1-to-1 in ordinal order (supporting duplicate connected pedals as well as unpaired input-only or output-only endpoints).
- **Outbound Short & SysEx Transmission:**
  * Packs 1-, 2-, and 3-byte short messages into a little-endian `DWORD` via `midiOutShortMsg`.
  * Serializes outgoing SysEx frames (`0xF0 ... 0xF7`) using heap-allocated `MIDIHDR` buffers (`midiOutPrepareHeader` -> `midiOutLongMsg` -> poll `MHDR_DONE` -> `midiOutUnprepareHeader`) with `finally` cleanup.
- **Inbound `NativeCallable.listener` & Ring Buffer SysEx Reassembly:**
  * Registers a `NativeCallable<MidiInProcNative>.listener` callback backed by pre-queued `MIDIHDR` input buffers (`midiInPrepareHeader` + `midiInAddBuffer`).
  * Emits 1-, 2-, and 3-byte `MIM_DATA` messages and reassembles single- and multi-buffer `MIM_LONGDATA` SysEx dumps until `0xF7`, re-queueing processed buffers while active.
- **Rollback & Deadlock-Free Teardown:**
  * Rolls back input handles and prepared buffers if `midiOutOpen` fails during `connect()`.
  * On `disconnect()` / `dispose()`, sets `_isClosing = true` prior to `midiInStop` and `midiInReset` so flushed buffers are never re-queued, closes the `NativeCallable`, unprepares headers, closes handles, and frees every native heap allocation.

### 2.5 Composite Transport Architecture (`CompositeMidiTransport`)
- Aggregates multiple `MidiTransport` implementations (e.g., `LinuxAlsaMidiTransport`, `AndroidMidiTransport`, or `WinMmMidiTransport` + `MockMidiTransport`) into a unified surface.
- Discovers ports across all underlying transports concurrently.
- Automatically routes `connect`, `send`, `onMessageReceived`, and `disconnect` calls to the transport managing the target port.

---

## 3. Pure Dart Protocol & SysEx Engine (`lib/protocols/`)

All protocol modules are implemented in pure Dart using `dart:typed_data` (`Uint8List`, `ByteData`) with **zero Flutter or third-party platform imports**.

### 3.1 Common MIDI Utilities
- **SysEx Framing:** Framing detection (`0xF0` ... `0xF7`), message slicing, checksum validation, and stream reassembly for multi-packet dumps.
- **7-bit / 8-bit Packing:**
  * Standard MIDI transmits data bytes in the range `0x00`–`0x7F` (MSB = 0).
  * 8-bit binary payloads (firmware, DSP parameters, names) must be packed using high-bit grouping (7 raw bytes packed into 8 MIDI bytes, with the 1st byte storing the MSBs).
  * Pure Dart `BytePacker` utility provides symmetrical `pack7to8(Uint8List raw)` and `unpack8to7(Uint8List packed)`.

---

### 3.2 Zoom MS Plus Series Protocol (`lib/protocols/zoom_ms_plus_protocol.dart`)

#### Supported Devices
- Zoom MS-50G+ (Model code `0x23`)
- Zoom MS-60B+ (Model code `0x27`)
- Zoom MS-70CDR+ (Model code `0x26`)
- Zoom MS-200D+ (Model code `0x25`)

#### Protocol Specifications
1. **Device Inquiry / Handshake:**
   - Universal Non-Real-Time SysEx Identity Request: `F0 7E 7F 06 01 F7`
   - Identity Reply format: `F0 7E <channel> 06 02 52 6E 00 <model_lsb> <model_msb> <version...> F7`
     * Manufacturer ID: `0x52` (Zoom)
     * Family Code: `0x6E 0x00` (MS Plus series)
     * Model LSB: `0x23` (MS-50G+), `0x25` (MS-200D+), `0x26` (MS-70CDR+), `0x27` (MS-60B+)
2. **Editor & PC Mode Activation & Warm Handshake Pacing:**
   - Parameter Edit Enable: `F0 52 00 6E 50 F7` (Disable: `F0 52 00 6E 51 F7`)
   - PC Mode Enable: `F0 52 00 6E 52 F7` (Disable: `F0 52 00 6E 53 F7`)
   - Initialization Sequence: `0x53` (PC Mode Disable) -> `0x50` (Parameter Edit Enable) -> `0x33` (Request Bank & Program) -> `64 13` (Request Current Patch).
   - Warm-Restart Pacing: To prevent MIDI FIFO buffer drops on pedal restart or app re-launch, an inter-command pacing delay of 25ms is enforced between init commands and before `64 13`.
   - Current Patch Request Retry: Host awaits `64 12 01` response with an 800ms timeout (50ms in automated tests); retries once on timeout before launching background bank scans.
   - Slot Request Retry: During `syncDeviceBank` (`0x46`), individual slot requests that encounter timeouts are retried once before falling back to empty slot descriptors.
   - ALSA RawMIDI Process Cleanup & Drain: Before binding `amidi -p <port> -d`, stale background `amidi` listeners are terminated (`pkill -9 -f amidi.*$portId`), and the ALSA input stream is drained for 50ms (0ms in tests) to clear leftover partial bytes. On disconnect, `amidi` is killed with `SIGTERM` and escalated to `SIGKILL` after 150ms.
3. **Patch Data Requests & SysEx Framing:**
   - Request Current Patch V2: `F0 52 00 6E 64 13 F7`
   - Request Active Bank & Program: `F0 52 00 6E 33 F7`
   - Current Patch Dump V2: `F0 52 00 6E 64 12 01 <len_lsb> <len_msb> <7-bit packed data...> <5 CRC bytes> F7` (fixed unpacked length 848 bytes: `len_lsb = 0x50`, `len_msb = 0x06`)
   - Request Memory Slot V2: `F0 52 00 6E 46 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> F7`
   - Memory Slot Dump V2: `F0 52 00 6E 45 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> <len_lsb> <len_msb> <7-bit packed data...> <5 CRC bytes> F7` (fixed unpacked length 848 bytes: `len_lsb = 0x50`, `len_msb = 0x06`, total frame length: 989 bytes)
   - Success Acknowledgment: `F0 52 00 6E 00 00 F7`
4. **PTCF Binary Patch Format:**
   - Unpacked 8-bit binary structure:
     * Magic header: `PTCF` (4 bytes ASCII)
     * Total length: 4 bytes uint32 LE
     * Version: 4 bytes uint32 LE
     * Number of effects: 4 bytes uint32 LE (typically 6)
     * Target pedal mask: 4 bytes uint32 LE (`0x00080000` for MS-60B+, `0x00040000` for MS-50G+)
     * Unknown header bytes: 6 bytes
     * Short name: 10 bytes ASCII string (padded with spaces)
     * DSP Effect IDs array: `numEffects * 4` bytes uint32 LE
   - Embedded subchunks:
     * `NAME`: 32 bytes (28 ASCII characters padded with spaces + 4 null bytes)
     * `EDTB`: Effect Parameter Edit blocks (`numEffects * 24` bytes). Each 24-byte block is bit-manipulated in reverse byte order (bits 191 down to 0):
       - Bit 191: Effect enabled toggle (1 bit)
       - Bits 162..190: DSP Algorithm ID (29 bits)
       - Parameters 0..4: 5 continuous/discrete parameters of 12 bits each
       - Parameters 5..7: 3 parameters of 8 bits each
       - Parameters 8..11: 4 parameters of 12 bits each
     * `PRM2`: Tempo (bits split across last 2 bytes), active editing slot (byte 10 bits 5..7), volume, routing.
       - Byte 20 (`prm2PreampSlot`): `(preampBits & 0x3F) << 1` (bitmask of slots containing Preamp models).
       - Bytes 21–22 (`prm2BPMSlot`): Bitmask of slots with tempo sync.
       - Bytes 22–23 (`prm2LineSelSlot`): Bitmask of Line Selector slots.
       - Byte 10 & Bytes 11–12: Active editing cursor slot index bitfields.
     * `TXE1`: English patch description.
   - CRC Validation:
     * 32-bit CRC (IEEE 802.3 `0xEDB88320` polynomial) inverted with `0xFFFFFFFF`, split into 5 7-bit words (LSB first).
5. **Real-time Parameter Modulation & Live Structural Chain Sync:**
   - Outgoing parameter change: `F0 52 00 6E 64 20 00 <slot_idx> <param_idx> <val_lsb> <val_word1> <val_word2> <val_word3> <val_word4> F7`
     * `param_idx = 0`: Effect Bypass state (`00` bypassed, `01` active).
     * `param_idx = 1`: Effect DSP Algorithm ID (`buildEffectTypeMessage`), with 32-bit `effectId` packed as 5 7-bit bytes (supports `effectId = 0` to empty/clear a slot).
     * `param_idx >= 2`: Knob parameter value (`paramNumber = paramIndex + 2`).
     * `slot_idx = 0x64`, `param_idx = 0x01`: Active cursor focus slot navigation (`buildSlotFocusMessage`).
   - Structural sync sequence (`buildSlotSyncSequence`): Dispatches Effect ID (`paramNumber = 1`), followed by Bypass (`paramNumber = 0`), followed by all mapped and trailing hidden parameters (`paramNumber >= 2`).
   - Hardware feedback reception: `F0 52 00 6E 64 20 01 <slot_idx> <param_idx> <val_lsb> <val_msb> ... F7`

---

### 3.3 Line 6 Bass Pod Pro Protocol (`lib/protocols/line6_bass_pod_pro_protocol.dart`)

#### Supported Device
- Line 6 Bass Pod Pro (Rackmount Multi-FX Processor)

#### Protocol Specifications
1. **Manufacturer ID & Identity Handshake:**
   - Line 6 3-byte SysEx Header: `F0 00 01 0C` (Manufacturer `0x00 01 0C`, USB Vendor `0x0E41`).
   - Family / Device Type byte: `0x02` (Bass POD / Bass POD Pro).
   - Universal SysEx Identity Request (`F0 7E 7F 06 01 F7`) matches Reply containing manufacturer `00 01 0C` and LSB-first family code `02 00` (`0x0002`, e.g., firmware 1.40 `F0 7E 7F 06 02 00 01 0C 02 00 01 00 30 31 34 30 F7`).
2. **Preset Recall & Verified Control Changes:**
   - Standard MIDI Program Change (PC `1`–`36` for slots `0`–`35` / `1A`–`9D`; PC `0` = Manual, PC `37` = Tuner).
   - Verified Continuous Controller (CC) parameters (6-bit scaled params step by 2 from `0..126`):
     * CC #1: Effect Tweak (`0–126`)
     * CC #4: Wah Pedal (`0–127`)
     * CC #7: Volume / Master Level (`0–127`)
     * CC #12: Amp Model Select (`0–15`)
     * CC #13: Drive (`0–126`)
     * CC #14: Bass (`0–126`)
     * CC #15: Mid (`0–126`)
     * CC #16: Treble (`0–126`)
     * CC #17: Channel Volume (`0–126`)
     * CC #18: Compress (`0–126`)
     * CC #19: Effect Select (`0–15`, index `10` = Bypass)
     * CC #21: FX Lo Cut (`0–126`)
     * CC #22: Noise Gate (`0` / `127`)
     * CC #60: Effect On/Off (`0` / `127`)
     * CC #64: Apply FX to DI (`0` / `127`)
     * CC #71: Cabinet Model Select (`0–15`, index `10` = Bypass)
     * CC #72: A.I.R. Level (`0–126`)
3. **Edit Buffer & SysEx Dumps (`opcode 0x00 = request`, `0x01 = dump`, `version = 0x01`):**
   - Request Edit Buffer Dump: `F0 00 01 0C 02 00 01 F7`
   - Request Program Slot Dump: `F0 00 01 0C 02 00 00 <program_number> F7` (`0x00..0x23`)
   - Request All Programs Dump: `F0 00 01 0C 02 00 02 F7`
   - Edit Buffer Dump Response (169 bytes): `F0 00 01 0C 02 01 01 01 <160 MSB-first nibbles> F7`
   - Program Slot Dump Response (170 bytes): `F0 00 01 0C 02 01 00 <program_number> 01 <160 MSB-first nibbles> F7`
   - Unpacked 80-byte program layout:
     * Byte 0 `[bit 0]`: Noise Gate enable (`0`/`1`)
     * Byte 3 `[3:0]`: Amp Model (`0–15`)
     * Byte 4 `[5:0]`: Drive (stored `0–63`, scaled `x2`)
     * Byte 6 `[5:0]`: Bass (stored `0–63`, scaled `x2`)
     * Byte 7 `[5:0]`: Middle (stored `0–63`, scaled `x2`)
     * Byte 8 `[5:0]`: Treble (stored `0–63`, scaled `x2`)
     * Byte 10 `[5:0]`: Channel Volume (stored `0–63`, scaled `x2`)
     * Byte 11 `[5:0]`: Compress (stored `0–63`, scaled `x2`)
     * Byte 31 `[3:0]`: Cabinet Model (`0–15`, index `10` = Bypass)
     * Byte 32 `[5:0]`: A.I.R. Level (stored `0–63`, scaled `x2`)
     * Byte 49 `[3:0]`: Effect Select (`0–15`, index `10` = Bypass)
     * Byte 50 `[5:0]`: Effect Tweak (stored `0–63`, scaled `x2`)
     * Byte 51 `[5:0]`: FX Lo Cut (stored `0–63`, scaled `x2`)
     * Byte 52 `[bit 0]`: Effect On/Off (`0`/`1`)
     * Bytes 64..79: Preset Name (16 ASCII characters, space-padded)

---

### 3.4 Effect & Parameter Metadata Catalogs (`lib/protocols/catalogs/` & `lib/catalog/`)

- `EffectDefinition`: Immutable specification of an effect type (`effectId`, `name`, `category`, `deviceFamily`, `List<ParameterDescriptor> parameters`, `int? dspLoad`, and integer ID getter `intEffectId`).
- `EffectCatalogRegistry`: Global lookup service resolving effect definitions by `DeviceFamily` and `effectId`, returning fallback definitions for unmapped DSP IDs and normalizing hex identifiers across Zoom and Line 6 pedal families.
- `ZoomMsPlusCatalog`: Complete multi-pedal catalogs generated by standalone pure-Dart `tool/generate_zoom_catalog.dart` from `tool/reference/` CSV/JSON/JS definitions into `lib/catalog/`:
  * **Zoom MS-60B+:** 98 effects (`zoom_ms60b_plus_catalog_data.dart`)
  * **Zoom MS-50G+:** 106 effects (`zoom_ms50g_plus_catalog_data.dart`)
  * **Zoom MS-70CDR+:** 150 effects (`zoom_ms70cdr_plus_catalog_data.dart`)
  * **Zoom MS-200D+:** 224 effects with full-name overlay (`zoom_ms200d_plus_catalog_data.dart`)
- `Line6BassPodProCatalog`: Complete 16 Amp models, 16 Cabinet models, Compressor/Noise Gate, and 16 built-in Effects matching hardware tables.
  * Spans all 11 hardware categories: Dynamics, Filter / EQ, Drive / Distortion, Preamp, Amp Model, Modulation, Pitch / Octave, Bass Synth, Special / SFX, Delay, Reverb.
  * Provides high-level browsing APIs: `getByIntId(int)`, `getById(String)`, `getByCategory(String)`, `categories`, and `search(query, {category})`.

---

## 4. Immutable Domain Models (`lib/models/`)

### 4.1 Device Models (`lib/models/device_family.dart`)
- `DeviceFamily`: Enum (`zoomMs50gPlus`, `zoomMs60bPlus`, `zoomMs70cdrPlus`, `zoomMs200dPlus`, `line6BassPodPro`, `unknown`).
  * Stable string key serialization via `toJson()` and fallback-safe `fromJson()`.

### 4.2 Patch & Chain Models (`lib/models/patch.dart`, `lib/models/effect_slot.dart`)
- `Patch`:
  ```dart
  class Patch {
    final String id;
    final String name;
    final DeviceFamily deviceFamily;
    final int? programNumber;
    final List<EffectSlot> slots;
    final List<String> tags;
    final String? author;
    final String? notes;
    final DateTime? updatedAt;
    final Map<String, dynamic> metadata;
  }
  ```
- `EffectSlot`:
  ```dart
  class EffectSlot {
    final int slotIndex;
    final String effectId;
    final String effectName;
    final bool isEnabled;
    final List<ParameterValue> parameters;
  }
  ```

### 4.3 Parameter Models (`lib/models/parameter_descriptor.dart`)
- `ParameterDescriptor`:
  ```dart
  class ParameterDescriptor {
    final String id;
    final String name;
    final double min;
    final double max;
    final double defaultValue;
    final double step;
    final String? unit;
    final List<String>? labels;
  }
  ```
- `ParameterValue`:
  ```dart
  class ParameterValue {
    final ParameterDescriptor descriptor;
    final double currentValue;
  }
  ```

### 4.4 Hardware Memory Bank Models (`lib/models/bank_slot_descriptor.dart`)
- `BankSlotDescriptor`:
  ```dart
  class BankSlotDescriptor {
    final int index; // 0 to 99
    final String name;
    final DeviceFamily deviceFamily;
    final bool isEmpty;
    final bool isLoaded;
    final Patch? patch;
    final Map<String, dynamic> metadata;

    String get formattedSlotIndex => index.toString().padLeft(2, '0');
    String get bankAndProgramNumber => '${(index ~/ 10) + 1}-${(index % 10) + 1}';
    String get slotLabel => '#$formattedSlotIndex ($bankAndProgramNumber)';
  }
  ```

---

## 5. Storage & Preset Library Layer (`lib/core/storage/`)

### 5.1 Repository Contracts & Implementations
- `PatchLibraryRepository`: Abstract contract defining search, filtering, CRUD, JSON import/export, and raw SysEx import/export.
- `InMemoryPatchLibraryRepository`: Deterministic in-memory repository for unit tests and UI preview environments.
- `FileSystemPatchLibraryRepository`: Pure `dart:io` repository providing atomic write-to-temp-then-rename persistence, searching, tag filtering, and file-level `.json` and `.syx` import/export.

---

## 6. State Management & Feature Modules (`lib/features/`)

Implemented using Flutter's built-in `ChangeNotifier` and clean constructor dependency injection (`MidiTransport`, `PatchLibraryRepository`, `EffectCatalogRegistry`) for 100% offline `--no-pub` reliability and zero third-party package fragility.

### 6.1 Device Connection Module (`lib/features/connection/`)
- `DeviceConnectionController`: Manages available MIDI ports, active connection state, active `DeviceFamily`, and resolved `DeviceProtocol` (`ZoomMsPlusProtocol` or `Line6BassPodProProtocol`). Performs Universal Identity Request handshake with port name fallback heuristics, executes hardware initialization sequences (sending `0x53` to exit lock-screen PC Mode and `0x50` to enable live parameter edits on Zoom MS Plus pedals, never `0x52`), and handles clean disconnection.
- Known Port Auto-Selection & Hot-Plug: Scans discovered port names on startup and `refreshPorts()` against known patterns (`ZOOM`, `MS Plus`, `MS-60B`, `MS-50G`, `MS-70CDR`, `MS-200D`, `Bass POD`, `Line 6`). Runs a periodic hot-plug poll every 2 seconds when disconnected from real hardware to auto-connect as soon as a matching device is plugged in, and cleanly disconnects when the active hardware device is unplugged.
- Asynchronous Bank Synchronization (`syncDeviceBank`): Non-blocking fetch of all persistent memory bank slots (0–99), safely catching per-slot timeouts, reporting live progress percentage and status, and updating `bankSlots` incrementally without locking the UI. Incoming `0x45` slot dumps strictly update `bankSlots` using `extractSlotIndex` and never overwrite or cycle the active editor buffer.
- `ConnectionBarWidget`: Top studio toolbar with status badge, port selector dropdown, device family picker, hardware sync actions ("Pull Patch" / "Push Patch"), and "Save to Library" button.

### 6.2 Patch Editor Module (`lib/features/editor/`)
- `PatchEditorController`: Holds active `Patch?`, inspected `selectedSlotIndex`, dirty state tracking, bounded 50-step `PatchEditHistory` (Undo/Redo with gesture & time-window coalescing), `CompareSlot` (`A`/`B`) tone comparison state, and incoming MIDI message stream subscription.
- Undo/Redo & A/B Hardware Sync: `undo()`, `redo()`, and `toggleCompareSlot()` synchronize transitions to connected hardware via `_syncPatchTransitionToDevice`—dispatching targeted `64 20 00` slot/parameter/bypass/clear deltas on Zoom MS Plus (never `64 12 01`) and `encodePatch` on Line 6 Bass POD Pro. Hardware-originated edits via `applyExternalHardwareUpdate` are excluded from the app Undo stack.
- Structured Patch Diffing (`lib/models/patch_diff.dart` & `PatchDiffDialog`): Computes name, tempo, slot (`added`, `removed`, `replaced`, `modified`, `unchanged`), bypass, and formatted parameter deltas; integrated into `PatchMetadataHeaderWidget` (A vs. B), `WriteToSlotDialog` (pre-write slot diff), `PatchLibraryDrawerOrPanel` (library preset vs. editor), and `PatchImportDialog` (import entry vs. editor).
- Desktop Keyboard Shortcuts (`lib/main.dart`): `Ctrl+Z` / `Cmd+Z` (Undo) and `Ctrl+Y` / `Ctrl+Shift+Z` / `Cmd+Shift+Z` (Redo), guarded to yield when an `EditableText` has focus.
- Real-time parameter control: `updateParameter` immediately updates local state and dispatches `protocol.buildParameterEditMessage(...)` over `MidiTransport` when connected.
- Real-time patch metadata controls:
  * `updatePatchName(String newName)`: Enforces hardware-specific character limits (10 chars for Zoom MS Plus, 16 for Line 6), converts unprintable and invalid ASCII characters to spaces, marks patch dirty, and synchronizes live to connected hardware.
  * `updatePatchTempo(int bpm)`: Clamps BPM to 40–250 range, updates patch PRM2 metadata, marks patch dirty, and syncs live to connected hardware.
  * `loadPatchFromDeviceSlot(int slotIndex, {bool notifyHardware = true})`: Single-click responsive slot loading into editor buffer: immediately loads cached patch if already available in `bankSlots` without redundant round-trips; when `!notifyHardware` on an uncached slot, requests the slot/current patch with `currentPatchTimeout` and zero MIDI echo (`buildSlotSelectMessages` skipped), and never issues slot-write commands (`0x45`).
  * `savePatchToDeviceSlot(int slotIndex, [Patch? patchToSave])`: Enforces `DeviceGeneration` compatibility (hard-blocking cross-generation writes via `isSameGeneration`), encodes active (or supplied) preset via `protocol.encodePatch(target, programNumber: slotIndex)` (or `buildSavePatchToSlotMessage`), and transmits memory slot dump SysEx (`0x45 0x00 0x00` on Zoom MS Plus) over `transport.sendSysEx(...)` / `send(...)` to persist patch in hardware slot (0–99). Resets `isDirty` flag, sets `programNumber`, and updates `connectionController.bankSlots[slotIndex]`.
- Bi-directional hardware sync: Listens to incoming MIDI messages; hardware parameter changes (`protocol.isParameterEdit`), active edit buffer dumps (`protocol.isCurrentPatchDump`), Zoom `64 26 00 00` slot changes, and Bank Select CC `0`/`32` + program changes (`isProgramChange`) immediately update `activeHardwareSlotIndex` and load the target slot into the editor buffer via `applyExternalHardwareUpdate(...)` without echoing outbound messages back to hardware. Incoming memory slot dumps (`protocol.isSlotPatchDump`) update `bankSlots` without overriding active editing.
- Signal chain slot operations:
  * `addEffectSlot({int? index, required dynamic effectId})`: Inserts new effect slot respecting device max slot limits (e.g. 6 slots on Zoom MS Plus) and initializes default parameters from `EffectCatalogRegistry`.
  * `insertEffectSlotAt(int index, EffectCatalogEntry entry)`: Inserts a new effect slot from catalog entry at designated index in the signal chain.
  * `removeEffectSlot(int slotIndex)`: Safely deletes a slot, re-indexes remaining slots, and clamps `selectedSlotIndex`.
  * `moveEffectSlot(int oldIndex, int newIndex)` / `reorderEffectSlots(int fromIndex, int toIndex)`: Reorders slots in the signal chain and adjusts selection.
  * `changeSlotEffect(int slotIndex, dynamic newEffectId)`: Swaps algorithm in slot (accepting integer DSP ID or hex string) and populates default parameter descriptors.
  * Automatically dispatches full edit buffer sync (`protocol.encodePatch`) to hardware when connected on structural chain modifications.
- `PatchMetadataHeaderWidget`: Integrated editor header bar featuring:
  * Real-time patch name `TextField` with device character limit and live updating.
  * Unsaved dirty state badge (`* UNSAVED`).
  * Tempo BPM display with decrement (`-1 BPM`), increment (`+1 BPM`), and continuous slider (40–250 BPM).
  * "Write to Slot..." button opening `WriteToSlotDialog`.
- `WriteToSlotDialog`: Modal slot selector dialog (0–99) displaying destination bank/slot numbers, existing slot names, and confirmation save dispatch.
- `SignalChainStripWidget`: Horizontal pedalboard stompbox view rendered in **Right-to-Left pedalboard order** (`[OUT] (Left) <-- [Add Slot] <-- [Slot N] ... <-- [Slot 1] <-- [IN] (Right)`):
  * Embedded `PatchMetadataHeaderWidget` and slot count subheader with `OUT ← IN` flow direction.
  * Rightmost `[IN]` badge and leftmost `[OUT]` badge with leftward audio flow indicators (`←`).
  * Dedicated inter-slot `DragTarget` **insertion zones** between every slot in RTL order (before slot 0 next to IN, between `i` and `i+1`, and after slot N), expanding on hover with illuminated vertical insertion indicators.
  * Dropping an `EffectDragPayload` or `EffectCatalogEntry` onto an insertion zone inserts the effect at that exact position via `insertEffectSlotAt`.
  * Dropping a `SlotReorderPayload` onto an insertion zone moves the dragged slot to that position via `reorderEffectSlots`.
  * Dropping directly onto an existing slot card swaps the effect or reorders slots.
  * Slot index, category badge, and effect name.
  * Move Left (towards Output, index + 1) and Move Right (towards Input, index - 1) controls on each slot for instant signal chain reordering.
  * Direct "Swap" effect trigger opening `EffectPickerDialog`.
  * Remove effect slot button (`IconButton`) when chain has more than 1 slot.
  * "+ Add Effect" card when patch has fewer than device maximum allowed slots.
  * Interactive Bypass/Enable LED switch with category glow.
- `EffectBankPaletteWidget`: Studio dockable panel / bottom-right studio shelf featuring:
  * Live search input by name, category, or ID.
  * Category filter chips (`All`, `Dynamics`, `Filter`, `Drive`, `Amp`, `Cabinet`, `Modulation`, `SFX`, `Delay`, `Reverb`).
  * Draggable effect cards (`Draggable<EffectDragPayload>`) with drag handle and category indicators.
  * Accessible click-to-add / swap interaction.
- `RotaryKnobWidget`: Dark studio circular rotary dial widget representing adjustable DSP parameters:
  * Custom painted dial with a 270° radial value sweep (from 7 o'clock to 5 o'clock), bevel border, active angular arc, and indicator needle.
  * Mouse scroll wheel interaction via `PointerScrollEvent` to increment/decrement parameter value cleanly without page scroll.
  * Vertical touch & mouse drag smoothly increments (upward) or decrements (downward) value.
  * Double-tap resets value to parameter default.
  * Accessible popup menu for discrete choice selection.
  * Monospace formatted value display matching pedal hardware screens.
- `SlotInspectorWidget`: Parameter inspector displaying an adaptive grid (`Wrap`) of `RotaryKnobWidget`s for known/defined catalog parameters:
  * Shows only true parameters defined in the catalog for each effect (eliminating unmapped/dummy parameters up to 12).
  * Filter toggle for internal/hidden parameters (`Hidden-1`), hidden by default.
  * Algorithm dropdown and search catalog button opening `EffectPickerDialog`.
- `EffectPickerDialog`: Full modal browsing dialog supporting text search across names and categories, category filter chips (All, Dynamics, Filter / EQ, Drive / Distortion, Preamp, Amp Model, Modulation, Pitch / Octave, Bass Synth, Special / SFX, Delay, Reverb), and one-click effect algorithm selection.

### 6.3 Preset Library & Hardware Bank Module (`lib/features/library/`)
- `PatchLibraryController`: Wraps `PatchLibraryRepository` to manage preset indexing, search queries, `DeviceFamily` filter chips, `availableTags` / tag filtering, `duplicatePatch` ("Save Copy As..."), and `saveHardwareSlotToLibrary`. Supports CRUD operations, editor loading, and JSON/SysEx import/export.
- `HardwareBankBrowserWidget`: Dedicated hardware memory slot browser:
  * Displays scrollable list of all 100 persistent slots (0–99) with slot numbers (`#00`, `1-1`) and names.
  * One-click "Load into Editor" action and quick "Write Active Here" overwrite action.
  * Search/filter bar by slot number or preset name, plus "Sync Bank" and "Restore Bank..." actions with live progress bars and cancellation.
  * Bidirectional drag-and-drop support (`DragTarget<LibraryPatchDragPayload>` for writing library presets onto slots with mismatch confirmation, and `buildAdaptiveDraggable<HardwareSlotDragPayload>` for dragging populated slots into the local library).
- `PatchLibraryDrawerOrPanel`: Unified side panel/drawer featuring segmented tab toggle between `Local Presets`, `Hardware Bank`, and `Setlists`, horizontal tag filter chips, `DragTarget<HardwareSlotDragPayload>` drop zone, "Open Side-by-Side Bank Manager" button, and per-card "Save Copy As..." duplication.
- `BankManagerDialog` (`lib/features/library/bank_manager_dialog.dart`): Side-by-side responsive workspace displaying searchable, family/tag-filterable local presets alongside hardware bank slots with hover highlights, `DeviceGeneration` cross-generation hard blocks (`showGenerationIncompatibleDialog` with zero "Write Anyway" override), same-generation cross-model confirmation (`confirmDeviceMismatchDrop`), and adaptive `Draggable` (desktop) / `LongPressDraggable` (touchscreen) support.
- `BankRestoreDialog` (`lib/features/library/bank_restore_dialog.dart`): Sequential batch slot restore dialog supporting local presets, **From File / Folder** disk backups via `ImportFileSystem` & `PatchImporter`, or pasted JSON/SysEx bundles starting at a chosen slot index, filtering incompatible hardware generations and restoring directly to hardware without creating duplicate Local Library presets.
- `PatchExportDialog` & `PatchImportDialog` (`lib/features/library/`): `PatchExportDialog` adds an interactive destination folder browser (`..`, subfolder navigation, editable path, "New Folder" creation) persisting `lastExportDirectory` in `AppPreferencesRepository`; `PatchImportDialog` supports multi-file selection checkboxes + `"Select All Files"` batch decoding in folders and defaults `"Import to Library"` to bypass the active editor buffer (with an opt-in `"Also load into Editor"` checkbox for single patches).
- `SaveCopyAsDialog` (`lib/features/library/save_copy_as_dialog.dart`): Quick preset duplication prompt launched from `PatchMetadataHeaderWidget` (`PatchEditorController.saveCopyAs`) and `PatchLibraryDrawerOrPanel` (`PatchLibraryController.duplicatePatch`).

---

## 7. Studio UI & Theming (`lib/features/theme/`)

- `StudioTheme`: High-contrast dark studio theme (`ThemeData.dark(useMaterial3: true)`) with category accent colors:
  * **Dynamics:** Vibrant Green (`#00E676`)
  * **Filter / EQ:** Vibrant Amber (`#FF9100`)
  * **Drive / Distortion:** Fiery Crimson (`#FF3D00`)
  * **Amp / Cab / Preamp:** Vibrant Violet (`#E040FB`)
  * **Modulation:** Electric Cyan (`#00E5FF`)
  * **Delay / Reverb:** Royal Blue (`#3D5AFE`)
  * **Pitch / Synth / SFX:** Bright Pink (`#FF4081`)
- `ResponsiveLayoutMetrics` & `ViewportSizeClass` (`lib/features/theme/responsive_layout.dart`):
  * **Breakpoints:** `compact` (`< 600px` width), `medium` (`600–1024px` width), and `expanded` (`> 1024px` width), plus `isShortEditorBody(availableBodyHeight < 440)` for landscape phones and Android `adjustResize` soft keyboards.
  * **Adaptive Panels & Drawers:** `PatchLibraryDrawerOrPanel` (`Local Presets` | `Hardware Bank`) docks as a right side panel (`300–340px`) on `expanded` viewports (`> 1024px`, height `>= 480px`) and collapses into an `endDrawer` (`min(360px, 88% width)`) on `compact` and `medium` viewports.
  * **Adaptive Inspector & Palette:** Side-by-side when editor body width `>= 700px` and non-short (`>= 440px`); switches cleanly to an `INSPECTOR | EFFECT PALETTE` segmented tab toggle on narrow/short screens, wrapped in a unified vertical `SingleChildScrollView` on short viewports (`< 440px` body height) with `LayoutBuilder` unbounded-height awareness in `SlotInspectorWidget` and `EffectBankPaletteWidget`.
  * **Touch-Friendly Drag & Controls:** Uses `LongPressDraggable` on mobile touch platforms (Android/iOS) so swipes scroll the horizontal signal chain strip and effect palette grid naturally while preserving immediate `Draggable` on desktop; toolbars, metadata header, and dialogs (`EffectPickerDialog`, `WriteToSlotDialog`, Import/Export) use `Wrap`, `SingleChildScrollView`, `CustomScrollView`, and viewport-clamped sizing.

---

## 9. Platform Packaging & Distribution

### 9.1 Linux Packaging
- **Desktop Entry (`linux/packaging/signal-chain.desktop`):** Standard XDG application launcher with `Categories=AudioVideo;Audio;Midi;` matching Freedesktop.org specifications and passing `desktop-file-validate`.
- **AppStream MetaInfo (`linux/packaging/io.github.bassmannate.signal_chain.appdata.xml`):** Compliant AppStream XML metadata for AppImageHub (`appimage.github.io`) submission with `<id>`, `<metadata_license>FSFAP</metadata_license>`, `<project_license>MIT</project_license>`, `<name>`, `<summary>`, `<description>`, `<developer>`, `<url type="homepage">`, `<launchable type="desktop-id">signal-chain.desktop</launchable>`, `<provides>`, `<content_rating>`, and release tags; verified with `appstreamcli validate --strict`.
- **Icon Assets:** Scalable SVG (`linux/packaging/signal-chain.svg`) and 256x256 PNG (`linux/packaging/signal-chain.png`) featuring studio pedalboard nodes, glowing stomp switches, RTL audio flow arrows, and a 5-pin MIDI socket badge.
- **Debian Package Generator (`tool/package_linux_deb.sh`):** Automates `.deb` package creation with `dpkg-deb`, declaring `Depends: alsa-utils, libgtk-3-0` so `amidi` is guaranteed on target distributions.
- **AppImage Generator (`tool/package_linux_appimage.sh`):** Assembles AppDir structure and `AppRun` launcher, copies AppStream MetaInfo to `usr/share/metainfo/`, and bundles desktop entries/icons before invoking `appimagetool`.
- **Local User Install Helper (`tool/install_linux_desktop.sh`):** Non-root user installer copying release artifacts to `~/.local/lib/signal-chain`, `~/.local/bin/signal-chain`, and `~/.local/share/applications/signal-chain.desktop`.
- **Build Artifact Hygiene:** Root `.gitignore` excludes `dist/`, `AppDir/`, `*.AppImage`, `*.deb`, `*.zip`, `*.tar.gz`, `*.tar.xz`, and downloaded `tool/appimagetool`.

### 9.2 Android USB Host & MIDI Capabilities
- **Permissions & Features:** Declares `android.hardware.usb.host` and `android.software.midi` in `AndroidManifest.xml`.
- **USB Device Filters (`android/app/src/main/res/xml/device_filter.xml`):** Matches Zoom Corporation (`vendor-id="5766"` / `0x1686`) and Line 6 (`vendor-id="3649"` / `0x0E41`) for automatic device attachment triggering.
- **Native USB MIDI Transport (`MainActivity.kt` & `AndroidMidiTransport`):** Implements `android.media.midi.MidiManager` `MethodChannel` / `EventChannel` streaming with 256-byte outgoing SysEx chunking and `_rxBuffer` incoming SysEx stitching + 2/3-byte MIDI channel framing (`lib/src/transport/android_midi_transport.dart`, `lib/core/midi/android_midi_transport.dart`), wired into `lib/main.dart` and physically verified over USB OTG on a Fire HD 10 tablet and Pixel 10 Pro XL with a Zoom MS-60B+.
- **Branding, Adaptive Icons, Signing & F-Droid Readiness:** `AndroidManifest.xml` declares `android:label="Signal Chain"` and `android:roundIcon="@mipmap/ic_launcher_round"`, with `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher*.png` and `mipmap-anydpi-v26/ic_launcher*.xml` adaptive/monochrome icons generated via `tool/generate_android_icons.py`, dark `#121318` splash (`launch_background.xml`), `dependenciesInfo` disabled in `android/app/build.gradle.kts`, optional release keystore signing via `ANDROID_KEYSTORE_*` / `android/key.properties` (safe debug fallback), and `fastlane/metadata/android/en-US/` store metadata.

### 9.3 Windows Distribution
- **Metadata:** Clean application metadata in `windows/runner/Runner.rc` ("Signal Chain", "Signal Chain Contributors").
- **Packaging:** PowerShell script `tool/package_windows_zip.ps1` bundling release executable, assets, and DLLs into a clean portable release ZIP (`dist/signal-chain-windows-x64-<version>.zip`).

### 9.4 Automated GitHub Releases (`.github/workflows/release.yml`)
- **Trigger:** Pushing a `v*.*.*` tag (`GITHUB_REF_NAME`).
- **Verification Gate (`verify`):** Runs `flutter analyze --no-pub` and `flutter test --no-pub` on `ubuntu-latest`.
- **Platform Build Jobs:**
  - `build-linux`: Builds `flutter build linux --release --no-pub`, downloads `appimagetool`, runs `./tool/package_linux_deb.sh "${VERSION}"` and `./tool/package_linux_appimage.sh "${VERSION}"` (with `APPIMAGE_EXTRACT_AND_RUN=1`), and uploads `dist/*.deb` and `dist/*.AppImage`.
  - `build-android`: Optionally decodes `ANDROID_KEYSTORE_BASE64`, builds `flutter build apk --release --no-pub --android-skip-build-dependency-validation`, and uploads `dist/signal-chain-${VERSION}-android.apk`.
  - `build-windows`: Builds `flutter build windows --release --no-pub`, runs `pwsh -File tool/package_windows_zip.ps1 -Version $version`, and uploads `dist/*.zip`.
- **Release Publishing (`publish-release`):** Downloads all artifacts, generates `SHA256SUMS.txt`, and publishes via `softprops/action-gh-release@v3`.

---

## 10. Implementation Conventions & Coding Standards

1. **Safety & Lints:** Enforce strict type safety with `flutter_lints` and avoid `dynamic` where typed models are possible.
2. **Byte Buffer Hygiene:** Always use `Uint8List.fromList()` or subview slices rather than mutating shared memory across async boundaries.
3. **No UI in Logic:** Keep widgets declarative and dumb. All business logic lives in controllers and protocol parsers.
4. **Hardware Echo Prevention:** Incoming hardware updates (preset changes, knob turns, bypass toggles) are processed under `_isHandlingIncoming = true` and `notifyHardware: false` so that zero SysEx/CC messages are echoed back to the device, preventing feedback loops.
5. **Zoom MS Plus Parameter Numbering:** Parameter 0 represents Effect Bypass (1 = ON, 0 = OFF), Parameter 1 represents Effect ID, and Parameter numbers 2+ map to effect knob parameters (knob index = `paramNumber - 2`).
6. **Zoom MS Plus Slot Screen Focus:** SysEx `F0 52 00 6E 64 20 00 64 01 <slotIndex> 00 00 00 00 F7` synchronizes the active effect slot screen bidirectionally. Sent when selecting a slot in the app UI, and received when the user presses Left/Right cursor buttons on the physical pedal.
7. **Device-Level SysEx Disambiguation:** SysEx with `data[4..6] == 64 20 00` and `data[7] == 0x64` (100 decimal) represent pedal global parameters (e.g. `64 01` = slot focus, `64 02` = tempo, `64 0F` = auto-save). Protocols must guard `isSlotBypass` and `isParameterEdit` to only match effect slots (`slotIndex < 6`), rejecting `0x64`.

