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
- **Milestone 8.8:** Zoom MS Plus Hardware Slot Write Protocol Alignment & ACK Verification — **Completed**
- **Milestone 8.9:** Zoom MS Plus Live Structural Chain Sync (Reorder, Swap, Add, Remove & Dynamic PRM2 Bitmasks) — **Completed**
- **Milestone 8.10:** Zoom MS Plus Initial Active Slot Identification (Opcode 0x33 & Deterministic Bank Signature Fallback) — **Completed**
- **Milestone 8.11:** Linux ALSA Warm-Restart Reliability & Handshake Pacing (`amidi` Cleanup, Port Drain, Init Pacing & Retry Guards) — **Completed**
- **Milestone 9:** Platform Packaging & Release Distribution (Linux .deb/AppImage/.desktop, Android USB Host OTG, Windows Portable ZIP, AppImageHub / AppStream compliance) — **Completed**
- **Milestone 10:** Platform Expansion & Multi-Device Support (Native Android USB MIDI Transport hardware-verified on Fire HD 10 & Pixel 10 Pro XL with Zoom MS-60B+; Multi-Pedal Zoom MS Plus Catalogs: MS-60B+ 98, MS-50G+ 106, MS-70CDR+ 150, MS-200D+ 224; Hardware-Aligned Line 6 Bass POD Pro Baseline) — **Completed**
- **Milestone 11:** Responsive & Adaptive UI Polish (Three-tier `compact`/`medium`/`expanded` breakpoints in `ResponsiveLayoutMetrics`, wrapping toolbars & metadata header, short-viewport unified vertical scrolling, `LongPressDraggable` on Android/iOS touchscreens, and keyboard-safe scrollable dialogs) — **Completed**
- **Milestone 12:** External Format Export & Interoperability (`ExportAdapter` registry for Native JSON, Zoom PTCF `.zptc`, Symbiosis model-suffixed `.zptc` / batch folders, Zoom MultiStomp Studio, and Raw SysEx `.syx`; pure `dart:io` XDG preferences persistence & `ExportFileWriter`; responsive `PatchExportDialog` wired into `PatchLibraryDrawerOrPanel` and `HardwareBankBrowserWidget`) — **Completed**

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
  - Program dump request and write for Line 6 Bass Pod Pro (`0x02` family byte, 36 internal slots `0..35` / 1A–9D).
  - `BankSlotDescriptor` model representing remote hardware patch indices, synchronization state, and bank/slot formatting (`#42 (5-3)`).
  - Hardware Memory Slot Saving (`savePatchToDeviceSlot`): Encodes active or target preset via `protocol.encodePatch(target, programNumber: slotIndex)` and transmits binary memory slot dump SysEx over `MidiTransport.sendSysEx(...)` / `send(...)`. Updates `programNumber`, resets dirty flag, and updates local `bankSlots` cache.
  - Added `MidiTransport.sendSysEx(MidiMessage message)` convenience contract across all transport implementations.
  - Enhanced `WriteToSlotDialog` with error state handling and snackbar confirmation.
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

## 9. Hardware Memory Slot Write Protocol Alignment (Milestone 8.8)

- **Zoom MS Plus Hardware Buffer Alignment:**
  - Standardized unpacked PTCF slot buffer length to fixed 848 bytes (`0x0350`, LSB `0x50`, MSB `0x06`) matching pedal expectations.
  - Zero-padded PTCF binary payloads up to 848 bytes prior to 7-bit packing and CRC calculation.
  - Fixed 7-bit MIDI packing to encode all 848 bytes into 970 SysEx data bytes.
  - Calculated inverted CRC32 ($\sim\text{CRC32}$) across the complete 848-byte padded buffer.
  - Removed erroneous trailing `0x00` padding byte before `0xF7` (SysEx frame length: exactly 989 bytes).
  - Applied the same 848-byte length, PRM2 volume ($100$), active slot bit pattern, and CRC framing to edit buffer updates (`0x64 0x12 0x01`).
