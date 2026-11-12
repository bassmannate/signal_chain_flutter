# Project Context: `signal_chain_flutter`

## 1. Project Overview

`signal_chain_flutter` is a cross-platform rewrite of the Node.js/Electron `signal-chain` patch editor and preset library manager. It provides real-time parameter editing, preset management, bank backup/restore, and chain reorganization for guitar and bass multi-effects processors, specifically:
- **Zoom MS Plus Series** pedals (e.g., MS-50G+, MS-60B+, MS-70CDR+, MS-200+).
- **Line 6 Bass Pod Pro** rackmount multi-effects processors.

The goal of this Flutter rewrite is to replace the heavier Electron desktop footprint with a high-performance, single-codebase application capable of running smoothly across desktop and mobile devices.

### Milestone Status
- **Milestone 1:** Project Scaffolding, Domain Models & Core MIDI Abstraction — **Completed**
- **Milestone 2:** Pure Dart Protocol & SysEx Engine (`SysexCodec`, `ZoomMsPlusProtocol`, `Line6BassPodProProtocol`) — **Completed**
- **Milestone 3:** Effect Catalogs, Patch Serialization & Local Persistence Layer — **Completed**
- **Milestone 4:** Application State Controllers & Cross-Platform Signal Chain UI — **Completed**
- **Milestone 5:** Native Platform MIDI Transport (`LinuxAlsaMidiTransport`, `CompositeMidiTransport`), Persistent Disk Storage & Presets Import/Export — **Completed**
- **Milestone 6:** Full Zoom MS-60B+ / MS Plus Effect Catalog Extraction & Signal Chain Slot Workflows (Reordering, Add, Remove, Swap & Modal Catalog Picker) — **Completed**
- **Milestone 7:** Hardware Patch Memory Bank Protocol (0–99 Slots), Patch Metadata Controls (Name & Tempo), Hardware Bank Browser UI — **Completed**
- **Milestone 7.5:** Live Bidirectional Hardware Sync, Patch Name Extraction, MIDI Auto-Select, and Drag-and-Drop Effect Palette — **Completed**
- **Milestone 8:** Zoom MS-60B+ Live Hardware Testing Protocol & UX Bug Fixes (0x50/0x53 Handshake, Bank Sync Isolation, Single-Click Slot Loading, Inter-Slot Insertion Zones) — **Completed**
- **Milestone 8.5:** Zoom MS-60B+ Hardware Patch Switch Feedback Loop Elimination & Bidirectional Knob/Bypass Sync — **Completed**
- **Milestone 8.6:** Physical Footswitch Bypass Real-Time Fix & Bidirectional Effect Slot Focus Synchronization — **Completed**
- **Milestone 8.7:** Right-to-Left Pedalboard Signal Chain, Rotary Knob Inspector & Parameter Accuracy — **Completed**

---

## 2. Target Platforms

| Platform | Primary Deployment Mode | MIDI Subsystem / Transport Interface |
| :--- | :--- | :--- |
| **Linux** | Desktop (x86_64, ARM64) | ALSA Sequencer / RawMIDI via platform bridge |
| **Android** | Mobile & Tablet (ARM64, x86_64) | Android MIDI API (`android.media.midi`) / USB Host OTG |
| **Windows** | Desktop (x64) | Windows Multimedia API (`winmm.dll`) / WinRT MIDI API |

---

## 3. Core Tech Stack & Dependencies

- **Language & Runtime:** Dart SDK `^3.13.7` (Flutter 3.47.x+).
- **UI Framework:** Flutter (Material 3 with responsive layout adapters for desktop and mobile).
- **State Management & DI:** `flutter_riverpod` for reactive, testable state management and dependency injection.
- **Binary & Protocol Processing:** Pure `dart:typed_data` (`Uint8List`, `ByteData`, `Endian`). No native plugins or C-bindings in the protocol layer—SysEx serialization, deserialization, bit-packing, and checksum calculations are 100% pure Dart.
- **Hardware Abstraction Layer:** Platform-abstracted MIDI transport (`MidiTransport`) sitting between native platform channels and domain protocol handlers.
- **Persistence:** Local JSON / SQLite / Hive-compatible storage layer for offline preset libraries and pedal backups.

