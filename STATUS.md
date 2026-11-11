# Project Status & Milestone Roadmap: `signal_chain_flutter`

**Current Status:** Milestone 1 Complete (Scaffolding, Core Models & MIDI Abstraction)  
**Active Milestone:** Milestone 2 (Ready / Next)  
**Last Updated:** 2026-11-10

---

## 1. Milestone Roadmap

### 🟢 Milestone 1: Project Scaffolding, Domain Models & Core MIDI Transport Abstraction
*Status:* **Completed**
- [x] **Stage 0:** Workspace audit & clean baseline analysis.
- [x] **Stage 0:** Foundational documentation scaffolding (`PROJECT_CONTEXT.md`, `SPEC.md`, `STATUS.md`).
- [x] **Stage 0:** Clean directory structure scaffolding (`lib/core/midi/`, `lib/protocols/`, `lib/models/`, `lib/features/`).
- [x] Implement core MIDI abstract contracts:
  * `MidiPortDescriptor` (id, name, manufacturer, isInput, isOutput, equality, toString).
  * `MidiMessage` (`Uint8List` data, timestamp, `isSysEx`, `isControlChange`, `isProgramChange`, factories `sysEx`, `controlChange`, `programChange`, byte equality).
  * `MidiTransport` abstract interface (port listing, connection lifecycle, send, `sendSysExAndWait`, dispose).
- [x] Implement `MockMidiTransport` for deterministic unit testing and hardware simulation:
  * Port listing and connection management.
  * `sentMessages` recording and assertion helpers.
  * `simulateIncomingMessage` stream injection.
  * Bidirectional auto-responder registration (`registerResponder`).
  * `sendSysExAndWait` response matching and timeout handling.
- [x] Implement core domain models:
  * `DeviceFamily` enum (`zoomMs50gPlus`, `zoomMs60bPlus`, `zoomMs70cdrPlus`, `zoomMs200dPlus`, `line6BassPodPro`, `unknown`).
  * `ParameterDescriptor` and `ParameterValue` (ranges, normalized values, discrete labels, formatted display strings).
  * `EffectSlot` (slotIndex, effectId, effectName, isEnabled, parameters, copyWith).
  * `Patch` (id, name, deviceFamily, programNumber, slots, metadata, copyWith).
- [x] Comprehensive unit test suites (100% passing):
  * `test/core/midi/midi_transport_test.dart` (12 tests).
  * `test/models/models_test.dart` (6 tests).
  * `test/widget_test.dart` (app smoke test).
- [x] Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟡 Milestone 2: Pure Dart Protocol & SysEx Engine
*Status:* **Ready / Next**
- [ ] **Core MIDI Utilities (`lib/protocols/midi_utils/`):**
  * Byte packing/unpacking: 7-bit to 8-bit (`pack7to8`, `unpack8to7`).
  * SysEx framing utilities (delimiter extraction, packet slicing, checksum validation).
- [ ] **Zoom MS Plus Series Protocol (`lib/protocols/zoom/`):**
  * Identity request & reply parsing (handshake `0x52`).
  * Editor mode activation & keep-alive ping framing.
  * Patch memory dump parser & serializer (6-slot effect blocks, 32-bit DSP IDs).
  * Real-time parameter change encoder and parser.
  * Unit test suite against captured SysEx byte fixtures (`test/protocols/zoom/`).
- [ ] **Line 6 Bass Pod Pro Protocol (`lib/protocols/line6/`):**
  * Line 6 SysEx header framing (`0xF0 0x00 0x01 0x0C ... 0xF7`).
  * Program Change (PC) mapping and Continuous Controller (CC) mapping table.
  * Edit buffer request & parser.
  * Parameter range scalers (amp models, cab models, drive, tone controls).
  * Unit test suite against captured SysEx fixtures (`test/protocols/line6/`).

---

### ⚪ Milestone 3: Patch Library & Local Persistence Layer
*Status:* **Planned**
- [ ] File serialization engine:
  * Raw SysEx (`.syx`) import/export.
  * Structured JSON patch and bank definitions.
- [ ] Local storage repository interface & implementation for user preset libraries.
- [ ] Unit tests for patch serialization and library persistence (`test/models/`, `test/features/library/`).

---

### ⚪ Milestone 4: Cross-Platform UI & Real-Time Parameter Control
*Status:* **Planned**
- [ ] Add `flutter_riverpod` state layer.
- [ ] Riverpod state providers:
  * `deviceConnectionController` (auto-scan, connection lifecycle).
  * `activePatchController` (live editing, undo/redo buffer).
  * `libraryController` (preset management).
- [ ] Cross-platform UI components:
  * Device selector & status header.
  * Virtual pedalboard effect chain visualization (drag-to-reorder slots).
  * Responsive parameter editors (rotary knobs, toggle switches, enum dropdowns).
  * Preset bank organizer (desktop two-pane layout / mobile tabbed layout).
- [ ] Platform MIDI integration:
  * Linux ALSA platform integration.
  * Android USB OTG / MIDI API integration.
  * Windows WinMM / WinRT MIDI integration.

---

## 2. Workspace Audit Summary

| Item | Status | Notes |
| :--- | :--- | :--- |
| **Workspace Repository** | Clean Flutter Project | Flutter 3.47.9 / Dart 3.13.7 baseline |
| **Legacy Source Code** | Not Present | Standalone clean repo |
| **Directory Scaffolding** | Complete | `lib/core/midi/`, `lib/protocols/`, `lib/models/`, `lib/features/` created |
| **Core MIDI Transport** | Complete | Fully tested with `MockMidiTransport` |
| **Domain Models** | Complete | `DeviceFamily`, `ParameterDescriptor`, `EffectSlot`, `Patch` tested |
| **Static Analysis** | Passing (0 issues) | Verified via `flutter analyze --no-pub` |
| **Unit Tests** | 100% Passing | 18 unit tests across MIDI and models passing |
