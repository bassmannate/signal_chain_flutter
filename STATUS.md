# Project Status & Milestone Roadmap: `signal_chain_flutter`

**Current Status:** Milestone 15 Complete (Android Release Polish, F-Droid Readiness & Live Performance Setlist Mode)  
**Active Milestone:** Milestone 15 Complete / Ready for Local Verification  
**Last Updated:** 2026-11-13

---

## 1. Milestone Roadmap

### 🟢 Milestone 15: Android Release Polish, F-Droid Readiness & Live Performance Setlist Mode
*Status:* **Completed**
- [x] **Android Branding, Adaptive Icons & Dark Launch Background (`android/app/src/main/` & `tool/generate_android_icons.py`):**
  * Updated `AndroidManifest.xml` to `android:label="Signal Chain"` and `android:roundIcon="@mipmap/ic_launcher_round"`.
  * Generated `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` & `ic_launcher_round.png` (`48/72/96/144/192` px) and `fastlane/metadata/android/en-US/images/icon.png` (`512×512` px) via `tool/generate_android_icons.py`, plus `mipmap-anydpi-v26/ic_launcher*.xml` adaptive/monochrome layers, `drawable/ic_launcher_foreground.xml`, `values/colors.xml` (`#121318`), and dark `launch_background.xml`.
- [x] **Android Release Signing, F-Droid Reproducible Builds & CI Artifact Naming (`android/app/build.gradle.kts`, `.github/workflows/release.yml`, `fastlane/metadata/android/en-US/`):**
  * Added env/property-driven release signing with safe debug fallback and `dependenciesInfo { includeInApk = false; includeInBundle = false }`.
  * Added optional `ANDROID_KEYSTORE_BASE64` decoding/cleanup in `.github/workflows/release.yml` outputting `dist/signal-chain-${VERSION}-android.apk`, and created `fastlane/metadata/android/en-US/` listings & changelogs.
- [x] **Live Performance Setlist Mode (`lib/models/setlist.dart`, `lib/core/storage/`, `lib/features/setlist/`):**
  * Implemented `Setlist` & `SetlistEntry` models, `SetlistRepository` (`InMemorySetlistRepository` & atomic `FileSystemSetlistRepository`), `PatchEditorController.activatePatchLive`, and `SetlistController` (live `64 20 00` / `encodePatch` dispatch, missing-preset & device-mismatch guards, and debounced incoming MIDI PC/CC foot-controller stepping).
  * Built `SetlistBrowserWidget` (`Setlists` tab + `"Add to Setlist"` in `PatchLibraryDrawerOrPanel`) and high-contrast `SetlistPerformanceView` Stage Mode (`Stage Mode` toggle in `ConnectionBarWidget`, `◄ PREVIOUS` / `NEXT ►` stepping, live stompbox bypasses, and desktop arrow shortcuts).
- [x] **Unit & `FakeAsync`-Safe Widget Tests (13 new tests, 296 total):**
  * Expanded `test/packaging_config_test.dart` (+2 tests) and added `test/models/setlist_test.dart` (2 tests), `test/core/storage/setlist_repository_test.dart` (2 tests), `test/features/setlist/setlist_controller_test.dart` (4 tests), and `test/features/setlist/setlist_ui_test.dart` (3 tests).

---

### 🟢 Milestone 14: Editor Power-User Ergonomics (Undo/Redo, A/B Compare & Patch Diff Preview)
*Status:* **Completed**
- [x] **Pure Dart Patch Diff Engine (`lib/models/patch_diff.dart`):**
  * Implemented `PatchDiff`, `SlotDiff`, `SlotDiffKind`, and `ParameterDiff` comparing metadata (name, tempo), slot structure (`added`, `removed`, `replaced`, `modified`, `unchanged`), bypass states, and formatted parameter values while filtering `Hidden-*` descriptors by default.
- [x] **Bounded Undo/Redo History & A/B Tone Compare (`lib/features/editor/patch_edit_history.dart`, `patch_editor_controller.dart`):**
  * Implemented `PatchEditHistory` (50-step cap) with explicit rotary-knob drag gesture transactions (`beginEditGesture` / `endEditGesture` wired to `RotaryKnobWidget.onDragStart` / `onDragEnd`) and 600ms time-window coalescing for scroll wheel, tempo slider, and patch name typing.
  * Added `CompareSlot` (`A`/`B`) snapshots (`captureCompareA`, `toggleCompareSlot`, `copyCompareSlot`, `swapCompareSlots`, `diffAB`) and live hardware delta sync (`_syncPatchTransitionToDevice`) dispatching Zoom `64 20 00` deltas (never `64 12 01`) and Line 6 `encodePatch`, while excluding `applyExternalHardwareUpdate` from the Undo stack.
- [x] **Responsive UI & Keyboard Shortcuts (`patch_metadata_header_widget.dart`, `patch_diff_dialog.dart`, `write_to_slot_dialog.dart`, `patch_import_dialog.dart`, `patch_library_drawer_or_panel.dart`, `lib/main.dart`):**
  * Added Undo/Redo buttons, `A | B` toggle, View Diff button, and A/B actions menu to `PatchMetadataHeaderWidget` within its responsive `Wrap`.
  * Created viewport-clamped `PatchDiffDialog` and integrated it into A/B compare, `WriteToSlotDialog` pre-write slot diffing, `PatchImportDialog` entry previews, and `PatchLibraryDrawerOrPanel` preset cards.
  * Wired `Ctrl+Z` / `Cmd+Z` (Undo) and `Ctrl+Y` / `Ctrl+Shift+Z` / `Cmd+Shift+Z` (Redo) in `lib/main.dart`, guarded against focused `EditableText` widgets.
- [x] **Unit & `FakeAsync`-Safe Widget Tests (14 new tests, 283 total):**
  * Added `test/models/patch_diff_test.dart`, `test/features/patch_edit_history_test.dart`, `test/features/editor/undo_compare_diff_ui_test.dart`, and expanded `test/features/patch_editor_controller_test.dart`.

---

### 🟢 Milestone 13: External File Import & Round-Trip Restore
*Status:* **Completed**
- [x] **Symmetric Import Layer (`lib/core/import/`):**
  * Implemented `ImportFormat`, `ImportedPatchEntry`, `ImportBatchResult` (`ImportDiagnostic`), `ImportAdapter`, and `PatchImporter` with magic-header and filename-suffix auto-detection.
  * Added 5 format decoders: `NativeJsonImportAdapter` (single `.json` + `signal_chain_library` bundles), `ZoomPtcfImportAdapter` (`.zptc`), `SymbiosisImportAdapter` (`.60bp.zptc` / `.50gp.zptc` / `.70cdrp.zptc` / `.200dp.zptc` + batch folder restore), `ZoomMultistompStudioImportAdapter` (`.zptc`), and `RawSysExImportAdapter` (Zoom `0x45` 989-byte / `64 12 01`, Line 6 `0x02` 170/169-byte, and multi-message `.syx` streams).
  * Added `ImportFileSystem` (`LocalImportFileSystem` backed by `dart:io` + `InMemoryImportFileSystem` for deterministic widget tests).