- **Hardware ACK Verification & Dialog Guardrails:**
  - Added `DeviceProtocol.isSuccessAck` matching Zoom ACK: `F0 52 00 <familyIdByte> 00 00 F7`.
  - Updated `PatchEditorController.savePatchToDeviceSlot` to await hardware ACK response via `transport.sendRequest` with 2500ms timeout on physical devices.
  - Guarded `WriteToSlotDialog` so write failures/timeouts retain the dialog and display actionable error text rather than prematurely closing with a false success notification.

---

## 10. Live Structural Chain Sync & Reordering Architecture (Milestone 8.9)

- **Root Cause Analysis (Live Reordering & Intermittent Save Revert):**
  - **`64 12 01` is strictly Device-to-Host:** Sending `64 12 01` (PTCF edit buffer dump) from host to pedal in live edit mode is ignored by the physical DSP and LCD. Worse, it triggers the pedal to echo back its existing edit buffer dump (`64 12 01`), which previously overwrote local state and reverted the user's edits in the app.
  - **Live Structural Updates via Parameter Opcodes (`64 20 00`):**
    The MS Plus (`0x6E`) pedal modifies its live edit buffer exclusively via `64 20 00`:
    * `paramNumber = 1`: Sets the DSP algorithm ID in the slot. The 32-bit ID is packed as 5 bytes of 7-bit MIDI data (`buildEffectTypeMessage`). Passing `effectId = 0` empties/clears the slot.
    * `paramNumber = 0`: Sets the bypass state (`00` bypassed, `01` active).
    * `paramNumber = paramIndex + 2`: Sets individual knob parameter values.
    * Changing effect ID resets DSP parameters to defaults on the pedal; host immediately follows up with all parameter values (`buildSlotSyncSequence`), including preserved `rawTrailingValues`.
    * `64 20 00 64 01 <slotIndex>`: Focuses the LCD screen cursor on the active slot.
- **Dynamic PRM2 Bitmasks (`encodePtcf`):**
  - Reordering slots shifts the physical positions of Preamp, BPM, and Line Selector effects.
  - In `ZoomMsPlusProtocol.encodePtcf`, PRM2 bitmasks are now dynamically computed from the active chain:
    * Byte 20 (`prm2PreampSlot`): `(preampBits & 0x3F) << 1` (bitmask of slots containing Preamp models).
    * Bytes 21–22 (`prm2BPMSlot`): Bitmask of slots with tempo sync.
    * Bytes 22–23 (`prm2LineSelSlot`): Bitmask of Line Selector slots.
    * Byte 10 & 11–12: Active cursor slot index bits.
- **Drag-and-Drop & Nudge Indexing (`SignalChainStripWidget` & `PatchEditorController`):**
  - **Card-on-card drops & nudge buttons (`<` / `>`):** Route directly to `swapEffectSlots(indexA, indexB)` for an exact slot swap.
  - **Inter-slot insertion zones (`insertion_zone_$insertIndex`):** Route to `reorderEffectSlots(fromIndex, insertIndex)`, adjusting `insertIndex` (`fromIndex < toIndex ? toIndex - 1 : toIndex`) to account for element removal before insertion.
  - **Echo & ACK Protection:** In-flight synchronization flag `_isSyncingStructure` and dirty-state guards in `applyExternalHardwareUpdate` prevent incoming ACKs or unsolicited patch dumps from reverting local edits during multi-message structural slot bursts.

---

## 11. Initial Active Memory Slot Identification & Write Dialog Pre-Selection (Milestone 8.10)

- **Root Cause Analysis (Missing Active Slot on Connect):**
  - **Edit Buffer Dump (`64 12 01`) contains no slot index:** The Zoom MS Plus edit buffer dump contains only length and PTCF binary payload. Consequently, `Patch.programNumber` initialized to `null`.
  - **Symptoms:** The Hardware Bank sidebar had no slot marked as `ACTIVE IN EDITOR` on initial connection, and opening the "Write to Slot..." dialog defaulted to slot `001` (index 0) rather than the physical pedal's active preset.
