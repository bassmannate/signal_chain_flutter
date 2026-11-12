# Technical Architecture Specification: `signal_chain_flutter`

## 1. Architectural Overview & Layering

The codebase is organized strictly under Clean Architecture principles to ensure complete platform independence, full unit-testability of protocol logic without hardware or plugins, and predictable state transitions.

```
lib/
├── core/
│   └── midi/               # Abstract transport contracts & testing doubles
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

### 2.4 Composite Transport Architecture (`CompositeMidiTransport`)
- Aggregates multiple `MidiTransport` implementations (e.g. `LinuxAlsaMidiTransport` + `MockMidiTransport`) into a unified surface.
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
2. **Editor & PC Mode Activation:**
   - Parameter Edit Enable: `F0 52 00 6E 50 F7` (Disable: `F0 52 00 6E 51 F7`)
   - PC Mode Enable: `F0 52 00 6E 52 F7` (Disable: `F0 52 00 6E 53 F7`)
3. **Patch Data Requests & SysEx Framing:**
   - Request Current Patch V2: `F0 52 00 6E 64 13 F7`
   - Current Patch Dump V2: `F0 52 00 6E 64 12 01 <len_lsb> <len_msb> <7-bit packed data...> <5 CRC bytes> 00 F7`
   - Request Memory Slot V2: `F0 52 00 6E 46 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> F7`
   - Memory Slot Dump V2: `F0 52 00 6E 45 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb> <len_lsb> <len_msb> <7-bit packed data...> <5 CRC bytes> 00 F7`
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
     * `TXE1`: English patch description.
   - CRC Validation:
     * 32-bit CRC (IEEE 802.3 `0xEDB88320` polynomial) inverted with `0xFFFFFFFF`, split into 5 7-bit words (LSB first).
5. **Real-time Parameter Modulation:**
   - Outgoing parameter change: `F0 52 00 6E 64 20 00 <slot_idx> <param_idx> <val_lsb> <val_word1> <val_word2> <val_word3> <val_word4> F7`
   - Hardware feedback reception: `F0 52 00 6E 64 20 01 <slot_idx> <param_idx> <val_lsb> <val_msb> ... F7`

---

### 3.3 Line 6 Bass Pod Pro Protocol (`lib/protocols/line6_bass_pod_pro_protocol.dart`)

#### Supported Device
- Line 6 Bass Pod Pro (Rackmount Multi-FX Processor)

#### Protocol Specifications
1. **Manufacturer ID & Header:**
   - Line 6 3-byte SysEx Header: `F0 00 01 0C` (Manufacturer `0x00 0x01 0x0C`).
   - Family / Device Type byte: `0x01` (Bass Pod Pro).
2. **Preset Recall & Control Changes:**
   - Standard MIDI Program Change (PC `0`–`127`) for switching preset channel memories.
   - Real-time Continuous Controller (CC) parameters:
     * CC #4: Drive (0–127)
     * CC #14: Bass (0–127)
     * CC #15: Mid (0–127)
     * CC #16: Treble (0–127)
     * CC #17: Channel Volume (0–127)
     * CC #12: Amp Model Select (0–15)
     * CC #13: Cabinet Model Select (0–7)
     * CC #19: Effect Tweak / Value (0–127)
     * CC #7: Master Volume (0–127)
     * CC #64: Compressor Ratio / Threshold (0–127)
     * CC #11: Effect Select / Type (0–7)
3. **Edit Buffer & SysEx Dumps:**
   - Request Edit Buffer Dump: `F0 00 01 0C 01 00 F7`
   - Request Program Slot Dump: `F0 00 01 0C 01 01 <program_number> F7`
   - Edit Buffer Dump response: `F0 00 01 0C 01 00 <payload...> F7`
     * 72-byte parameter payload encoded as 144 4-bit nibbles (low nibble first) or 72 raw bytes.
     * Byte 0: Amp Model (0–15)
     * Byte 1: Cabinet Model (0–7)
     * Byte 2: Drive (0–127)
     * Byte 3: Bass (0–127)
     * Byte 4: Mid (0–127)
     * Byte 5: Treble (0–127)
     * Byte 6: Channel Volume (0–127)
     * Byte 7: Compressor Ratio / Threshold (0–127)
     * Byte 8: Effect Type (0–7)
     * Byte 9: Effect Tweak (0–127)
     * Byte 10: Master Volume (0–127)
     * Byte 11: Compressor Enable toggle (0 / 1)
     * Bytes 56..71: Preset Name (16 ASCII characters, space-padded)

---

### 3.4 Effect & Parameter Metadata Catalogs (`lib/protocols/catalogs/` & `lib/catalog/`)

- `EffectDefinition`: Immutable specification of an effect type (`effectId`, `name`, `category`, `deviceFamily`, `List<ParameterDescriptor> parameters`, `int? dspLoad`, and integer ID getter `intEffectId`).
- `EffectCatalogRegistry`: Global lookup service resolving effect definitions by `DeviceFamily` and `effectId`, returning fallback definitions for unmapped DSP IDs and normalizing hex identifiers across Zoom and Line 6 pedal families.
- `ZoomMsPlusCatalog`: Complete 98-effect MS-60B+ and MS Plus catalog extracted from `zoom-effect-mappings-ms60bp.json` via pure-Dart deterministic generator `tool/generate_zoom_catalog.dart` into `lib/catalog/zoom_ms_plus_catalog_data.dart`.
  * Spans all 11 hardware categories: Dynamics, Filter / EQ, Drive / Distortion, Preamp, Amp Model, Modulation, Pitch / Octave, Bass Synth, Special / SFX, Delay, Reverb.
  * Provides high-level browsing APIs: `getByIntId(int)`, `getById(String)`, `getByCategory(String)`, `categories`, and `search(query, {category})`.
- `Line6BassPodProCatalog`: 16 Amp models, 8 Cabinet models, Compressor block, and 8 Modulation/Delay effects with exact CC/edit buffer parameter mappings.

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
- `PatchEditorController`: Holds active `Patch?`, inspected `selectedSlotIndex`, dirty state tracking, and incoming MIDI message stream subscription.
- Real-time parameter control: `updateParameter` immediately updates local state and dispatches `protocol.buildParameterEditMessage(...)` over `MidiTransport` when connected.
- Real-time patch metadata controls:
  * `updatePatchName(String newName)`: Enforces hardware-specific character limits (10 chars for Zoom MS Plus, 16 for Line 6), converts unprintable and invalid ASCII characters to spaces, marks patch dirty, and synchronizes live to connected hardware.
  * `updatePatchTempo(int bpm)`: Clamps BPM to 40–250 range, updates patch PRM2 metadata, marks patch dirty, and syncs live to connected hardware.
  * `loadPatchFromDeviceSlot(int slotIndex)`: Single-click responsive slot loading into editor buffer: immediately loads cached patch if already available in `bankSlots` without redundant round-trips, switches pedal memory slot via `buildSlotSelectMessages` (CC0/CC32/PC), and never issues slot-write commands (`0x45`).
  * `savePatchToDeviceSlot(int slotIndex, [Patch? patchToSave])`: Encodes and transmits memory slot dump SysEx to persist patch in hardware slot (0–99).
- Bi-directional hardware sync: Listens to incoming MIDI messages; hardware parameter changes (`protocol.isParameterEdit`), active edit buffer dumps (`protocol.isCurrentPatchDump`), and program changes (`isProgramChange`) update local state via `applyExternalHardwareUpdate(...)` without echoing outbound messages back to hardware. Incoming memory slot dumps (`protocol.isSlotPatchDump`) are ignored by the editor buffer to prevent background sync cycling.
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
- `SignalChainStripWidget`: Horizontal pedalboard stompbox view featuring:
  * Embedded `PatchMetadataHeaderWidget` and slot count subheader.
  * Dedicated inter-slot `DragTarget` **insertion zones** before slot 0, between slot `i` and `i+1`, and after the last slot, expanding on hover with illuminated vertical insertion indicators.
  * Dropping an `EffectDragPayload` or `EffectCatalogEntry` onto an insertion zone inserts the effect at that exact position via `insertEffectSlotAt`.
  * Dropping a `SlotReorderPayload` onto an insertion zone moves the dragged slot to that position via `reorderEffectSlots`.
  * Dropping directly onto an existing slot card swaps the effect or reorders slots.
  * Slot index, category badge, and effect name.
  * Move Left and Move Right controls on each slot for instant signal chain reordering.
  * Direct "Swap" effect trigger opening `EffectPickerDialog`.
  * Remove effect slot button (`IconButton`) when chain has more than 1 slot.
  * "+ Add Effect" card when patch has fewer than device maximum allowed slots.
  * Interactive Bypass/Enable LED switch with category glow.
- `EffectBankPaletteWidget`: Studio dockable panel / bottom-right studio shelf featuring:
  * Live search input by name, category, or ID.
  * Category filter chips (`All`, `Dynamics`, `Filter`, `Drive`, `Amp`, `Cabinet`, `Modulation`, `SFX`, `Delay`, `Reverb`).
  * Draggable effect cards (`Draggable<EffectDragPayload>`) with drag handle and category indicators.
  * Accessible click-to-add / swap interaction.
- `SlotInspectorWidget`: Parameter inspector with algorithm dropdown, search catalog button opening `EffectPickerDialog`, discrete label dropdowns, and continuous sliders.
- `EffectPickerDialog`: Full modal browsing dialog supporting text search across names and categories, category filter chips (All, Dynamics, Filter / EQ, Drive / Distortion, Preamp, Amp Model, Modulation, Pitch / Octave, Bass Synth, Special / SFX, Delay, Reverb), and one-click effect algorithm selection.

### 6.3 Preset Library & Hardware Bank Module (`lib/features/library/`)
- `PatchLibraryController`: Wraps `PatchLibraryRepository` to manage preset indexing, search queries, `DeviceFamily` filter chips, and tag filtering. Supports CRUD operations, editor loading, and JSON/SysEx import/export.
- `HardwareBankBrowserWidget`: Dedicated hardware memory slot browser:
  * Displays scrollable list of all 100 persistent slots (0–99) with slot numbers (`#00`, `1-1`) and names.
  * One-click "Load into Editor" action.
  * Quick "Write Active Here" overwrite action.
  * Search/filter bar by slot number or preset name.
  * "Sync Bank" action with progress bar and cancellation.
