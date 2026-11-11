# Project Status & Milestone Roadmap: `signal_chain_flutter`

**Current Status:** Milestone 5 Complete (Native Platform MIDI Transport, Composite Hardware/Simulation Bridge & Persistent Storage Wiring)  
**Active Milestone:** Milestone 6 (Platform Packaging & Release Distribution)  
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

### 🟢 Milestone 4: Application State Controllers & Cross-Platform Signal Chain UI
*Status:* **Completed**
- [x] **Zero-Dependency State Layer (`lib/features/` via Flutter `ChangeNotifier`):**
  * `DeviceConnectionController`: Port discovery, connection lifecycle, Universal Identity Request handshake with fallback heuristics, hardware init sequence dispatch, and protocol resolution (`ZoomMsPlusProtocol` & `Line6BassPodProProtocol`).
  * `PatchEditorController`: Live patch editing, slot selection, dirty state tracking, hardware patch pull (`pullCurrentPatch`), push (`pushPatchToDevice`), slot bypass toggling (`toggleSlotEnabled`), algorithm swapping (`changeSlotEffect`), real-time parameter tweaking (`updateParameter`), and bidirectional incoming hardware sync.
  * `PatchLibraryController`: Local preset management wrapping `PatchLibraryRepository`, text search, `DeviceFamily` filter chips, tag filtering, CRUD operations, and JSON/SysEx import/export.
- [x] **Studio Dark-Mode UI Components (`lib/features/` & `lib/main.dart`):**
  * `StudioTheme`: High-contrast dark studio palette with category accent colors (Dynamics, Filter/EQ, Drive, Amp/Cab, Modulation, Delay/Reverb, Pitch/Synth).
  * `ConnectionBarWidget`: Status badge, MIDI port dropdown, device family picker, "Pull Patch" / "Push Patch" sync actions, and "Save to Library" button.
  * `SignalChainStripWidget`: Horizontal pedalboard stompbox chain with slot index, category badge, effect name, interactive Bypass/Enable LED switch, and selection highlight.
  * `SlotInspectorWidget`: Parameter inspector with effect algorithm dropdown populated from `EffectCatalogRegistry`, discrete label dropdowns, continuous sliders, and real-time updates.
  * `PatchLibraryDrawerOrPanel`: Responsive preset library browser (side panel on desktop >= 900px, endDrawer on compact screens).
  * `SignalChainApp` entry point pre-wired with simulated virtual ports (`Zoom MS-60B+ (Simulated)` & `Line 6 Bass Pod Pro (Simulated)`) and pre-seeded preset repository.
- [x] **Targeted Unit & Widget Test Suites (100% passing):**
  * `test/features/patch_editor_controller_test.dart` (7 tests).
  * `test/features/patch_library_controller_test.dart` (8 tests).
  * `test/widget_test.dart` (2 comprehensive desktop wide and mobile compact widget tests).
- [x] Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 5: Native Platform MIDI Transport, Composite Hardware/Simulation Bridge & Persistent Storage Wiring
*Status:* **Completed**
- [x] **Zero-Dependency Linux ALSA RawMIDI Transport (`lib/core/midi/linux_alsa_midi_transport.dart`):**
  * Hardware port discovery parsing `amidi -l` with device name, port ID (`hw:X,Y,Z`), and direction (`I`/`O`/`IO`) extraction.
  * Robust fallback discovery scanning `/proc/asound/cards` and `/dev/snd/midiC*D*`.
  * Background process listener (`amidi -p <port> -d`) with hex stream state machine for assembling fragmented SysEx (`F0 ... F7`), Continuous Controller (`B0 cc vv`), and Program Change (`C0 pp`) messages without data loss.
  * Outbound transmission formatting uppercase hex arrays for `amidi -p <port> -S "<hex>"`.
  * Injectable `ProcessRunner` and `ProcessStarter` for deterministic, sandboxed unit testing without native OS dependencies.
- [x] **Composite MIDI Transport Architecture (`lib/core/midi/composite_midi_transport.dart`):**
  * Unified aggregation over arbitrary child transports (e.g. `LinuxAlsaMidiTransport` + `MockMidiTransport`).
  * Aggregated port discovery with automatic routing of `connect()`, `send()`, `onMessageReceived`, and `disconnect()` to the active transport.
- [x] **Persistent Storage Wiring & Starter Seed (`lib/main.dart`):**
  * Platform-appropriate preset storage directory resolution (`$XDG_DATA_HOME/signal_chain_flutter/presets`, `%APPDATA%/signal_chain_flutter/presets`, etc.) with graceful fallback to `InMemoryPatchLibraryRepository`.
  * Safe starter preset seeding on first launch when repository is empty.
  * Seamless test/runtime bifurcation preserving offline deterministic widget test execution.
- [x] **Preset Import/Export Dialogs (`lib/features/library/patch_library_drawer_or_panel.dart`):**
  * Multi-format "Import JSON / SysEx" dialog supporting raw JSON presets or hex SysEx dumps with auto-detection of device protocol.
  * Tabbed "Export JSON / SysEx" dialog displaying pretty-printed JSON and raw hex dumps with copy-to-clipboard buttons (`Clipboard.setData`).
- [x] **Comprehensive Test Suites (100% passing, 124 total tests):**
  * `test/core/midi/linux_alsa_midi_transport_test.dart` (10 tests).
  * `test/core/midi/composite_midi_transport_test.dart` (8 tests).
  * `test/widget_test.dart` (+1 test for import/export modal workflows, 3 total widget tests).
- [x] Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟡 Milestone 6: Platform Packaging & Release Distribution
*Status:* **Ready / Next**
- [ ] Linux AppImage / Debian packaging and desktop launcher entries (`.desktop`, icons).
- [ ] Android USB Host OTG permissions in `AndroidManifest.xml` and release APK / AAB setup.
- [ ] Windows MSIX / portable zip packaging.

---

## 2. Workspace Audit Summary

| Item | Status | Notes |
| :--- | :--- | :--- |
| **Workspace Repository** | Clean Flutter Project | Flutter 3.47.9 / Dart 3.13.7 baseline |
| **Legacy Source Code** | Audited | Sibling archive audited at `~/.cache/.fr-CFTZU3/` |
| **Directory Scaffolding** | Complete | Clean architecture layers maintained |
| **Core MIDI Transport** | Complete | `MidiTransport`, `MidiMessage`, `MockMidiTransport`, `LinuxAlsaMidiTransport`, `CompositeMidiTransport` |
| **Domain Models** | Complete | `DeviceFamily`, `ParameterDescriptor`, `EffectSlot`, `Patch` |
| **SysEx & Protocol Engine** | Complete | `SysexCodec`, `ZoomMsPlusProtocol`, `Line6BassPodProProtocol` |
| **Effect Catalogs** | Complete | `EffectDefinition`, `EffectCatalogRegistry`, `ZoomMsPlusCatalog`, `Line6BassPodProCatalog` |
| **Persistence Repositories** | Complete | `PatchLibraryRepository`, `InMemoryPatchLibraryRepository`, `FileSystemPatchLibraryRepository` |
| **State Controllers** | Complete | `DeviceConnectionController`, `PatchEditorController`, `PatchLibraryController` |
| **Studio UI & Widgets** | Complete | `StudioTheme`, `ConnectionBarWidget`, `SignalChainStripWidget`, `SlotInspectorWidget`, `PatchLibraryDrawerOrPanel` (Import/Export dialogs) |
| **Static Analysis** | Passing (0 issues) | Verified via `flutter analyze --no-pub` |
| **Unit & Widget Tests** | 100% Passing | 124 tests passing across all test suites |