- [x] **Responsive Import Dialog & Controller Integration (`lib/features/library/`):**
  * Built `PatchImportDialog` with File & Folder Browser tab (quick locations `SignalChainExports`, `Documents`, `Home`, directory navigation, extension filter, "Import Folder"), Paste JSON / SysEx tab ("Paste from Clipboard"), Preview & Selection pane with format/device badges, per-patch checkboxes, and mismatch/error banners.
  * Wired `PatchLibraryController.importEntries` with collision-safe ID generation and `PatchImportDialog` into `PatchLibraryDrawerOrPanel`.
  * Handled mismatched "Load into Editor" cleanly: auto-switches offline `activeFamily` when disconnected, locks `activeFamily` with warning when connected.
- [x] **Unit & Widget Tests:**
  * Added `test/core/import/patch_importer_test.dart` (round-trip & malformed-input unit tests) and `test/features/library/patch_import_dialog_test.dart` (FakeAsync-safe widget tests), and updated `test/widget_test.dart`.

---

### 🟢 Milestone 12: External Format Export & Interoperability
*Status:* **Completed**
- [x] **Export Adapter Architecture (`lib/core/export/`):**
  * Implemented `ExportFormat`, `ExportPayload`, `ExportAdapter`, and `ExportAdapterRegistry` with zero external pub dependencies.
  * Added 5 format serializers: `NativeJsonExportAdapter` (`.json`), `ZoomPtcfExportAdapter` (848-byte `.zptc`), `SymbiosisExportAdapter` (model-suffixed `.60bp.zptc` / `.50gp.zptc` / `.70cdrp.zptc` / `.200dp.zptc` and batch folder exports), `ZoomMultistompStudioExportAdapter` (`.zptc`), and `RawSysExExportAdapter` (`.syx` for Zoom 989-byte `0x45` and Line 6 170-byte `0x02`).
  * Implemented pure `dart:io` `ExportFileWriter` targeting OS-appropriate `SignalChainExports` directories.
- [x] **XDG / AppData Preferences Persistence (`lib/core/storage/`):**
  * Added `AppPreferencesRepository`, `InMemoryPreferencesRepository`, and `FileSystemPreferencesRepository` (atomic write-temp-then-rename `preferences.json`) wired into `PatchLibraryController` and `lib/main.dart`.
- [x] **Responsive Export Dialog & UI Integration (`lib/features/library/`):**
  * Built `PatchExportDialog` with format dropdown, "Set as default format" checkbox, editable filename/folder name, Line 6 compatibility filtering/skipped-item warnings, clipboard copy, and file/folder save.
  * Wired into `PatchLibraryDrawerOrPanel` (single-patch and full-library export) and `HardwareBankBrowserWidget` (bank backup export).
- [x] **Unit & Widget Tests:**
  * Added `test/core/export/export_adapters_test.dart`, `test/core/storage/preferences_repository_test.dart`, and `test/features/library/patch_export_dialog_test.dart`.

---

### 🟢 Milestone 11: Responsive & Adaptive UI Polish
*Status:* **Completed**
- [x] **Responsive Breakpoints & Adaptive Workspace (`lib/features/theme/responsive_layout.dart`, `lib/main.dart`):**
  * Introduced `ResponsiveLayoutMetrics` with `compact` (`< 600px`), `medium` (`600–1024px`), and `expanded` (`> 1024px`) breakpoints plus `isShortEditorBody(availableBodyHeight < 440)`.
  * Collapsed `PatchLibraryDrawerOrPanel` into a slide-over `endDrawer` (`min(360px, 88% width)`) on compact/medium viewports (`<= 1024px`), while keeping `SlotInspectorWidget` and `EffectBankPaletteWidget` side-by-side on medium/tablet screens (`width >= 700px` and non-short, e.g., Fire HD 10 `1024x600`).
  * Replaced `TabBarView` on narrow/short screens with an explicit `INSPECTOR | EFFECT PALETTE` segmented tab bar and unified vertical `SingleChildScrollView` on short landscape / keyboard-resized viewports (`844x390`, `390x420`).
- [x] **Wrapping Toolbars, Unbounded-Height Inspector/Palette & Touch Ergonomics:**
  * Updated `ConnectionBarWidget` and `PatchMetadataHeaderWidget` from horizontal scroll clipping to responsive `Wrap` layouts with ellipsized port dropdowns and larger touch constraints.
  * Removed outer fixed `height: 255` on `SignalChainStripWidget` and adapted strip height (`156px` compact/short vs. `172px` desktop), enlarged slot/bank/tempo/discrete-knob touch targets, and scaled palette grid `mainAxisExtent` (`76 * textScale`).
  * Added `LayoutBuilder` `hasBoundedHeight` support in `SlotInspectorWidget` and `EffectBankPaletteWidget`, and switched `Draggable` to `LongPressDraggable` on Android/iOS touch platforms while preserving immediate `Draggable` on desktop.
- [x] **Keyboard-Safe & Viewport-Clamped Dialogs:**
  * Made `EffectPickerDialog` (`CustomScrollView` fallback on short heights, `Flexible` title text, compact `insetPadding`), `WriteToSlotDialog` (`SingleChildScrollView`, `Expanded` title), and `PatchLibraryDrawerOrPanel` Import/Export dialogs viewport-clamped and overflow-free.
- [x] **Static Analysis & Targeted Responsive/UI Verification:**
  * `flutter analyze --no-pub`: **0 issues found**.
  * Targeted UI & responsive test suites (`test/features/responsive_layout_test.dart`, `test/widget_test.dart`, `test/drag_drop_editor_test.dart`, `test/hardware_bank_widget_test.dart`, `test/controllers_and_ui_test.dart`, `test/features/ui_accuracy_and_knob_test.dart`): **43 tests passing (100%)** covering `390x844`, `844x390`, `390x420`, `844x240`, `1024x600`, `1440x900`, `720x540`, `500x450`, and Android vs. Linux drag behavior.

---

### 🟢 Milestone 10: Platform Expansion & Multi-Device Support
*Status:* **Completed**
- [x] **Step 1: Native Android USB MIDI Transport (Hardware-Verified):**
  * Implemented Kotlin `android.media.midi.MidiManager` bridge in `MainActivity.kt` with 256-byte outgoing SysEx chunking paired with `AndroidMidiTransport` (`lib/src/transport/android_midi_transport.dart` & `lib/core/midi/android_midi_transport.dart`) providing `_rxBuffer` incoming SysEx stitching and MIDI framing, wired into `lib/main.dart`.
  * Covered by unit tests in `test/core/midi/android_midi_transport_test.dart` (5 tests covering port discovery, connect, send, 989-byte chunked SysEx reassembly, and 2/3-byte PC/CC extraction).
  * Physically tested and verified over USB OTG on a **Fire HD 10** tablet and a **Pixel 10 Pro XL** phone connected to a physical **Zoom MS-60B+**.
