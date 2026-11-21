# Signal Chain (`signal_chain_flutter`)

Cross-platform patch editor and preset librarian for **Zoom MS Plus** series pedals, **Zoom Four** series pedals (**B1X FOUR / B1 FOUR**), and **Line 6 Bass POD Pro** rackmount processors, rewritten in pure Dart/Flutter from the original web-based [Signal Chain](https://github.com/bassmannate/signal-chain) project.

Repository: <https://github.com/bassmannate/signal_chain_flutter>

Built with a **100% pure Dart/Flutter foundation** and **zero external pub dependencies** (no third-party `pub.dev` packages required).

---

## Supported Hardware & Verification Status

| Device | Protocol / Family | Effect Catalog | Verification Status |
| :--- | :--- | :--- | :--- |
| **Zoom MS-60B+** | Zoom MS Plus (`0x6E`) | 98 effects | **Fully hardware-verified** on Linux ALSA MIDI and Android USB OTG (Fire HD 10 & Pixel 10 Pro XL): bidirectional live knob/bypass editing, 100-slot hardware bank sync, slot writing, and right-to-left (`OUT ← IN`) signal chain reordering. |
| **Zoom MS-50G+** | Zoom MS Plus (`0x6E`) | 106 effects | Complete typed catalog included; shares the MS Plus protocol (`0x6E`) and should work, though physical hardware testing has only been performed on the MS-60B+ so far. |
| **Zoom MS-70CDR+** | Zoom MS Plus (`0x6E`) | 150 effects | Complete typed catalog included; shares the MS Plus protocol (`0x6E`) and should work, though physical hardware testing has only been performed on the MS-60B+ so far. |
| **Zoom MS-200D+** | Zoom MS Plus (`0x6E`) | 224 effects | Complete typed catalog included; shares the MS Plus protocol (`0x6E`) and should work, though physical hardware testing has only been performed on the MS-60B+ so far. |
| **Zoom B1X FOUR / B1 FOUR** | Zoom Four (`0x6E` / `DeviceGeneration.zoomFour`) | 99 effects (93 without Expression Pedal on B1 FOUR) | Pure Dart protocol (`ZoomFourProtocol`, `PtcfCodec`), authoritative ZDL7 32-bit effect IDs (`tool/reference/zoom-b1x-four-list.txt`), 5-slot / 50-patch (`10`–`59`) bank model, USB/`0x6E` identity detection (`0x0C`–`0x0F`), `.zb1f`/`.ptcf`/`.syx` import/export, and cross-generation write locks verified via automated tests. (Includes `G1X FOUR` / `G1 FOUR` model recognition & `.zg1f` support.) |
| **Line 6 Bass POD Pro** | Line 6 (`0x0E41` / `0x02`) | 16 amps, 16 cabs, 16 effects | Firmware 1.40 protocol framing and 36-slot (`1A`–`9D`) bank support implemented; physical hardware verification pending. |

Total typed effect catalog coverage: **578** Zoom MS Plus definitions + **99** Zoom B1X FOUR definitions + **50** Line 6 definitions.

### Connectivity Scope
- **Supported:** Wired USB MIDI across Linux ALSA (`amidi`), Android USB Host OTG (`android.media.midi`), and Windows native WinMM (`winmm.dll` via pure `dart:ffi`).
- **Not Supported:** Bluetooth LE (BLE) MIDI is not supported and is not currently planned.

---

## Key Features (Through Milestone 19A)

- **Zoom Four (`B1X FOUR` / `B1 FOUR`) & Multi-Generation Protocol Support:** Full `ZoomFourProfile`, `ZoomFourProtocol`, `PtcfCodec`, and `ZoomFourCatalog` support enforcing 5 effect slots max, 50 persistent patches numbered `10`–`59` across 5 banks (`10–19` to `50–59`), `hasExpressionPedal` capabilities (`PDL Vol`, `BassWah`, `PDL Reso`, `Ba PDLPit`, `Ba PDLMnP`, `Output VP` on `B1X FOUR` / `G1X FOUR`), strict ZDL7-vs-MS+ catalog isolation, USB/`0x6E` identity disambiguation, and **ToneLib `.zb1f` / `.zg1f`** XML/PTCF export and import alongside `.zptc` / `.ptcf` / `.syx`.

- **Physical Pedal Patch-Switch Sync & Hardware Generation Locks:** Incoming pedal patch switches (`64 26 00 00`, Bank Select CC `0`/`32` + PC, and `64 12 01` dumps) immediately update the active hardware slot and editor buffer with zero MIDI echo (`notifyHardware: false`); hardware generation locks (`DeviceGeneration`) hard-block incompatible cross-generation writes (e.g., Line 6 ↔ Zoom MS Plus) while allowing same-generation cross-model writes (e.g., MS-50G+ → MS-60B+) after confirmation.

- **Drag-and-Drop Bank Manager, Custom Export Browser & File-Based Batch Restore:** Side-by-side `BankManagerDialog` pairing searchable, family/tag-filterable local presets with hardware bank slots (`Draggable` on desktop, `LongPressDraggable` on mobile touchscreens) with bidirectional drag-and-drop transfer, generation compatibility enforcement, sequential **"Restore Bank..."** (`BankRestoreDialog`) from local multi-select, **From File / Folder** disk backups (`.json`, `.syx`, `.zptc`, Symbiosis batch folders) without duplicating library presets, or pasted bundles, interactive destination folder browsing + `lastExportDirectory` persistence in `PatchExportDialog`, and **"Save Copy As..."** preset duplication (`SaveCopyAsDialog`) in `PatchMetadataHeaderWidget` and `PatchLibraryDrawerOrPanel`.

- **Multi-File Patch Import & Library-Only Mode:** `PatchImportDialog` supports checking multiple individual patch files in a folder for batch decode and defaults **"Import to Library"** to bypass the active editor buffer (with an explicit opt-in `"Also load into Editor"` toggle for single patches).

- **Native Cross-Platform Hardware USB MIDI:** Zero-dependency hardware MIDI transports for Linux ALSA (`LinuxAlsaMidiTransport`), Android USB Host OTG (`AndroidMidiTransport`), and Windows WinMM (`WinMmMidiTransport` via pure `dart:ffi` to `winmm.dll` and `kernel32.dll`, with endpoint pairing, `NativeCallable.listener` SysEx ring reassembly, and `MIDIHDR` SysEx transmission).

- **Live Performance Setlist Mode & Hardware Tuner Toggle:** Ordered gig/rehearsal setlists referencing saved library patches with BPM overrides, cue notes, a full-screen Stage Mode view with responsive portrait layout and a dedicated **Landscape Stage Dashboard** (`~22%` left column with setlist selector, compact active-patch header, `PREV`/`NEXT` step buttons, `TUNER` toggle, and auto-scrolling setlist patch list + `~78%` right adaptive grid of giant touch-friendly effect stompboxes with live bypass toggling), **Hardware Tuner Toggle** in both `ConnectionBarWidget` and `SetlistPerformanceView` (Line 6 `PC 37` / restore PC; Zoom MS Plus 7-byte SysEx `F0 52 00 6E 64 0B F7` ON / `F0 52 00 6E 64 0C F7` OFF with bidirectional feedback), immediate hardware dispatch (`64 20 00` deltas on Zoom MS Plus, `encodePatch` on Line 6), and optional incoming MIDI Program Change / CC foot-controller triggers.
- **Right-to-Left Pedalboard Signal Chain & Desktop Mouse Ergonomics:** Physical audio-flow strip (`OUT ← ... ← IN`) with drag-and-drop reordering (`LongPressDraggable` on mobile touchscreens, immediate drag on desktop), inter-slot insertion zones, custom scroll/drag rotary knobs (`RotaryKnobWidget`), inline click-to-edit Tempo (BPM) input, compact Effect Palette category dropdown and Preset Library multi-select checkbox tag filter, and desktop mouse-wheel / interactive scrollbar horizontal scrolling (with dedicated bottom scrollbar gutter) across overflowing frames.
- **Undo/Redo History, A/B Tone Compare & Patch Diff Preview:** Bounded 50-step Undo/Redo history with rotary-knob drag coalescing and desktop keyboard shortcuts (`Ctrl+Z` / `Ctrl+Y` / `Ctrl+Shift+Z`), instant `A | B` tone comparison with live hardware delta sync (`64 20 00` on Zoom MS Plus, `encodePatch` on Line 6), and structured `PatchDiffDialog` previews for A/B compare, pre-write slot diffing, library preset comparison, and import preview.
- **Live Bidirectional Hardware Sync:** Real-time knob, bypass, and active-slot focus synchronization with Zoom MS Plus hardware, plus 100-slot hardware bank browsing and slot writing.
- **Responsive & Adaptive UI:** Three-tier breakpoints (`compact`, `medium`, `expanded`) across phone portrait/landscape, tablets, and resized desktop windows, with unified vertical scrolling on short viewports and keyboard-safe dialogs.
- **Local Patch Library & Multi-Format Export / Import:** Manage offline preset libraries and export or import/restore single patches, full libraries, or hardware banks in:
  - **Signal Chain Native JSON** (`.json` single patches and library bundles)
  - **Zoom PTCF** (`.zptc`)
  - **Symbiosis** (model-suffixed `.<model>.zptc`, e.g., `.60bp.zptc` / `.50gp.zptc` / `.70cdrp.zptc` / `.200dp.zptc` / `.b1xf.zptc` / `.b1f.zptc`, and batch backup folders)
  - **ToneLib Zoom Four** (`.zb1f` / `.zg1f` XML-wrapped `PTCF` containers for `B1X FOUR`, `B1 FOUR`, `G1X FOUR`, `G1 FOUR`)
  - **Zoom MultiStomp Studio** (`.zptc`)
  - **Raw SysEx** (`.syx`, including Zoom `0x45` / `64 12 01`, Line 6 `0x02`, and multi-message `.syx` files)
- **Persistent Preferences:** Default export format and app preferences persist via pure `dart:io` storage (`$XDG_CONFIG_HOME/signal_chain_flutter/preferences.json` on Linux).

---

## Building, Running & Testing (`--no-pub`)

Because the project uses **zero external `pub.dev` packages**, all Flutter commands should be run with `--no-pub` (no dependency fetching step is needed):

- **Run on Linux desktop:**
  ```bash
  flutter run -d linux --no-pub
  ```
- **Run on Windows desktop:**
  ```bash
  flutter run -d windows --no-pub
  ```
- **Build Android debug APK:**
  ```bash
  flutter build apk --debug --no-pub
  ```
- **Linux AppImage & DEB packaging:**
  - DEB package: `./tool/package_linux_deb.sh`
  - AppImage: `./tool/package_linux_appimage.sh`
  - Local desktop install (`~/.local`): `./tool/install_linux_desktop.sh`
  - Desktop & AppStream metadata: [`linux/packaging/signal-chain.desktop`](linux/packaging/signal-chain.desktop) and [`linux/packaging/io.github.bassmannate.signal_chain.appdata.xml`](linux/packaging/io.github.bassmannate.signal_chain.appdata.xml)
- **Windows portable ZIP packaging:**
  - `./tool/package_windows_zip.ps1`
- **Automated GitHub Releases:**
  - Pushing a `v*.*.*` tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which runs `flutter analyze --no-pub` and `flutter test --no-pub`, builds Linux (`.deb` and `.AppImage`), Android (`signal-chain-<version>-android.apk`, signed persistently via `ANDROID_KEYSTORE_BASE64` → `android/app/release-keystore.jks` + `android/key.properties`, with F-Droid reproducible build configuration), and Windows (`.zip`) artifacts, generates `SHA256SUMS.txt`, and publishes the GitHub Release via `softprops/action-gh-release@v3`.
  - **Android APK Signing & In-Place Upgrades:** CI release builds require `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` secrets and fail if missing so debug-signed APKs are never published; local developer builds fall back to `signingConfigs.debug` only when `android/key.properties` is absent. Starting with `v1.2.1`, release APKs use a persistent signing key so future upgrades install cleanly in place without losing local presets or setlists (if upgrading from an earlier debug-signed pre-`1.2.1` APK, export your library and uninstall the older build once before installing `v1.2.1`).
- **Static analysis & tests:**
  ```bash
  flutter analyze --no-pub
  flutter test --no-pub
  ```

---

## Project Documentation & Roadmap

- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — Architecture, protocol notes, and milestone highlights
- [SPEC.md](SPEC.md) — Detailed technical specification
- [STATUS.md](STATUS.md) — Milestone completion log and test verification status