- **Opcode `0x33` Hardware Slot Query:**
  - Added `DeviceProtocol.buildCurrentSlotRequest()` implemented in `ZoomMsPlusProtocol` as opcode `0x33` (`F0 52 00 6E 33 F7`).
  - Appended to `ZoomMsPlusProtocol.buildInitSequence()` (`0x53` -> `0x50` -> `0x33`) to request the current bank and program number immediately upon connection.
  - Automatically captures incoming `64 26 00 00` SysEx or Bank Select CC (`B0 00` / `B0 20`) + Program Change (`C0`) to populate `activeHardwareSlotIndex`.
- **Deterministic Bank Signature Fallback:**
  - If the pedal does not explicitly report slot index via opcode `0x33`, `Patch.isSignatureMatch` performs two-pass heuristic matching between the active edit buffer and incoming `0x45` bank slots as they stream in during `syncDeviceBank`:
    * **Pass 1:** Exact signature match (case-insensitive trimmed name, slot count, effect IDs, bypass states, and parameter values within delta tolerance).
    * **Pass 2:** Structural signature match (name, slot count, effect IDs, and bypass states, handling unmapped dummy parameters).
  - As soon as the matching slot is encountered, `DeviceConnectionController.setActiveHardwareSlotIndex` locks onto that slot index without waiting for user patch switches.
- **Controller & UI Layer Synchronization:**
  - `DeviceConnectionController.activeHardwareSlotIndex` synchronizes with `PatchEditorController.patch.programNumber`.
  - In `PatchEditorController.applyExternalHardwareUpdate`, incoming `64 12 01` dumps preserve the known active slot number rather than resetting it to `null`.
  - `HardwareBankBrowserWidget` inspects `patch.programNumber ?? activeHardwareSlotIndex` to highlight the slot card with `ACTIVE IN EDITOR` and teal border styling immediately after connect/sync.
  - `WriteToSlotDialog` pre-selects `activeHardwareSlotIndex` in its slot dropdown by default.

---

## 12. Platform Packaging & AppImageHub Metadata Compliance (Milestone 9)

- **Release Packaging Outputs & `.gitignore`:**
  - Configured root `.gitignore` to exclude all Linux and Windows release staging directories and artifacts (`dist/`, `AppDir/`, `*.AppImage`, `*.deb`, `*.zip`, `*.tar.gz`, `*.tar.xz`, and downloaded `tool/appimagetool`).
- **Linux Desktop & AppStream Metadata Compliance (`appimage.github.io` / AppImageHub):**
  - **Desktop Entry (`linux/packaging/signal-chain.desktop`):** Fully compliant with Freedesktop.org specifications with standard categories `Categories=AudioVideo;Audio;Midi;`, proper `Name=Signal Chain`, `Exec=signal-chain %u`, `Icon=signal-chain`, `Type=Application`, and `Comment`. Validated clean via `desktop-file-validate`.
  - **AppStream MetaInfo (`linux/packaging/io.github.bassmannate.signal_chain.appdata.xml`):** Validated XML matching desktop ID `signal-chain.desktop`, containing component `<id>`, `<metadata_license>FSFAP</metadata_license>`, `<project_license>MIT</project_license>`, `<name>`, `<summary>`, `<description>`, `<developer>`, `<url type="homepage">`, `<url type="bugtracker">`, `<url type="vcs-browser">`, `<provides>`, `<content_rating>`, and release metadata. Validated clean with `appstreamcli validate --strict --no-net`.
  - **AppImage Build Pipeline Integration (`tool/package_linux_appimage.sh`):** Creates `${APPDIR}/usr/share/metainfo/` and copies `io.github.bassmannate.signal_chain.appdata.xml` into the AppDir alongside desktop entries and icons prior to executing `appimagetool`.
  - **Packaging Regression Suite:** Verified by `test/packaging_config_test.dart` asserting desktop configuration, icon assets, AppStream XML fields, packaging scripts, and Android/Windows manifest entries.

---

## 13. Platform Expansion & Multi-Device Support (Milestone 10)

- **Native Android USB MIDI Transport (Hardware-Verified):**
  - Implemented Android native bridge in `MainActivity.kt` (`android.media.midi.MidiManager`, outgoing 256-byte chunking) paired with `AndroidMidiTransport` (`lib/src/transport/android_midi_transport.dart` / `lib/core/midi/android_midi_transport.dart`) featuring `_rxBuffer` incoming SysEx stitching and MIDI framing, wired into `lib/main.dart` and covered by `test/core/midi/android_midi_transport_test.dart`.
  - Physically tested and verified over USB OTG on both a **Fire HD 10** tablet and a **Pixel 10 Pro XL** phone connected to a physical **Zoom MS-60B+**.