- [x] **Step 2: Expanded Zoom MS Plus Catalogs (All 4 Pedals):**
  * Vendored Zoom MS Plus reference JSON/JS definitions into `tool/reference/` (`MS-50G+`, `MS-60B+`, `MS-70CDR+`, `MS-200D+` including `zoom-effect-ids-full-names-ms200dp.js`).
  * Refactored pure-Dart `tool/generate_zoom_catalog.dart` (no `package:flutter` dependency) to ingest both CSV and JSON/JS definitions and generate typed catalogs for **MS-60B+ (98 effects)**, **MS-50G+ (106 effects)**, **MS-70CDR+ (150 effects)**, and **MS-200D+ (224 effects)**.
  * Wired per-pedal resolution into `ZoomMsPlusCatalog`, `EffectCatalogRegistry`, `ZoomMsPlusProtocol`, and `StudioTheme` while keeping MS-60B+ lookups backward-compatible.
  * Expanded `test/zoom_full_catalog_test.dart` to verify exact effect counts (98, 106, 150, 224) and parameter lookup integrity across all four pedals.
- [x] **Step 3: Line 6 Bass POD Pro Hardware Spec Baseline:**
  * Aligned `Line6BassPodProProtocol`, `Line6BassPodProCatalog`, `DeviceFamily.line6BassPodPro` (`totalMemorySlots = 36`, 1A–9D), and mock responders in `lib/main.dart` with verified firmware 1.40 hardware captures: Universal Identity Reply (`00 01 0C` manufacturer / USB Vendor `0x0E41`, `02 00` family code), `0x02` SysEx family byte, 80-byte MSB-first nibble-packed program/edit dumps (169/170 bytes), 16 amp models, 16 cabinet models, Compressor/Noise Gate, 16 effects, and verified hardware CCs.
  * Updated and expanded `test/protocols/line6_bass_pod_pro_protocol_test.dart`, `test/protocol_bank_test.dart`, `test/protocols/catalogs/effect_catalog_test.dart`, and `test/features/patch_editor_controller_test.dart` including decoding the verbatim firmware 1.40 `"Eighties"` edit-buffer capture.
- [x] **Static Analysis & Targeted Verification:**
  * `flutter analyze --no-pub`: **0 issues found**.
  * Targeted test suites (`zoom_full_catalog_test.dart`, `effect_catalog_test.dart`, `line6_bass_pod_pro_protocol_test.dart`, `protocol_bank_test.dart`, `patch_editor_controller_test.dart`, `android_midi_transport_test.dart`, `patch_library_repository_test.dart`, `widget_test.dart`): **84 tests passing (100%)**.

---

### 🟢 Milestone 9: Platform Packaging & Release Distribution
*Status:* **Completed**
- [x] **Linux Packaging & Desktop Integration:**
  * Created standard XDG desktop entry `linux/packaging/signal-chain.desktop` (`Categories=AudioVideo;Audio;Midi;`).
  * Added AppImageHub (`appimage.github.io`) compliant AppStream MetaInfo XML `linux/packaging/io.github.bassmannate.signal_chain.appdata.xml` (`<id>`, `<metadata_license>FSFAP</metadata_license>`, `<project_license>MIT</project_license>`, `<name>`, `<summary>`, `<description>`, `<developer>`, `<url type="homepage">`, `<launchable type="desktop-id">signal-chain.desktop</launchable>`, `<provides>`, `<content_rating>`, and release tags).
  * Designed scalable SVG app icon `linux/packaging/signal-chain.svg` and generated high-resolution 256x256 PNG asset `linux/packaging/signal-chain.png`.
  * Created Debian package generator script `tool/package_linux_deb.sh` bundling the release binary, icons, desktop entry, and declaring `alsa-utils` (`amidi`) and `libgtk-3-0` in `Depends`.
  * Created AppImage packaging script `tool/package_linux_appimage.sh` assembling AppDir layout, copying AppStream XML to `usr/share/metainfo/`, and setting up `AppRun` launcher.
  * Created local user installation script `tool/install_linux_desktop.sh` installing directly into `~/.local/lib/signal-chain`, `~/.local/bin`, and `~/.local/share/applications` without requiring root permissions.
  * Updated `.gitignore` to exclude all Linux/Windows release outputs and staging artifacts (`dist/`, `AppDir/`, `*.AppImage`, `*.deb`, `*.zip`, `*.tar.gz`, `*.tar.xz`, and `tool/appimagetool`).
- [x] **Android USB Host & MIDI Configuration:**
  * Added `android.hardware.usb.host` and `android.software.midi` feature flags in `android/app/src/main/AndroidManifest.xml`.
  * Added `android.hardware.usb.action.USB_DEVICE_ATTACHED` intent filter and metadata.
  * Created `android/app/src/main/res/xml/device_filter.xml` specifying Zoom Corporation (`vendor-id="5766"` / `0x1686`) and Line 6 (`vendor-id="3649"` / `0x0E41`).
- [x] **Windows Packaging Configuration:**
  * Updated `windows/runner/Runner.rc` with official application branding, company name ("Signal Chain Contributors"), and description.
  * Created PowerShell distribution script `tool/package_windows_zip.ps1` for assembling clean portable release ZIP archives.
- [x] **Automated GitHub Release Workflow (`.github/workflows/release.yml`):**
  * Configured `v*.*.*` tag-triggered CI/CD workflow with `verify` (`flutter analyze --no-pub` & `flutter test --no-pub`), `build-linux` (`./tool/package_linux_deb.sh` + `./tool/package_linux_appimage.sh` outputting `dist/*.deb` & `dist/*.AppImage`), `build-android` (`app-release.apk`), `build-windows` (`tool/package_windows_zip.ps1` outputting `dist/*.zip`), `SHA256SUMS.txt` generation, and `softprops/action-gh-release@v3`.
- [x] **Targeted Unit Test Suites (100% passing):**
  * `test/packaging_config_test.dart` (5 tests verifying desktop launcher, AppStream MetaInfo XML fields, executable script permissions, Android features, USB filter VIDs, and Windows PowerShell packaging script).
  * Full project test suite: 219 tests passing across all suites (`flutter test --no-pub`).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8.11: Linux ALSA Warm-Restart Reliability & Handshake Pacing
*Status:* **Completed**
- [x] **Linux ALSA RawMIDI Orphaned Process Cleanup & Port Drain (`LinuxAlsaMidiTransport`):**
  * Discovered that restarting the application while the Zoom MS-60B+ remains plugged in could leave orphaned `amidi -p <port> -d` processes holding the ALSA RawMIDI node, splitting or stealing incoming SysEx dumps across app runs.
  * Added proactive process cleanup before binding: terminates any stale `amidi` listeners on the target port via `pkill -9 -f "amidi.*$portId"` when running in production Linux environments.
  * Added port drain window: upon starting the listener process, discards and clears any stale or partial bytes queued in the ALSA kernel buffer for 50ms (0ms in automated tests) before returning to caller, ensuring the message reassembly buffers are 100% clean.
  * Enhanced process termination in `disconnect()`: sends `SIGTERM`, waits up to 150ms, and escalates to `SIGKILL` if the process remains stubborn.
- [x] **Warm Handshake Pacing & Sequenced Patch Pull (`DeviceConnectionController`):**
  * Prevented packet flooding on pedal reconnect: added a 25ms inter-command pacing delay (0ms under `FLUTTER_TEST`) between initialization messages (`0x53` -> `0x50` -> `0x33`) and before `64 13`.
  * Sequenced initial current patch request (`buildRequestCurrentPatchMessage`): awaits the incoming `64 12 01` patch dump via `sendSysExAndWait` with an 800ms timeout (50ms under `FLUTTER_TEST`).
  * Added single retry: if the initial attempt times out, retries once before proceeding, preventing missed edit buffer loads during warm pedal reconnects.
  * Eliminated collision with background bank sync: `syncDeviceBank()` is strictly deferred until the current patch request completes or finishes its retry.