- `PatchLibraryDrawerOrPanel`: Unified side panel/drawer featuring segmented tab toggle between `Local Presets` and `Hardware Bank`.

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

---

## 8. Implementation Conventions & Coding Standards

1. **Safety & Lints:** Enforce strict type safety with `flutter_lints` and avoid `dynamic` where typed models are possible.
2. **Byte Buffer Hygiene:** Always use `Uint8List.fromList()` or subview slices rather than mutating shared memory across async boundaries.
3. **No UI in Logic:** Keep widgets declarative and dumb. All business logic lives in controllers and protocol parsers.
4. **Hardware Echo Prevention:** Incoming hardware updates (preset changes, knob turns, bypass toggles) are processed under `_isHandlingIncoming = true` and `notifyHardware: false` so that zero SysEx/CC messages are echoed back to the device, preventing feedback loops.
5. **Zoom MS Plus Parameter Numbering:** Parameter 0 represents Effect Bypass (1 = ON, 0 = OFF), Parameter 1 represents Effect ID, and Parameter numbers 2+ map to effect knob parameters (knob index = `paramNumber - 2`).
6. **Zoom MS Plus Slot Screen Focus:** SysEx `F0 52 00 6E 64 20 00 64 01 <slotIndex> 00 00 00 00 F7` synchronizes the active effect slot screen bidirectionally. Sent when selecting a slot in the app UI, and received when the user presses Left/Right cursor buttons on the physical pedal.
7. **Device-Level SysEx Disambiguation:** SysEx with `data[4..6] == 64 20 00` and `data[7] == 0x64` (100 decimal) represent pedal global parameters (e.g. `64 01` = slot focus, `64 02` = tempo, `64 0F` = auto-save). Protocols must guard `isSlotBypass` and `isParameterEdit` to only match effect slots (`slotIndex < 6`), rejecting `0x64`.

