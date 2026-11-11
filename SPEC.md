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

### 3.2 Zoom MS Plus Series Protocol (`lib/protocols/zoom/`)

#### Supported Devices
- Zoom MS-50G+
- Zoom MS-60B+
- Zoom MS-70CDR+
- Zoom MS-200+

#### Protocol Specifications
1. **Device Inquiry / Handshake:**
   - Universal Non-Real-Time SysEx Identity Request: `F0 7E 00 06 01 F7`
   - Identity Reply format: `F0 7E 00 06 02 52 <family_code> <model_number> ... F7` (Zoom Manufacturer ID: `0x52`).
2. **Editor Mode Activation & Keep-Alive:**
   - Host sends pedal-specific editor mode trigger (`F0 52 00 <device_id> 50 ... F7`) to enable real-time bi-directional control and disable sleep.
3. **Patch Data Structure:**
   - Zoom patch files / dumps contain:
     * Header & Patch Name (ASCII character buffer).
     * Effect Slot count (up to 6 concurrent effect blocks).
     * Effect ID (32-bit DSP algorithm identifier).
     * Parameter Blocks (packed bitfields representing rotary knob values, toggle states, expression pedal mappings).
4. **Real-time Parameter Modulation:**
   - Instant parameter changes sent as concise SysEx messages (`F0 52 00 <device_id> 31 <slot_idx> <param_idx> <val_lsb> <val_msb> F7`).
   - Dynamic update feedback loop to update the UI when the pedal's physical knobs are rotated.

---

### 3.3 Line 6 Bass Pod Pro Protocol (`lib/protocols/line6/`)

#### Supported Device
- Line 6 Bass Pod Pro (Rackmount Multi-FX Processor)

#### Protocol Specifications
1. **Manufacturer ID & Header:**
   - Line 6 SysEx Header: `F0 00 01 0C` (Manufacturer `0x00 0x01 0x0C`).
   - Device Type identifier for Bass Pod Pro.
2. **Preset Recall & Control Changes:**
   - Standard MIDI Program Change (PC `0`–`63`) for switching channel memories (A1 to D9 / User Banks).
   - Standard Continuous Controller (CC) parameters:
     * CC #4: Drive
     * CC #14: Bass
     * CC #15: Mid
     * CC #16: Treble
     * CC #17: Channel Volume
     * CC #12: Amp Model Select
     * CC #13: Cabinet Model Select
     * CC #19: Effect Tweak / Effect Value
     * CC #7: Master Volume
3. **Edit Buffer & Sysex Dumps:**
   - Request Edit Buffer Dump: `F0 00 01 0C 01 00 ... F7`
   - Edit Buffer Dump parsing: 72-byte packed parameter payload containing full amp model settings, cab simulations, compression thresholds, and FX routing.
   - Program Dump & Bank Dump commands for batch preset extraction.

---

## 4. Immutable Domain Models (`lib/models/`)

### 4.1 Device Models (`lib/models/device/`)
- `DeviceFamily`: Enum (`zoomMsPlus`, `line6BassPodPro`).
- `DeviceModelDescriptor`: Model name, max effect slots, supported sample rates, capabilities (e.g. tuner, tap tempo, expression).
- `ConnectedDevice`: Active connection state, firmware revision, input/output port assignments.

### 4.2 Patch & Chain Models (`lib/models/patch/`)
- `Patch`:
  ```dart
  class Patch {
    final String id;
    final String name;
    final int? slotIndex;
    final double tempoBpm;
    final List<EffectSlot> effectSlots;
    final Map<String, dynamic> metadata;
  }
  ```
- `EffectSlot`:
  ```dart
  class EffectSlot {
    final int slotIndex;
    final bool isEnabled;
    final String effectId;
    final String effectName;
    final List<ParameterValue> parameters;
  }
  ```

### 4.3 Parameter Models (`lib/models/parameter/`)
- `ParameterDescriptor`:
  ```dart
  enum ParameterType { integer, float, enumeration, toggle }

  class ParameterDescriptor {
    final String id;
    final String name;
    final ParameterType type;
    final double minValue;
    final double maxValue;
    final double defaultValue;
    final double step;
    final String? unit;
    final List<String>? enumValues;
  }
  ```
- `ParameterValue`:
  ```dart
  class ParameterValue {
    final String parameterId;
    final double value;
  }
  ```

---

## 5. State Management & Feature Modules (`lib/features/`)

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