- [x] **Bank Slot Request Retry Guard (`syncDeviceBank`):**
  * Wrapped individual memory slot requests (`0x46`) in a retry loop: if a slot read times out, retries once before marking the slot descriptor loaded but empty.
  * Added inter-slot pacing delay in the sync loop to avoid overflowing the pedal's internal flash memory controller during bulk 100-slot scans.
- [x] **Unit & Widget Test Suites (100% passing):**
  * `test/core/midi/linux_alsa_midi_transport_test.dart` (13 tests, +3 tests for `pkill` cleanup, port drain discard, and `SIGKILL` escalation).
  * `test/features/device_connection_controller_test.dart` (3 tests, newly created suite verifying pacing, `64 13` timeout retry, `0x46` timeout retry, and sequential ordering).
  * `test/hardware_bank_widget_test.dart` (12 tests).
  * Full project test suite: 214 tests passing across all suites (`flutter test --no-pub`).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8.10: Zoom MS Plus Initial Active Slot Identification (Opcode 0x33 & Deterministic Bank Signature Fallback)
*Status:* **Completed**
- [x] **Protocol Forensics & Root Cause Discovery:**
  * Analyzed initial connection SysEx sequence vs `ZoomDevice.js`.
  * Identified that `64 12 01` (PTCF edit buffer dump) contains no memory slot number in its header, causing `Patch.programNumber` to initialize as `null`.
  * As a consequence, the Hardware Bank sidebar displayed no active slot highlight on connect, and "Write to Slot..." defaulted to slot `001` (index 0).
- [x] **Opcode `0x33` Hardware Query (`ZoomMsPlusProtocol` & `DeviceProtocol`):**
  * Added `buildCurrentSlotRequest()` returning `F0 52 00 6E 33 F7` (`cmdRequestBankAndProgram = 0x33`).
  * Appended `0x33` to `ZoomMsPlusProtocol.buildInitSequence()` (`0x53` -> `0x50` -> `0x33`) to request the selected bank and slot immediately upon connection.
  * Successfully routes both `64 26 00 00` SysEx and Bank Select CC (`B0 00` / `B0 20`) + Program Change (`C0`) to `setActiveHardwareSlotIndex`.
- [x] **Deterministic Bank Signature Fallback Heuristic (`Patch.isSignatureMatch`):**
  * Added `Patch.isSignatureMatch(target, candidate, {bool matchParameters = true})` to robustly match presets by name, slot count, effect IDs, bypass states, and parameter values.
  * As `0x45` memory slots stream in during `syncDeviceBank`, if `activeHardwareSlotIndex` is not yet set, the engine evaluates incoming bank slots against the initial edit buffer and locks `activeHardwareSlotIndex` onto the matching slot.
  * Symmetrically checks already-synced slots if the `64 12 01` dump arrives after bank sync has commenced.
- [x] **Controller & UI Layer Pre-Selection:**
  * Added `activeHardwareSlotIndex` getter and `setActiveHardwareSlotIndex(slotIndex)` in `DeviceConnectionController`.
  * Added `setHardwareSlotIndex(slotIndex)` in `PatchEditorController` to associate the active preset with its hardware slot without marking it dirty.
  * In `applyExternalHardwareUpdate`, preserved known slot index during unsolicited edit buffer dumps (`64 12 01`) so `programNumber` is never reset to `null`.
  * `HardwareBankBrowserWidget` inspects `patch.programNumber ?? activeHardwareSlotIndex` and immediately highlights the slot as `ACTIVE IN EDITOR`.
  * `WriteToSlotDialog` pre-selects `activeHardwareSlotIndex` by default in the slot dropdown.
- [x] **Unit & Widget Test Suites (100% passing):**
  * `test/protocols/zoom_ms_plus_protocol_test.dart` (31 tests, +7 tests for `buildCurrentSlotRequest` and `Patch.isSignatureMatch`).
  * `test/features/patch_editor_controller_test.dart` (15 tests, +3 tests for `setHardwareSlotIndex`, unassigned slot assignment, and slot preservation).
  * `test/hardware_bank_widget_test.dart` (12 tests, +2 tests for hardware slot notification and deterministic bank signature fallback pre-selection).
  * Full project test suite: 208 tests passing across all suites (`flutter test --no-pub`).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8.9: Zoom MS Plus Live Structural Chain Sync (Reorder, Swap, Add, Remove & Dynamic PRM2 Bitmasks)
*Status:* **Completed**
- [x] **Protocol Forensics & Root Cause Discovery (`zoom-explorer`):**
  * Discovered that opcode `64 12 01` (PTCF edit buffer dump) is strictly device-to-host; transmitting it to the pedal in live edit mode is ignored by DSP/display and triggers an echo loopback dump that reverts local app state.
  * Identified that live structural edits on Zoom MS Plus (`0x6E`) operate exclusively via parameter opcodes (`64 20 00`):
    - `paramNumber = 1`: Sets 32-bit DSP algorithm ID packed as 5 7-bit bytes (`buildEffectTypeMessage`), supporting `effectId = 0` to empty/clear slots.
    - `paramNumber = 0`: Bypass state (`00` bypassed, `01` active).
    - `paramNumber = paramIndex + 2`: Knob parameter values.
    - `64 20 00 64 01 <slotIndex>`: Focuses physical LCD cursor on active slot.
- [x] **Protocol Layer Implementation (`ZoomMsPlusProtocol` & `DeviceProtocol`):**
  * Added `buildEffectTypeMessage(int slotIndex, int effectId)` implementing `64 20 00 <slotIndex> 01 <5 bytes 7-bit dspId>`.
  * Added `buildSlotSyncSequence(int slotIndex, EffectSlot slot)` sequencing: Effect ID, Bypass, mapped parameters, and trailing hidden parameters (`rawTrailingValues`).
  * In `encodePtcf`, added dynamic calculation for PRM2 bitmasks: Preamp (`byte 20`, `(preampBits & 0x3F) << 1`), BPM tempo-sync (`bytes 21-22`), Line Selector (`bytes 22-23`), and cursor slot (`byte 10`).
- [x] **Controller Layer & State Protection (`PatchEditorController`):**
  * Added `swapEffectSlots(int indexA, int indexB)` for card-on-card drops and nudge buttons.
  * Corrected `reorderEffectSlots(int fromIndex, int toIndex)` index adjustment (`fromIndex < toIndex ? toIndex - 1 : toIndex`).
  * Replaced `64 12 01` dump in `_syncStructureToDevice` with live `buildSlotSyncSequence` bursts and `buildSlotFocusMessage`.
  * Added `_isSyncingStructure` lock and dirty-state guards in `applyExternalHardwareUpdate` to prevent incoming ACK echoes or unsolicited patch dumps from overwriting user edits during structural modifications.