---

## 4. Architectural Principles & Clean Architecture

The project adheres strictly to Clean Architecture separation of concerns:

```
[ UI / Presentation (lib/features/) ]
            │ (Watches Riverpod State)
            ▼
[ Domain State & Controllers (lib/features/*/controllers) ]
            │ (Manipulates immutable models)
            ▼
[ Domain Models (lib/models/) ]
            ▲
            │ (Decodes into / Encodes from)
[ Protocol Engines (lib/protocols/) ] (Pure Dart: Zero Flutter/Platform imports)
            │ (Sends / Receives Uint8List SysEx messages)
            ▼
[ Hardware Abstraction (lib/core/midi/) ] (MidiTransport interface)
            │
            ├─► MockMidiTransport (Testing / Simulation)
            └─► NativeMidiTransport (Platform channels / USB / BLE)
```

### Key Rules:
1. **Zero Platform Leakage in Protocols:** Files under `lib/protocols/` and `lib/models/` must never import `flutter/material.dart`, platform channel code, or OS-specific libraries. They must operate purely on `Uint8List`, `int`, and immutable Dart models.
2. **Immutability:** Domain models (patches, effects, parameters) are immutable value objects using `copyWith` semantics.
3. **Hardware Isolation:** All MIDI interaction is mediated by the abstract `MidiTransport` interface. Code outside `lib/core/midi/platform/` must never interact directly with underlying platform plugins.

---

## 5. Testing & Quality Guardrails

- **Targeted Test Execution:** When iterating on protocol parsing or feature controllers, run strictly targeted unit tests (e.g., `flutter test test/protocols/zoom_test.dart`) to maintain fast feedback loops.
- **Deterministic Hardware Mocking:** All protocol unit tests must run against `MockMidiTransport` with canned SysEx byte fixtures (hex dumps captured from actual pedals). No physical device is required to run test suites.
- **Static Analysis Compliance:** Code must maintain a clean `flutter analyze` baseline with zero errors and zero warnings under `analysis_options.yaml` (`flutter_lints`).

---

## 6. Milestone 7 Highlights: Hardware Memory Bank & Patch Metadata

- **Hardware Memory Bank Protocol (0–99 Slots):**
  - Bidirectional memory slot commands for Zoom MS Plus (`46 00 00` read request, `45 00 00` slot dump/write).
  - Program dump request and write for Line 6 Bass Pod Pro (`0x01`).
  - `BankSlotDescriptor` model representing remote hardware patch indices, synchronization state, and bank/slot formatting (`#42 (5-3)`).
- **Asynchronous Bank Synchronization:**
  - `DeviceConnectionController.syncDeviceBank`: Non-blocking, incremental fetch of all 100 slots with live progress tracking and error tolerance.
- **Real-Time Patch Metadata Controls:**
  - `PatchEditorController.updatePatchName`: Enforces hardware character limits (10 chars for Zoom MS Plus, 16 for Line 6) and sanitizes invalid/unprintable characters to spaces.
  - `PatchEditorController.updatePatchTempo`: Clamps BPM to 40–250 boundaries and persists into PRM2 subchunk.
  - `PatchMetadataHeaderWidget`: Real-time name input, dirty indicator, BPM display, increment/decrement buttons, tempo slider, and "Write to Slot..." button.
- **Hardware Bank Browser UI:**
  - `HardwareBankBrowserWidget`: Scrollable 100-slot browser with live text search, active preset indicators, one-click load into editor buffer, and "Write to Hardware Slot..." dialog.
  - Integrated into `PatchLibraryDrawerOrPanel` with responsive segmented tab navigation (`Local Presets` | `Hardware Bank`).

---

## 7. Live Hardware Synchronization & Screen Focus (Milestones 8.5 & 8.6)

- **ALSA Stream Real-Time Unbuffering (`LinuxAlsaMidiTransport.feedHexStream`):**
  - Resolved physical footswitch bypass 1-message lag where `amidi -d` stdout terminates with raw `F7` without trailing whitespace.
  - Complete 2-hex-digit tokens are now processed immediately without stranding in buffer tails, ensuring live hardware actions reflect on the app screen in real time on the very first footswitch press.
