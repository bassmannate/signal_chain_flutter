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

### 3.4 Effect & Parameter Metadata Catalogs (`lib/protocols/catalogs/`)

- `EffectDefinition`: Immutable specification of an effect type (`effectId`, `name`, `category`, `deviceFamily`, `List<ParameterDescriptor> parameters`).
- `EffectCatalogRegistry`: Service resolving effect definitions by `DeviceFamily` and `effectId`, returning fallback definitions for unmapped DSP IDs and normalizing hex identifiers.
- `ZoomMsPlusCatalog`: Core MS-60B+ and MS Plus effects across 11 categories (Dynamics, Filter/EQ, Drive, Preamp, Amp Model, Modulation, Pitch, Synth, SFX, Delay, Reverb) with complete parameter descriptors and discrete labels.
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

---

## 5. Storage & Preset Library Layer (`lib/core/storage/`)

### 5.1 Repository Contracts & Implementations
- `PatchLibraryRepository`: Abstract contract defining search, filtering, CRUD, JSON import/export, and raw SysEx import/export.
- `InMemoryPatchLibraryRepository`: Deterministic in-memory repository for unit tests and UI preview environments.
- `FileSystemPatchLibraryRepository`: Pure `dart:io` repository providing atomic write-to-temp-then-rename persistence, searching, tag filtering, and file-level `.json` and `.syx` import/export.

---

## 6. State Management & Feature Modules (`lib/features/`)

Built on `flutter_riverpod` (Notifier / AsyncNotifier pattern).

### 5.1 Device Connection Module (`lib/features/connection/`)
- `midiTransportProvider`: Provides the active `MidiTransport` instance (mocked in tests, native in production).
- `deviceDiscoveryController`: Scans ports, performs MIDI identity inquiries, identifies connected pedal models, and maintains connection state.

### 5.2 Patch Editor Module (`lib/features/editor/`)
- `activePatchController`: Holds the patch currently loaded into the device's edit buffer.
- Real-time throttling & debouncing: High-frequency UI knob updates are debounced (15–30 ms) to prevent saturating MIDI baud rates.
- Bi-directional sync: Incoming parameter updates from the hardware are applied directly to the active patch state without triggering redundant outbound transmissions.

### 5.3 Preset Library Module (`lib/features/library/`)
- `libraryRepository`: Local storage abstraction for saving, naming, grouping, and backing up presets.
- Serializers: Export to and import from `.syx` (raw MIDI SysEx) and portable `.json` formats.
- Drag-and-drop bank manager for reorganizing pedal slot allocations.

---

## 6. Implementation Conventions & Coding Standards

1. **Safety & Lints:** Enforce strict type safety with `flutter_lints` and avoid `dynamic` where typed models are possible.
2. **Byte Buffer Hygiene:** Always use `Uint8List.fromList()` or subview slices rather than mutating shared memory across async boundaries.
3. **No UI in Logic:** Keep widgets declarative and dumb. All business logic lives in controllers and protocol parsers.