- [x] **UI Layer Alignment (`SignalChainStripWidget`):**
  * Routed card-on-card drops and nudge buttons (`<` / `>`) to `swapEffectSlots`.
  * Routed inter-slot insertion zones to `reorderEffectSlots`.
  * Fixed `onWillAcceptWithDetails` boundary condition in `_buildInsertionZone` to permit adjacent moves across RTL boundaries.
- [x] **Unit & Widget Test Suites (100% passing):**
  * `test/protocols/zoom_ms_plus_protocol_test.dart` (24 tests, +3 tests for `buildEffectTypeMessage`, `buildSlotSyncSequence`, and dynamic `PRM2` bitmasks).
  * `test/drag_drop_editor_test.dart` (10 tests, updated for `swapEffectSlots` and `reorderEffectSlots` live `64 20 00` dispatch).
  * Full test suite: 196 tests passing across all suites (`flutter test --no-pub`).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8.8: Zoom MS Plus Hardware Slot Write Protocol Alignment & ACK Verification
*Status:* **Completed**
- [x] **Deep Protocol Forensics vs `zoom-explorer`:**
  * Analyzed `ZoomDevice.js`, `ZoomPatch.js`, `tools.js`, and `miditools.js` against ALSA RawMIDI binary disassembly of `/usr/bin/amidi`.
  * Identified the requirement of fixed 848-byte (`0x0350`) unpacked PTCF slot payload buffer length on Zoom MS Plus hardware.
  * Verified opcode `0x45 0x00 0x00` writes directly without requiring PC Mode `0x52` or parameter edit enable/disable cycles.
  * Confirmed Zoom hardware Success ACK packet: `F0 52 00 <familyIdByte> 00 00 F7`.
- [x] **Binary Framing & Checksum Fixes (`ZoomMsPlusProtocol`):**
  * Updated `buildSavePatchToSlotMessage` to zero-pad unpacked PTCF data to `msPlusPtcfSlotLength` (848 bytes).
  * Set length fields strictly to LSB `0x50`, MSB `0x06` ($848$).
  * Packed all 848 bytes into 970 bytes of 7-bit MIDI data.
  * Computed inverted CRC32 ($\sim\text{CRC32}$) across the complete 848-byte padded buffer.
  * Eliminated the trailing `0x00` padding byte before `0xF7` (message strictly ends after 5 CRC bytes, yielding exactly 989 SysEx bytes).
  * Applied the same length padding, PRM2 volume ($100$), edit slot bit pattern, and CRC framing to edit buffer updates (`0x64 0x12 0x01`).
  * Implemented `isSuccessAck(MidiMessage message)` in `DeviceProtocol` and `ZoomMsPlusProtocol`.
- [x] **Bidirectional ACK Verification & Dialog Guardrails:**
  * Added `MidiTransport.sendRequest` convenience method.
  * Updated `PatchEditorController.savePatchToDeviceSlot` to await hardware ACK response (`F0 52 00 6E 00 00 F7`) with a 2500ms timeout when communicating with physical devices, maintaining seamless mock compatibility for `MockMidiTransport`.
  * Guarded `WriteToSlotDialog` to keep the dialog open on timeout/rejection and display the error message rather than falsely showing a success snackbar.
- [x] **Unit & Widget Test Suites (100% passing):**
  * `test/protocols/zoom_ms_plus_protocol_test.dart` (21 tests).
  * `test/protocol_bank_test.dart` (13 tests).
  * `test/features/patch_editor_controller_test.dart` (12 tests).
  * `test/hardware_bank_widget_test.dart` (9 tests).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

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

### 🟢 Milestone 6: Full Zoom MS-60B+ / MS Plus Effect Catalog Extraction & Signal Chain Slot Workflows
*Status:* **Completed**
- [x] **Full Zoom MS-60B+ / MS Plus Catalog Extraction (`lib/catalog/`, `tool/`):**
  * Located reference `zoom-effect-mappings-ms60bp.json` and created project reference at `tool/reference/zoom-effect-mappings-ms60bp.json`.
  * Created deterministic, pure-Dart tool script `tool/generate_zoom_catalog.dart` parsing the complete 98-effect MS-60B+ mapping and generating `lib/catalog/zoom_ms_plus_catalog_data.dart`.
  * Extracted all 98 effects across 11 categories: Dynamics, Filter / EQ, Drive / Distortion, Preamp, Amp Model, Modulation, Pitch / Octave, Bass Synth, Special / SFX, Delay, Reverb.
  * Mapped all parameter descriptors with exact min, max, default values, step, and discrete non-numeric value labels (e.g., Attack SLOW/FAST, Ultra, MID-FREQ 32-band steps).
  * Updated `ZoomMsPlusCatalog` in `lib/protocols/catalogs/zoom_ms_plus_catalog.dart` with backward-compatible lookup APIs (`getById`, `getByIntId`, `getByCategory`, `categories`, `search`).
  * Updated `EffectDefinition` with `intEffectId` helper and `dspLoad` metadata support.
- [x] **Signal Chain Slot Operations in `PatchEditorController` (`lib/features/editor/`):**
  * `addEffectSlot({int? index, required dynamic effectId})`: Adds slot with default parameters from `EffectCatalogRegistry`, respecting device max slot limits (e.g. 6 slots on Zoom MS Plus).
  * `removeEffectSlot(int slotIndex)`: Safely removes an effect slot, re-indexes remaining slots, and clamps `selectedSlotIndex`.
  * `moveEffectSlot(int oldIndex, int newIndex)`: Reorders slots in the signal chain and maintains selected slot tracking.
  * `changeSlotEffect(int slotIndex, dynamic newEffectId)`: Hot-swaps slot algorithm by integer DSP ID or hex string and re-populates default parameter descriptors.
  * Live hardware synchronization: Automatic edit buffer dump dispatch (`protocol.encodePatch`) to connected devices on chain structure modifications.
- [x] **Studio UI Enhancements & Modal Effect Picker (`lib/features/editor/`):**
  * `SignalChainStripWidget`: Added Move Left and Move Right buttons, Swap Effect button, Remove Slot action, and "+ Add Effect" card with max slot indicators.
  * `EffectPickerDialog` (`lib/features/editor/effect_picker_dialog.dart`): Modal dialog with live text search, category filter chips (All + 11 categories), parameter count and hex ID badges, and single-click selection.
  * `SlotInspectorWidget`: Added "Browse Effect Catalog" button opening `EffectPickerDialog` alongside existing model dropdown.
- [x] **Comprehensive Test Suites (100% passing, 124 total tests):**
  * `test/zoom_full_catalog_test.dart` (7 tests covering full 98 effects, 11 categories, parameter integrity, search, and family registration).
  * `test/controllers_and_ui_test.dart` (6 tests covering slot addition, removal, reordering, swapping, and widget interactions with `EffectPickerDialog`).
- [x] Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

---