- **Bidirectional Effect Slot Screen Focus (`64 20 00 64 01`):**
  - Hardware Left/Right cursor buttons emit `F0 52 00 6E 64 20 00 64 01 <slot> 00 00 00 00 F7`. The app parses this to immediately update `selectedSlotIndex` and notify listeners, tracking the pedal's active screen.
  - Selecting a slot in the app UI dispatches the same SysEx focus message, causing the physical pedal display to navigate to that slot.
  - Physical footswitch bypass and knob turns automatically update `selectedSlotIndex` so the slot inspector aligns with physical pedal interactions.
  - Guarded `isSlotBypass` and `isParameterEdit` with `slotIndex < 6` to reject pedal-level global parameters (`0x64`), preventing false bypass toggles.

---

## 8. UI & Catalog Accuracy Improvements (Milestone 8.7)

- **Right-to-Left Pedalboard Signal Chain Order (`SignalChainStripWidget`):**
  - Renders the pedalboard strip in physical audio gear order: `[OUT] (Left) <-- [Add Slot] <-- [Slot N] ... <-- [Slot 2] <-- [Slot 1] <-- [IN] (Right)`.
  - Leftward flow indicators (`←`) connect stompboxes.
  - Inter-slot insertion zones and drag-and-drop targets align with RTL positions (Slot 1 is rightmost, next to IN).
  - Slot card reordering arrows move towards Output (Left, index + 1) or towards Input (Right, index - 1).
- **Adaptive Grid of Rotary Knobs (`RotaryKnobWidget` & `SlotInspectorWidget`):**
  - Replaced horizontal slider list with a custom-painted rotary knob dial featuring a 270° radial sweep (7 o'clock to 5 o'clock), bevel border, active angular arc, and indicator needle.
  - Interactive controls:
    - Mouse scroll wheel adjusts value up/down cleanly without scrolling the page (with coarse adjustment via Shift).
    - Vertical touch & mouse drag smoothly increments/decrements value.
    - Double-tap resets value to default.
    - Accessible discrete popup menu for parameters with discrete labels.
- **Accurate Parameter Values & Display Offsets:**
  - `ParameterDescriptor` supports `displayOffset`, `valueLabels`, and `formatValue(num rawValue)` returning pedal-exact strings (e.g., Sequence Filter Step displays 2..8 from raw 0..6, Pattern displays 1..8 from raw 0..7, Speed displays 1..50 + tempo notes).
  - Cleaned up musical note symbols (`𝅚`, `𝅙`, `𝅘`, `♩`, `𝅗`) for tempo-synced parameters.
- **Unmapped Parameter Elimination & Lossless PTCF Round-Tripping:**
  - Removed trailing dummy parameters (up to 12) from `SlotInspectorWidget`, displaying only the true parameters defined in the catalog for each effect.
  - Internal/hidden parameters (`Hidden-1`) filtered by default with an optional "Show Internal" toggle.
  - Preserved trailing raw bytes in `EffectSlot.rawTrailingValues` so binary PTCF encode/decode remains 100% byte-for-byte lossless.

---

## 9. Terminal Sandbox Execution Guidelines

When running `flutter` or `dart` commands in sandboxed environments:
1. **Binary Location:** Flutter is installed at `/home/nreynolds/.local/share/flutter/bin/flutter` and Dart at `/home/nreynolds/.local/share/flutter/bin/dart`. Ensure the path is prefixed or exported:
   ```bash
   export PATH="$HOME/.local/share/flutter/bin:$PATH"
   ```
2. **Read-Only Home Bypass (`HOME=/tmp` with preserved `PUB_CACHE`):** The sandbox filesystem makes `$HOME` read-only for `.dartServer` lock files, while network requests to `pub.dev` are isolated. Always execute `flutter` or `dart` commands with `HOME=/tmp` and explicitly preserved `PUB_CACHE`:
   ```bash
   export PATH="$HOME/.local/share/flutter/bin:$PATH"
   export PUB_CACHE="$HOME/.pub-cache"
   export HOME="/tmp"
   ```
3. **Offline Flags:** Append `--no-pub` to prevent unwanted network calls to pub.dev:
   ```bash
   flutter analyze --no-pub
   flutter test --no-pub <test_file_path>
   ```


