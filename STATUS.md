# Project Status & Milestone Roadmap: `signal_chain_flutter`

**Current Status:** Milestone 3 Complete (Effect Catalogs, Patch Serialization & Local Persistence Layer)  
**Active Milestone:** Milestone 4 (Ready / Next)  
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

### 🟢 Milestone 2: Pure Dart Protocol & SysEx Engine
*Status:* **Completed**
- [x] **Core SysEx Utilities (`lib/protocols/sysex_codec.dart`):**
  * Byte packing/unpacking: 7-bit to 8-bit (`pack8BitTo7Bit`, `unpack7BitTo8Bit`) with MSB-header grouping.
  * 4-bit nibble packing/unpacking (`packNibbles`, `unpackNibbles`).
  * Big-endian bitfield extraction and insertion (`getBits`, `setBits`).
  * IEEE 802.3 CRC32 calculation and Zoom 5-byte 7-bit CRC generator (`calculateZoom7BitCrc`).
  * Framing helpers (`isSysEx`, `isIdentityReply`).
- [x] **Device Protocol Abstract Contract (`lib/protocols/device_protocol.dart`):**
  * Abstract interface defining identity matching, initialization sequences, current patch and memory slot requests, bidirectional patch encoding/decoding, and real-time parameter change handling.
- [x] **Zoom MS Plus Series Protocol (`lib/protocols/zoom_ms_plus_protocol.dart`):**
  * Support for Zoom MS-50G+, MS-60B+, MS-70CDR+, MS-200D+ (`0x52` manufacturer, `0x6E 0x00` family).
  * Parameter edit mode enable (`0x50`) / disable (`0x51`) and PC mode enable (`0x52`) framing.
  * Current patch (`64 13` request / `64 12 01` dump) and memory slot (`46 00 00` request / `45 00 00` dump) handling.
  * PTCF 8-bit chunk parser and serializer (`PTCF`, `NAME`, `EDTB`, `PRM2`, `TXE1`).
  * 24-byte EDTB reversed bitfield mapping (1-bit enabled, 29-bit DSP algorithm ID, 12-bit and 8-bit parameter values).
  * Real-time parameter edit SysEx generator (`64 20 00`) and hardware feedback parser (`64 20 01`).
- [x] **Line 6 Bass Pod Pro Protocol (`lib/protocols/line6_bass_pod_pro_protocol.dart`):**
  * Line 6 3-byte SysEx header framing (`F0 00 01 0C 01 ... F7`).
  * Edit buffer dump request (`F0 00 01 0C 01 00 F7`) and program dump request (`F0 00 01 0C 01 01 <prog> F7`).
  * 72-byte edit buffer parser & serializer (Amp, Cabinet, Compressor, Modulation/FX slots, 16-char ASCII patch name).
  * Real-time Continuous Controller (CC) modulation mapping (Drive CC#4, Bass CC#14, Mid CC#15, Treble CC#16, Chan Vol CC#17, Amp CC#12, Cab CC#13, Comp CC#64, FX CC#11/19).
  * Program Change (PC 0–127) memory recall mapping.
- [x] **Comprehensive Protocol Unit Test Suites (100% passing):**
  * `test/protocols/sysex_codec_test.dart` (16 tests).
  * `test/protocols/zoom_ms_plus_protocol_test.dart` (13 tests).
  * `test/protocols/line6_bass_pod_pro_protocol_test.dart` (10 tests).
- [x] Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 3: Effect Catalogs, Patch Serialization & Local Persistence Layer
*Status:* **Completed**
- [x] **Deterministic JSON Serialization for Domain Models (`lib/models/`):**
  * `DeviceFamily`: Stable string serialization (`toJson()`) and fallback to `DeviceFamily.unknown` (`fromJson()`).
  * `ParameterDescriptor` & `ParameterValue`: Symmetrical `toJson()` / `fromJson()` with range, step, unit, and discrete label list preservation.
  * `EffectSlot`: Symmetrical `toJson()` / `fromJson()`.
  * `Patch`: Rich metadata support with `tags` (`List<String>`), `author` (`String?`), `notes` (`String?`), and `updatedAt` (`DateTime?`), full `copyWith` support, and value equality.
- [x] **Effect & Parameter Metadata Catalogs (`lib/protocols/catalogs/`):**
  * `EffectDefinition` immutable model and `EffectCatalogRegistry` lookup service with hex normalization and clean fallback definitions.
  * `ZoomMsPlusCatalog`: Core MS-60B+ and MS Plus effects extracted across 11 categories (Dynamics, Filter/EQ, Drive, Preamp, Amp Models, Modulation, Pitch, Synth, SFX, Delay, Reverb) with complete parameter definitions and discrete labels.
  * `Line6BassPodProCatalog`: 16 Amp models, 8 Cabinet models, Compressor block, and 8 Modulation/Delay effects.
  * Bidirectional catalog lookup integration in `ZoomMsPlusProtocol` and `Line6BassPodProProtocol`.
- [x] **Local Storage Persistence Layer (`lib/core/storage/`):**
  * `PatchLibraryRepository` abstract contract with search filtering, tag matching, CRUD operations, JSON import/export, and raw SysEx import/export.
  * `InMemoryPatchLibraryRepository`: Deterministic in-memory repository for unit testing and preview states.
  * `FileSystemPatchLibraryRepository`: Pure `dart:io` repository with atomic write-via-temp-file safety (`.tmp_<timestamp>` rename) and disk-level `.json` and `.syx` import/export.
- [x] **Comprehensive Unit Test Suites (100% passing):**
  * `test/models/models_test.dart` (11 tests, +5 tests for JSON round-trip and metadata).
  * `test/protocols/catalogs/effect_catalog_test.dart` (12 tests).
  * `test/core/storage/patch_library_repository_test.dart` (14 tests).
- [x] Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟡 Milestone 4: Cross-Platform UI & Real-Time Parameter Control
*Status:* **Ready / Next**
- [ ] Add `flutter_riverpod` state layer:
  * `midiTransportProvider` (mocked in tests, native in production).
  * `deviceDiscoveryController` (auto-scan, connection lifecycle).
  * `activePatchController` (live editing, undo/redo buffer, debounced MIDI transmissions).
  * `patchLibraryController` (local persistence, preset search, bank management).
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
| **Legacy Source Code** | Audited | Sibling archive audited at `~/.cache/.fr-CFTZU3/` |
| **Directory Scaffolding** | Complete | Clean architecture layers maintained |
| **Core MIDI Transport** | Complete | `MidiTransport`, `MidiMessage`, `MockMidiTransport` |
| **Domain Models** | Complete | `DeviceFamily`, `ParameterDescriptor`, `EffectSlot`, `Patch` (with JSON round-trip & metadata) |
| **SysEx & Protocol Engine** | Complete | `SysexCodec`, `ZoomMsPlusProtocol`, `Line6BassPodProProtocol` |
| **Effect Catalogs** | Complete | `EffectDefinition`, `EffectCatalogRegistry`, `ZoomMsPlusCatalog`, `Line6BassPodProCatalog` |
| **Persistence Repositories** | Complete | `PatchLibraryRepository`, `InMemoryPatchLibraryRepository`, `FileSystemPatchLibraryRepository` |
| **Static Analysis** | Passing (0 issues) | Verified via `flutter analyze --no-pub` |
| **Unit Tests** | 100% Passing | 89 unit tests passing across core, models, protocols, catalogs, and storage |