### 🟢 Milestone 7: Hardware Patch Memory Bank Protocol, Patch Metadata Controls & Hardware Bank Browser UI
*Status:* **Completed**
- [x] **Part 1: Hardware Patch Memory Bank Protocol (0–99 Slots):**
  * `ZoomMsPlusProtocol`: Memory slot read request (`46 00 00 <bank_lsb> <bank_msb> <prog_lsb> <prog_msb>`) and save dump message (`45 00 00` with bank/prog offset, length, 7-bit packed PTCF, CRC, 00, F7).
  * `Line6BassPodProProtocol`: Program dump request (`0x01`) and program memory dump write.
  * `BankSlotDescriptor` model representing remote hardware patch indices, empty/loaded flags, bank/program numbers (`1-1` to `10-10`), and formatted slot labels (`#00 (1-1)`).
  * `DeviceConnectionController.syncDeviceBank`: Non-blocking, incremental asynchronous fetch of all 100 persistent slots with live percentage progress, cancellation support, and individual timeout resilience.
  * Direct memory slot loading (`loadPatchFromDeviceSlot`) and hardware slot write SysEx dispatch (`savePatchToDeviceSlot` via `sendSysEx` / `send`) in `PatchEditorController`.
  * Added `MidiTransport.sendSysEx(MidiMessage message)` convenience contract across all transport implementations.
- [x] **Part 2: Patch Metadata Controls (Name & Tempo):**
  * `PatchEditorController.updatePatchName(String newName)`: Enforces hardware-specific character limits (10 chars for Zoom MS Plus pedals, 16 for Line 6 Bass Pod Pro), converts invalid/unprintable ASCII characters to spaces, marks patch dirty, and dispatches real-time update to connected device.
  * `PatchEditorController.updatePatchTempo(int bpm)`: Clamps tempo to 40–250 BPM, encodes into Zoom PRM2 subchunk, marks patch dirty, and dispatches real-time sync.
  * `PatchMetadataHeaderWidget`: Real-time name input `TextField`, dirty status badge (`* UNSAVED`), tempo BPM display, increment/decrement buttons (`-1`/`+1 BPM`), tempo slider, and "Write to Slot..." button.
  * `WriteToSlotDialog`: Dedicated modal dialog for selecting destination memory slot (0–99) with overwrite confirmation.
- [x] **Part 3: Hardware Bank Browser UI:**
  * `HardwareBankBrowserWidget`: Dedicated scrollable 100-slot browser displaying slot numbers, names, active editor badges, search/filter bar, one-click load into editor buffer, and slot overwrite action.
  * `PatchLibraryDrawerOrPanel`: Segmented tab toggle switching between `Local Presets` and `Hardware Bank` with zero overflow across desktop and mobile screens.
  * Simulated memory slot responders in `MockMidiTransport` for Zoom MS-60B+ and Line 6 Bass Pod Pro.
- [x] **Part 4: Targeted Unit & Widget Tests + Documentation:**
  * `test/protocol_bank_test.dart` (7 tests verifying SysEx payloads for reading/writing slots 0–99 on Zoom and Line 6, round-trip encoding/decoding, and `BankSlotDescriptor`).
  * `test/patch_metadata_test.dart` (5 tests verifying name length enforcement, character sanitization, tempo boundary clamping 40–250 BPM, and PRM2 persistence).
  * `test/hardware_bank_widget_test.dart` (7 tests verifying `PatchMetadataHeaderWidget`, `HardwareBankBrowserWidget`, slot syncing, loading, and tab switching).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).
  * Comprehensive documentation updates in `PROJECT_CONTEXT.md`, `SPEC.md`, and `STATUS.md`.

---

### 🟢 Milestone 7.5: Live Bidirectional Hardware Sync, Patch Name Extraction, MIDI Auto-Select & Drag-and-Drop Effect Palette
*Status:* **Completed**
- [x] **MIDI Port Auto-Selection (`DeviceConnectionController`):**
  * Auto-scans discovered MIDI ports for known hardware patterns (`ZOOM`, `MS Plus`, `MS-60B`, `MS-50G`, `MS-70CDR`, `MS-200D`, `Bass POD`, `Line 6`).
  * If physical hardware is detected and not currently connected, auto-selects `DeviceFamily`, establishes connection, issues `buildRequestCurrentPatchMessage()`, and triggers background bank name sync.
  * Preserves manual dropdown port selection and simulation fallback in studio UI.
- [x] **Bidirectional Live Hardware-to-App Sync Without Feedback Loops:**
  * Non-blocking raw MIDI streaming with `AlsaRawMidiTransport` (`LinuxAlsaMidiTransport`) reassembling SysEx and standard channel messages (Program Change `0xC0..0xCF`, Control Change `0xB0..0xBF`).
  * `ZoomMsPlusProtocol` handles incoming current patch dumps (`0x28` / `0x64 0x12 0x01` / `0x45 0x00 0x00`), real-time parameter edits (`0x64 0x20` and legacy `0x31`), and Program Change events.
  * Direct unsolicited event routing from `DeviceConnectionController` into `PatchEditorController.applyExternalHardwareUpdate(...)`.
  * Guarantees local UI updates immediately without echoing messages back over MIDI, preventing feedback loops.
- [x] **Accurate Hardware Patch Name Extraction (`ZoomMsPlusProtocol`):**
  * `_cleanName` strips trailing null bytes (`0x00`) and whitespace while preserving printable ASCII characters and internal spaces.
  * Reliable `NAME` subchunk extraction in PTCF parser with fallback marker scanning for malformed or non-contiguous chunks.
  * Decoded names immediately populate `BankSlotDescriptor` in `HardwareBankBrowserWidget` and `PatchMetadataHeaderWidget`.
- [x] **Drag-and-Drop Signal Chain & Effect Bank Palette:**
  * `EffectBankPaletteWidget`: Studio shelf/panel with category filter chips (`All`, `Dynamics`, `Filter`, `Drive`, `Amp`, `Cabinet`, `Modulation`, `SFX`, `Delay`, `Reverb`), live search box, and `Draggable<EffectDragPayload>` cards with click-to-add accessibility.
  * `SignalChainStripWidget`: Slot cards wrapped in `Draggable<SlotReorderPayload>` and `DragTarget<Object>`.
  * Dragging slot A onto slot B calls `patchEditorController.reorderEffectSlots(fromIndex, toIndex)` and synchronizes to hardware.
  * Dragging from Effect Palette onto a slot swaps algorithm (`changeSlotEffect`) and syncs to hardware; dragging onto "+ Add Slot" card inserts algorithm (`addEffectSlot`) and syncs to hardware.
  * Visual hover feedback (`onWillAcceptWithDetails`) with glowing accent borders.
- [x] **Targeted Unit & Widget Test Suites (100% passing):**
  * `test/protocol_bank_test.dart` (10 tests, +3 tests verifying PTCF trailing null byte stripping, Current Patch dumps `0x28`/`0x64 0x12`, and parameter edits `0x31`/`0x64 0x20`).
  * `test/drag_drop_editor_test.dart` (8 tests verifying port auto-selection heuristics, unsolicited updates without echo loop, effect palette rendering, reordering, and slot drops).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8: Zoom MS-60B+ Live Hardware Testing Protocol & UX Bug Fixes
*Status:* **Completed**
- [x] **Bug 1: USB Lock Screen Icon Handshake & Bidirectional Control Fix:**
  * Updated `ZoomMsPlusProtocol.buildInitSequence()` to transmit `0x53` (`cmdPcModeDisable`) first to clear any USB lock screen PC Mode, followed by `0x50` (`cmdParameterEditEnable`) to enable live bidirectional parameter editing and physical pedal control.
  * Completely removed `0x52` (`cmdPcModeEnable`) and `0x51` from the initialization sequence.
  * Verified ALSA transport correctly receives knob turns, effect bypasses, and patch changes without echoing back.
