# Signal Chain (`signal_chain_flutter`)

Cross-platform patch editor and preset librarian for **Zoom MS Plus** series pedals and **Line 6 Bass POD Pro** rackmount processors, rewritten in pure Dart/Flutter from the original web-based [Signal Chain](https://github.com/bassmannate/signal-chain) project.

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
| **Line 6 Bass POD Pro** | Line 6 (`0x0E41` / `0x02`) | 16 amps, 16 cabs, 16 effects | Firmware 1.40 protocol framing and 36-slot (`1A`–`9D`) bank support implemented; physical hardware verification pending. |

Total Zoom MS Plus catalog coverage: **578** typed effect definitions across all four models.

### Connectivity Scope
- **Supported:** Wired USB MIDI, Linux ALSA (`amidi`), and Android USB Host OTG (`android.media.midi`).
- **Not Supported:** Bluetooth LE (BLE) MIDI is not supported and is not currently planned.

---

## Key Features (Through Milestone 12)

- **Right-to-Left Pedalboard Signal Chain:** Physical audio-flow strip (`OUT ← ... ← IN`) with drag-and-drop reordering (`LongPressDraggable` on mobile touchscreens, immediate drag on desktop), inter-slot insertion zones, and custom scroll/drag rotary knobs (`RotaryKnobWidget`).
- **Live Bidirectional Hardware Sync:** Real-time knob, bypass, and active-slot focus synchronization with Zoom MS Plus hardware, plus 100-slot hardware bank browsing and slot writing.
- **Responsive & Adaptive UI:** Three-tier breakpoints (`compact`, `medium`, `expanded`) across phone portrait/landscape, tablets, and resized desktop windows, with unified vertical scrolling on short viewports and keyboard-safe dialogs.
- **Local Patch Library & Multi-Format Export:** Manage offline preset libraries and export single patches, full libraries, or hardware banks in:
  - **Signal Chain Native JSON** (`.json`)
  - **Zoom PTCF** (`.zptc`)
  - **Symbiosis** (model-suffixed `.<model>.zptc`, e.g., `.60bp.zptc`, and batch backup folders)
  - **Zoom MultiStomp Studio** (`.zptc`)
  - **Raw SysEx** (`.syx`)
- **Persistent Preferences:** Default export format and app preferences persist via pure `dart:io` storage (`$XDG_CONFIG_HOME/signal_chain_flutter/preferences.json` on Linux).

---

## Building, Running & Testing (`--no-pub`)

Because the project uses **zero external `pub.dev` packages**, all Flutter commands should be run with `--no-pub` (no dependency fetching step is needed):

- **Run on Linux desktop:**
  ```bash
  flutter run -d linux --no-pub
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

**Upcoming (Milestone 13):** External `.zptc`, `.syx`, and `.json` file import and round-trip restore.
