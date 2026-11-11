# Project Context: `signal_chain_flutter`

## 1. Project Overview

`signal_chain_flutter` is a cross-platform rewrite of the Node.js/Electron `signal-chain` patch editor and preset library manager. It provides real-time parameter editing, preset management, bank backup/restore, and chain reorganization for guitar and bass multi-effects processors, specifically:
- **Zoom MS Plus Series** pedals (e.g., MS-50G+, MS-60B+, MS-70CDR+, MS-200+).
- **Line 6 Bass Pod Pro** rackmount multi-effects processors.

The goal of this Flutter rewrite is to replace the heavier Electron desktop footprint with a high-performance, single-codebase application capable of running smoothly across desktop and mobile devices.

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

## 6. Terminal Sandbox Execution Guidelines

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