- [x] **Bug 2: USB Hot-Plug Auto-Connect & Bank Sync Isolation:**
  * Added lightweight periodic hot-plug polling (every 2 seconds, disabled in `FLUTTER_TEST`) in `DeviceConnectionController` that auto-connects upon pedal plug-in and cleanly disconnects when unplugged.
  * Isolated memory slot dumps (`0x45 0x00 0x00` / `isSlotPatchDump`) from current edit buffer dumps (`0x64 0x12 0x01` / `0x28` / `isCurrentPatchDump`).
  * Incoming `0x45` responses strictly update `bankSlots[slotIndex]` using `extractSlotIndex(m)` and never overwrite or cycle the active editor patch buffer.
- [x] **Bug 3: Single-Click Responsive Hardware Bank Slot Selection:**
  * Tapping a slot in `HardwareBankBrowserWidget` immediately loads the pre-cached patch from `bankSlots` on single click with zero lag and without sending slot-write commands (`0x45`).
  * If uncached, queries hardware using targeted `sendSysExAndWait` matcher validating slot index.
  * Transmits standard Zoom slot switch messages (Bank Select CC 0, CC 32, and Program Change) to update the pedal's active slot.
- [x] **Bug 4: Inter-Slot Signal Chain Drag-and-Drop Insertion:**
  * Added `insertEffectSlotAt(int index, EffectCatalogEntry entry)` to `PatchEditorController`.
  * Implemented dedicated `DragTarget<Object>` **insertion zones** between every slot in `SignalChainStripWidget` (before slot 0, between `i` and `i+1`, and after the last slot).
  * Hovering an effect or slot reorder over an insertion zone displays an illuminated vertical insertion bar/spacer with glow styling.
  * Dropping an effect from the palette inserts it at that exact chain index; dropping a slot moves it to that exact index.
- [x] **Targeted Unit & Widget Test Suites (100% passing):**
  * `test/protocol_bank_test.dart` (13 tests).
  * `test/drag_drop_editor_test.dart` (10 tests).
  * `test/hardware_bank_widget_test.dart` (9 tests).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8.5: Zoom MS-60B+ Hardware Patch Switch Feedback Loop Elimination & Bidirectional Knob/Bypass Sync
*Status:* **Completed**
- [x] **Bug A: Hardware Patch Switch Flopping & Echo Loop Elimination:**
  * Added Bank Select CC tracking (`CC 0` MSB, `CC 32` LSB) in `DeviceConnectionController._handleIncomingHardwareEvent` to calculate the true slot index `(bank * 10) + prog` on incoming Program Change.
  * Added parsing for Zoom MS Plus SysEx `bankAndProgramNumberV2` (`F0 52 00 6E 64 26 00 00 <bank> <prog> F7`).
  * Updated `PatchEditorController.loadPatchFromDeviceSlot` with `bool notifyHardware = true` parameter.
  * When patch change originates from the physical pedal, `applyExternalHardwareUpdate(programNumber: slot)` passes `notifyHardware: false`, strictly loading the cached patch without transmitting slot-select or write commands back to the pedal, breaking the feedback loop.
- [x] **Bug B: Bidirectional Live Knob & Effect Bypass Sync (App <-> Pedal):**
  * Discovered and aligned with reference wire protocol semantics: Parameter 0 = Bypass (1 = ON, 0 = OFF), Parameter 1 = Effect ID, Parameter 2+ = Knobs (knob index = `paramNumber - 2`).
  * App to Pedal (Bypass): Implemented `buildSlotBypassMessage` in `DeviceProtocol` / `ZoomMsPlusProtocol` (15-byte SysEx: `F0 52 00 6E 64 20 00 <slot> 00 <val> ... F7`) and wired into `PatchEditorController.toggleSlotEnabled`.
  * App to Pedal (Knobs): Updated `buildParameterEditMessage` to encode `paramIndex + 2` in byte 8 so knob parameters map to pedal controls accurately.
  * Pedal to App (Bypass): Implemented `isSlotBypass` and `parseSlotBypass` in `ZoomMsPlusProtocol` to detect footswitch presses on physical pedal and toggle `slot.isEnabled` in UI under `_isHandlingIncoming = true` with zero echo.
  * Pedal to App (Knobs): Updated `parseParameterEdit` to map incoming `paramNumber >= 2` back to `paramIndex = paramNumber - 2`, and updated `isParameterEdit` to ignore ACK frames (`data[6] == 0x01`).
- [x] **Post-Sync Guardrail:**
  * Re-asserts `0x50` (`cmdParameterEditEnable`) at the completion of `syncDeviceBank()` to guarantee live SysEx streaming continues uninterrupted after slot fetching.

---

### 🟢 Milestone 8.6: Physical Footswitch Bypass Real-Time Fix & Bidirectional Effect Slot Focus Sync
*Status:* **Completed**
- [x] **Bug 1: Physical Footswitch Bypass Real-Time Unbuffering (`LinuxAlsaMidiTransport`):**
  * Discovered root cause of footswitch bypass inversion / 1-message lag: `feedHexStream` split on trailing whitespace, stranding raw `F7` terminating bytes emitted by `amidi -d` until the *subsequent* hardware action arrived.
  * Rewrote `feedHexStream` tokenizer to immediately consume all complete 2-hex-digit tokens without waiting for trailing whitespace or newlines, only buffering incomplete 1-character tails at stream boundaries.
  * Eliminated redundant secondary MIDI transport subscription in `PatchEditorController` to prevent duplicate message handling.
- [x] **Bug 2: Bidirectional Effect Slot Focus Synchronization (Pedal <-> App):**
  * Discovered Zoom MS Plus slot focus opcode in reference implementation: `F0 52 00 6E 64 20 00 64 01 <slotIndex> 00 00 00 00 F7`.
  * Implemented `buildSlotFocusMessage`, `isSlotFocusChange`, and `parseSlotFocusChange` in `DeviceProtocol` and `ZoomMsPlusProtocol`.
  * Guarded `isSlotBypass` and `isParameterEdit` to strictly match effect slots (`slotIndex < 6`), rejecting device-level `0x64` opcodes (such as slot focus `64 01`, tempo `64 02`, and autosave `64 0F`).
  * Pedal to App: Physical Left/Right cursor button presses on pedal update `PatchEditorController.selectedSlotIndex` and trigger UI updates in real time.
  * Pedal to App: Footswitch bypass toggles and knob tweaks automatically focus the targeted slot index in the UI inspector.
  * App to Pedal: Clicking a slot card in `SignalChainStripWidget` transmits `buildSlotFocusMessage`, causing the physical pedal screen to follow the app's selected slot.