- **Multi-Pedal Zoom MS Plus Catalogs (578 Total Definitions):**
  - Refactored `tool/generate_zoom_catalog.dart` (standalone pure-Dart CLI) to ingest vendored CSV, JSON, and JS reference definitions in `tool/reference/` and generate typed catalogs for all four pedals: **MS-60B+ (98 effects)**, **MS-50G+ (106 effects)**, **MS-70CDR+ (150 effects)**, and **MS-200D+ (224 effects, with full-name overlay from `zoom-effect-ids-full-names-ms200dp.js`)**.
  - Wired per-family effect lookup, category assignment, `displayOffset`, and discrete `labels` resolution through `ZoomMsPlusCatalog`, `EffectCatalogRegistry`, `ZoomMsPlusProtocol`, and `StudioTheme` while preserving full backward compatibility for MS-60B+.
- **Hardware-Aligned Line 6 Bass POD Pro Baseline:**
  - Aligned `Line6BassPodProProtocol`, `Line6BassPodProCatalog`, and `DeviceFamily.line6BassPodPro` (`totalMemorySlots = 36`, 1A–9D) with verified firmware 1.40 hardware SysEx captures: Universal Identity Reply (`00 01 0C` manufacturer, `02 00` family code LSB-first), `0x02` SysEx family byte, 80-byte MSB-first nibble-packed program dumps (169-byte edit buffer / 170-byte program dump), 16 amps, 16 cabinets, Compressor/Noise Gate, 16 effects, and verified hardware CCs.

---

## 14. Responsive & Adaptive UI Polish (Milestone 11)

- **Three-Tier Breakpoints & Short-Viewport Handling (`lib/features/theme/responsive_layout.dart` & `lib/main.dart`):**
  - Implemented `ResponsiveLayoutMetrics` with `ViewportSizeClass` (`compact < 600px`, `medium 600–1024px`, `expanded > 1024px`) and `isShortEditorBody(availableBodyHeight < 440)`.
  - Collapsed `PatchLibraryDrawerOrPanel` (`Local Presets` | `Hardware Bank`) into an adaptive `endDrawer` on compact and medium viewports (`<= 1024px`, e.g., Pixel 10 Pro XL and Fire HD 10 `1024x600`), while keeping `SlotInspectorWidget` and `EffectBankPaletteWidget` side-by-side when editor body width `>= 700px` and non-short.
  - Replaced `TabBarView` on narrow/short screens with an explicit `INSPECTOR | EFFECT PALETTE` segmented tab bar and unified vertical `SingleChildScrollView` on short viewports (`844x390` landscape or open Android soft keyboard), paired with `LayoutBuilder` bounded/unbounded height awareness in `SlotInspectorWidget` and `EffectBankPaletteWidget`.
- **Wrapping Toolbars, Scrollable Dialogs & Touch Ergonomics:**
  - Replaced horizontal `SingleChildScrollView` clipping in `ConnectionBarWidget` and `PatchMetadataHeaderWidget` with responsive `Wrap` layouts and ellipsized port dropdowns.
  - Removed rigid outer `height: 255` on `SignalChainStripWidget`, scaled card grid `mainAxisExtent` with `textScalerOf` in `EffectBankPaletteWidget`, and enlarged touch targets on slot controls, tempo `+/-`, bank slot actions, and discrete `RotaryKnobWidget` menus.
  - Switched reorderable slots and palette cards to `LongPressDraggable` on mobile touch platforms (Android/iOS) so horizontal/vertical swipes scroll naturally while keeping immediate `Draggable` on desktop.
  - Made `EffectPickerDialog`, `WriteToSlotDialog`, and `PatchLibraryDrawerOrPanel` Import/Export dialogs viewport-clamped and scrollable down to keyboard-resized heights.

---

## 15. Terminal Sandbox Execution Guidelines

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