- [x] **Targeted Unit & Widget Test Suites (100% passing):**
  * `test/core/midi/linux_alsa_midi_transport_test.dart` (10 tests, +2 tests verifying unbuffered `F7` dispatch without trailing whitespace).
  * `test/protocols/zoom_ms_plus_protocol_test.dart` (19 tests, +3 tests for `buildSlotFocusMessage`, `isSlotFocusChange`, and `0x64` opcode filtering).
  * `test/features/patch_editor_controller_test.dart` (10 tests, +3 tests for focus transmission, incoming focus navigation, and incoming bypass focus).
  * `test/protocol_bank_test.dart` (13 tests).
  * `test/drag_drop_editor_test.dart` (10 tests).
  * `test/hardware_bank_widget_test.dart` (9 tests).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 8.7: Right-to-Left Pedalboard Signal Chain, Rotary Knob Inspector & Parameter Accuracy
*Status:* **Completed**
- [x] **Objective 1: Right-to-Left Pedalboard Signal Chain Order (`SignalChainStripWidget`):**
  * Reordered horizontal signal chain layout to match physical pedalboard flow: `[OUT] <-- [Add Slot] <-- [Slot N] ... <-- [Slot 1] <-- [IN]`.
  * Added dedicated `[IN]` badge (right) and `[OUT]` badge (left) with `Icons.arrow_back` / `←` leftward flow arrows.
  * Realigned all inter-slot `DragTarget` insertion zones (`Key('insertion_zone_$insertIndex')`) in exact RTL order.
  * Updated reorder nudge buttons: Move Left (`Icons.arrow_back`) shifts towards output (`index + 1`); Move Right (`Icons.arrow_forward`) shifts towards input (`index - 1`).
  * Subheader displays `SIGNAL CHAIN (X SLOTS) • OUT ← IN`.
- [x] **Objective 2: Unmapped Parameter Elimination & Lossless PTCF Preservation:**
  * Updated `EffectSlot` with `final List<double>? rawTrailingValues;` for trailing bytes.
  * `ZoomMsPlusProtocol.decodePtcf`: When effect catalog definition is present, only exposes valid mapped parameters in `EffectSlot.parameters`, cleanly stashing trailing EDTB parameter bytes in `rawTrailingValues`.
  * `ZoomMsPlusProtocol.encodePtcf`: Symmetrically pulls from `parameters[p]` if `p < parameters.length`, else from `rawTrailingValues[p - parameters.length]`, guaranteeing 100% binary round-trip fidelity.
- [x] **Objective 3: Accurate Parameter Ranges, Display Offsets & Value Labels:**
  * Added `displayOffset` and `valueLabels` to `ParameterDescriptor` along with `formatValue(num rawValue)` handling discrete label lookups, display offsets, and decimal formatting.
  * Updated `ParameterValue.displayValue` to delegate directly to `descriptor.formatValue(currentValue)`.
  * Enhanced `tool/generate_zoom_catalog.dart` to auto-detect integer offsets, convert discrete label tables, and clean up HTML musical note entities (`&#119138;` -> `𝅚`, `&#119137;` -> `𝅙`, `&#119136;` -> `𝅘`, `&#119135;` -> `♩`, `&#119134;` -> `𝅗`).
  * Regenerated all 98 effects in `lib/catalog/zoom_ms_plus_catalog_data.dart`.
- [x] **Objective 4: Studio Rotary Knob Component & Adaptive Inspector:**
  * Created `RotaryKnobWidget`: Custom-painted dark studio dial (`_KnobPainter`) sweeping 270° (135° to 405°).
  * Implemented bidirectional mouse scroll wheel adjustment via `PointerScrollEvent` (`< 0` increments, `> 0` decrements, Shift for coarse adjust).
  * Implemented vertical touch/mouse drag gesture adjustment.
  * Implemented double-tap to reset to default parameter value.
  * Implemented discrete parameter selection via `PopupMenuButton`.
  * Converted `SlotInspectorWidget` to render an adaptive `Wrap` grid of rotary knobs with a collapsible hidden parameters toggle (`_showHidden`).
- [x] **Targeted Unit & Widget Test Suites (100% passing):**
  * `test/features/ui_accuracy_and_knob_test.dart` (5 tests verifying RTL layout, unmapped parameter omission, PTCF round-trip preservation, and rotary knob gestures).
  * `test/widget_test.dart` (3 tests).
  * `test/controllers_and_ui_test.dart` (6 tests).
  * `test/drag_drop_editor_test.dart` (10 tests).
  * `test/hardware_bank_widget_test.dart` (9 tests).
  * `test/protocols/zoom_ms_plus_protocol_test.dart` (19 tests).
  * `test/protocol_bank_test.dart` (13 tests).
  * `test/zoom_full_catalog_test.dart` (7 tests).
  * Static analysis: Zero errors, zero warnings (`flutter analyze --no-pub`).

---

### 🟢 Milestone 9: Platform Packaging & Release Distribution
*Status:* **Completed (Documented above in Milestone Roadmap)**

---

## 2. Workspace Audit Summary

| Item | Status | Notes |
| :--- | :--- | :--- |
| **Workspace Repository** | Clean Flutter Project | Flutter 3.47.9 / Dart 3.13.7 baseline |
| **Legacy Source Code** | Audited | Reference mappings in `tool/reference/zoom-effect-mappings-ms60bp.json` |
| **Directory Scaffolding** | Complete | Clean architecture layers maintained |
| **Core MIDI Transport** | Complete | `MidiTransport`, `MidiMessage`, `MockMidiTransport`, `LinuxAlsaMidiTransport`, `AndroidMidiTransport`, `CompositeMidiTransport` |
| **Domain Models** | Complete | `DeviceFamily`, `ParameterDescriptor`, `EffectSlot`, `Patch`, `PatchDiff`, `BankSlotDescriptor` |
| **SysEx & Protocol Engine** | Complete | `SysexCodec`, `ZoomMsPlusProtocol` (Memory slots 0–99 read/write), `Line6BassPodProProtocol` (`0x02` family byte, 80-byte MSB-first nibbles, 36 slots) |
| **Effect Catalogs** | Complete (578 Zoom + 50 Line 6) | `EffectDefinition`, `EffectCatalogRegistry`, `ZoomMsPlusCatalog` (MS-60B+ 98, MS-50G+ 106, MS-70CDR+ 150, MS-200D+ 224), `Line6BassPodProCatalog` |
| **Catalog Generator** | Complete | Deterministic pure-Dart script `tool/generate_zoom_catalog.dart` |
| **Persistence Repositories** | Complete | `PatchLibraryRepository`, `InMemoryPatchLibraryRepository`, `FileSystemPatchLibraryRepository`, `AppPreferencesRepository` |
| **State Controllers** | Complete | `DeviceConnectionController` (Bank sync), `PatchEditorController` (Undo/Redo, A/B Compare, Name/Tempo/Slots), `PatchLibraryController` |
| **Studio UI & Widgets** | Complete | `StudioTheme`, `ConnectionBarWidget`, `SignalChainStripWidget` (RTL order), `RotaryKnobWidget`, `SlotInspectorWidget`, `PatchDiffDialog`, `HardwareBankBrowserWidget`, `WriteToSlotDialog`, `PatchLibraryDrawerOrPanel` |
| **Static Analysis** | Passing (0 issues) | Verified via `flutter analyze --no-pub` |
| **Unit & Widget Tests** | 283 Passing (100%) | 269 prior + 14 Milestone 14 tests (`patch_diff_test.dart`, `patch_edit_history_test.dart`, `patch_editor_controller_test.dart`, `undo_compare_diff_ui_test.dart`) |

