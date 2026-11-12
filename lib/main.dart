import 'dart:io';

import 'package:flutter/material.dart';

import 'core/midi/composite_midi_transport.dart';
import 'core/midi/linux_alsa_midi_transport.dart';
import 'core/midi/midi_message.dart';
import 'core/midi/midi_port_descriptor.dart';
import 'core/midi/midi_transport.dart';
import 'core/midi/mock_midi_transport.dart';
import 'core/storage/file_system_patch_library_repository.dart';
import 'core/storage/in_memory_patch_library_repository.dart';
import 'core/storage/patch_library_repository.dart';
import 'features/connection/connection_bar_widget.dart';
import 'features/connection/device_connection_controller.dart';
import 'features/editor/effect_bank_palette_widget.dart';
import 'features/editor/patch_editor_controller.dart';
import 'features/editor/signal_chain_strip_widget.dart';
import 'features/editor/slot_inspector_widget.dart';
import 'features/library/patch_library_controller.dart';
import 'features/library/patch_library_drawer_or_panel.dart';
import 'features/theme/studio_theme.dart';
import 'models/device_family.dart';
import 'models/effect_slot.dart';
import 'models/parameter_descriptor.dart';
import 'models/patch.dart';
import 'protocols/catalogs/effect_catalog.dart';
import 'protocols/line6_bass_pod_pro_protocol.dart';
import 'protocols/zoom_ms_plus_protocol.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SignalChainApp());
}

/// Root widget for Signal Chain Flutter Studio.
class SignalChainApp extends StatefulWidget {
  final MidiTransport? transport;
  final PatchLibraryRepository? libraryRepository;
  final DeviceConnectionController? connectionController;
  final PatchEditorController? editorController;
  final PatchLibraryController? libraryController;

  const SignalChainApp({
    super.key,
    this.transport,
    this.libraryRepository,
    this.connectionController,
    this.editorController,
    this.libraryController,
  });

  @override
  State<SignalChainApp> createState() => _SignalChainAppState();
}

class _SignalChainAppState extends State<SignalChainApp> {
  late final MidiTransport _transport;
  late final PatchLibraryRepository _libraryRepo;
  late final DeviceConnectionController _connectionController;
  late final PatchEditorController _editorController;
  late final PatchLibraryController _libraryController;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    EffectCatalogRegistry.ensureInitialized();

    final zoomSample = _createSampleZoomPatch();
    final line6Sample = _createSampleLine6Patch();

    // 1. Initialize Transport (Composite Linux ALSA + Simulation, or provided)
    if (widget.transport != null) {
      _transport = widget.transport!;
    } else {
      final mock = _createMockTransportWithResponders(zoomSample, line6Sample);
      if (_isRunningInWidgetTest) {
        _transport = mock;
      } else {
        final childTransports = <MidiTransport>[];
        if (Platform.isLinux) {
          childTransports.add(LinuxAlsaMidiTransport());
        }
        childTransports.add(mock);
        _transport = CompositeMidiTransport(transports: childTransports);
      }
    }

    // 2. Initialize Library Repository
    if (widget.libraryRepository != null) {
      _libraryRepo = widget.libraryRepository!;
    } else if (_isRunningInWidgetTest) {
      _libraryRepo = InMemoryPatchLibraryRepository(
        initialPatches: [zoomSample, line6Sample],
      );
    } else {
      _libraryRepo = _createDefaultLibraryRepository(zoomSample, line6Sample);
    }

    // 3. Initialize Controllers
    _connectionController = widget.connectionController ??
        DeviceConnectionController(transport: _transport);

    _editorController = widget.editorController ??
        PatchEditorController(
          transport: _transport,
          connectionController: _connectionController,
          initialPatch: zoomSample,
        );

    _connectionController.setEditorController(_editorController);

    _libraryController = widget.libraryController ??
        PatchLibraryController(repository: _libraryRepo);

    // Initial async setup
    _connectionController.refreshPorts();
    _libraryController.refresh();

    // Seed filesystem repository if empty (at runtime outside widget tests)
    if (!_isRunningInWidgetTest && widget.libraryRepository == null) {
      _seedStorageIfEmpty(zoomSample, line6Sample);
    }
  }

  @override
  void dispose() {
    if (widget.transport == null) {
      _transport.dispose();
    }
    if (widget.connectionController == null) {
      _connectionController.dispose();
    }
    if (widget.editorController == null) {
      _editorController.dispose();
    }
    if (widget.libraryController == null) {
      _libraryController.dispose();
    }
    super.dispose();
  }

  static bool get _isRunningInWidgetTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static MockMidiTransport _createMockTransportWithResponders(
    Patch zoomSample,
    Patch line6Sample,
  ) {
    final mock = MockMidiTransport(
      initialPorts: const [
        MidiPortDescriptor(
          id: 'sim_zoom',
          name: 'Zoom MS-60B+ (Simulated)',
          manufacturer: 'Zoom Corporation',
          isInput: true,
          isOutput: true,
        ),
        MidiPortDescriptor(
          id: 'sim_line6',
          name: 'Line 6 Bass Pod Pro (Simulated)',
          manufacturer: 'Line 6',
          isInput: true,
          isOutput: true,
        ),
      ],
    );

    // Auto-responder for Universal Identity Requests
    mock.registerResponder(
      (req) =>
          req.isSysEx &&
          req.data.length >= 5 &&
          req.data[1] == 0x7E &&
          req.data[3] == 0x06 &&
          req.data[4] == 0x01,
      (req) {
        if (mock.connectedPort?.id == 'sim_line6') {
          return MidiMessage.sysEx([
            0x7E, 0x00, 0x06, 0x02, 0x00, 0x01, 0x0C, 0x01, 0x00, 0x03, 0x00,
          ]);
        }
        // Default: Zoom MS-60B+
        return MidiMessage.sysEx([
          0x7E, 0x00, 0x06, 0x02, 0x52, 0x6E, 0x00, 0x27, 0x00, 0x31, 0x2E, 0x30, 0x30,
        ]);
      },
    );

    // Auto-responder for Zoom Current Patch Request (64 13)
    mock.registerResponder(
      (req) =>
          req.isSysEx &&
          req.data.length >= 7 &&
          req.data[1] == 0x52 &&
          req.data[4] == 0x64 &&
          req.data[5] == 0x13,
      (req) => const ZoomMsPlusProtocol().encodePatch(zoomSample),
    );

    // Auto-responder for Zoom Request Current Bank & Program (33)
    mock.registerResponder(
      (req) =>
          req.isSysEx &&
          req.data.length >= 5 &&
          req.data[1] == 0x52 &&
          req.data[3] == 0x6E &&
          req.data[4] == 0x33,
      (req) => MidiMessage.sysEx([
        0x52, 0x00, 0x6E, 0x64, 0x26, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]),
    );

    // Auto-responder for Zoom Memory Slot Request (46 00 00)
    mock.registerResponder(
      (req) =>
          req.isSysEx &&
          req.data.length >= 11 &&
          req.data[1] == 0x52 &&
          req.data[4] == 0x46 &&
          req.data[5] == 0x00 &&
          req.data[6] == 0x00,
      (req) {
        final bank = req.data[7] | (req.data[8] << 7);
        final prog = req.data[9] | (req.data[10] << 7);
        final slotNum = (bank * 10) + prog;
        return const ZoomMsPlusProtocol().buildSavePatchToSlotMessage(
          zoomSample.copyWith(
            name: 'Slot ${slotNum.toString().padLeft(2, '0')}',
            programNumber: slotNum,
          ),
          slotNum,
        );
      },
    );

    // Auto-responder for Line 6 Edit Buffer Dump Request (F0 00 01 0C 01 00 F7)
    mock.registerResponder(
      (req) =>
          req.isSysEx &&
          req.data.length >= 6 &&
          req.data[1] == 0x00 &&
          req.data[2] == 0x01 &&
          req.data[3] == 0x0C &&
          req.data[5] == 0x00,
      (req) => const Line6BassPodProProtocol().encodePatch(line6Sample),
    );

    // Auto-responder for Line 6 Program Dump Request (F0 00 01 0C 01 01 <prog> F7)
    mock.registerResponder(
      (req) =>
          req.isSysEx &&
          req.data.length >= 7 &&
          req.data[1] == 0x00 &&
          req.data[2] == 0x01 &&
          req.data[3] == 0x0C &&
          req.data[5] == 0x01,
      (req) {
        final prog = req.data[6] & 0x7F;
        return const Line6BassPodProProtocol().buildSavePatchToSlotMessage(
          line6Sample.copyWith(
            name: 'POD ${prog.toString().padLeft(2, '0')}',
            programNumber: prog,
          ),
          prog,
        );
      },
    );

    return mock;
  }

  static Directory _resolvePresetsDirectory() {
    if (Platform.isLinux) {
      final xdgData = Platform.environment['XDG_DATA_HOME'];
      if (xdgData != null && xdgData.isNotEmpty) {
        return Directory('$xdgData/signal_chain_flutter/presets');
      }
      final home = Platform.environment['HOME'] ?? '';
      return Directory('$home/.local/share/signal_chain_flutter/presets');
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      return Directory('$appData/signal_chain_flutter/presets');
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return Directory('$home/Library/Application Support/signal_chain_flutter/presets');
    } else {
      return Directory('${Directory.systemTemp.path}/signal_chain_flutter/presets');
    }
  }

  static PatchLibraryRepository _createDefaultLibraryRepository(
    Patch zoomSample,
    Patch line6Sample,
  ) {
    try {
      final dir = _resolvePresetsDirectory();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return FileSystemPatchLibraryRepository(storageDir: dir);
    } catch (_) {
      // Graceful fallback to InMemory repository if filesystem is restricted
      return InMemoryPatchLibraryRepository(
        initialPatches: [zoomSample, line6Sample],
      );
    }
  }

  Future<void> _seedStorageIfEmpty(Patch zoomSample, Patch line6Sample) async {
    try {
      final existing = await _libraryRepo.getAllPatches();
      if (existing.isEmpty) {
        await _libraryRepo.savePatch(zoomSample);
        await _libraryRepo.savePatch(line6Sample);
        await _libraryController.refresh();
      }
    } catch (_) {
      // Ignore seeding errors in sandboxed contexts
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signal Chain Studio',
      debugShowCheckedModeBanner: false,
      theme: StudioTheme.darkTheme,
      home: Scaffold(
        key: _scaffoldKey,
        endDrawer: Drawer(
          backgroundColor: StudioTheme.surface,
          child: SafeArea(
            child: PatchLibraryDrawerOrPanel(
              libraryController: _libraryController,
              editorController: _editorController,
              isPanel: false,
            ),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktopWide = constraints.maxWidth >= 900;

              final editorContent = Column(
                children: [
                  // Pedalboard Signal Chain Strip
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SignalChainStripWidget(controller: _editorController),
                  ),

                  // Selected Slot Parameter Inspector + Studio Effect Palette
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: isDesktopWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: SlotInspectorWidget(controller: _editorController),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 320,
                                  child: EffectBankPaletteWidget(controller: _editorController),
                                ),
                              ],
                            )
                          : DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: StudioTheme.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: StudioTheme.surfaceBorder),
                                    ),
                                    child: const TabBar(
                                      indicatorColor: StudioTheme.colorModulation,
                                      tabs: [
                                        Tab(
                                          text: 'INSPECTOR',
                                          icon: Icon(Icons.tune, size: 16),
                                        ),
                                        Tab(
                                          text: 'EFFECT PALETTE',
                                          icon: Icon(Icons.widgets, size: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: TabBarView(
                                      children: [
                                        SlotInspectorWidget(controller: _editorController),
                                        EffectBankPaletteWidget(controller: _editorController),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              );

              return Column(
                children: [
                  ConnectionBarWidget(
                    connectionController: _connectionController,
                    editorController: _editorController,
                    libraryController: _libraryController,
                    onToggleLibrary: isDesktopWide
                        ? null
                        : () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                  Expanded(
                    child: isDesktopWide
                        ? Row(
                            children: [
                              Expanded(child: editorContent),
                              PatchLibraryDrawerOrPanel(
                                libraryController: _libraryController,
                                editorController: _editorController,
                                isPanel: true,
                              ),
                            ],
                          )
                        : editorContent,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Patch _createSampleZoomPatch() {
    return const Patch(
      id: 'zoom_sample_slap_punch',
      name: 'Slap & Punch',
      deviceFamily: DeviceFamily.zoomMs60bPlus,
      tags: ['slap', 'funk', 'modern'],
      author: 'Studio Bassist',
      slots: [
        EffectSlot(
          slotIndex: 0,
          effectId: '0x01000010',
          effectName: 'DYN Comp',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p0',
                name: 'Sense',
                min: 0,
                max: 10,
                defaultValue: 6,
              ),
              currentValue: 7.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p1',
                name: 'Attack',
                min: 0,
                max: 10,
                defaultValue: 5,
              ),
              currentValue: 4.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p2',
                name: 'Tone',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: 65.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p3',
                name: 'Level',
                min: 0,
                max: 150,
                defaultValue: 100,
              ),
              currentValue: 100.0,
            ),
          ],
        ),
        EffectSlot(
          slotIndex: 1,
          effectId: '0x02000010',
          effectName: 'Bass Preamp',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p0',
                name: 'Bass',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: 60.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p1',
                name: 'Mid',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: 55.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p2',
                name: 'Treble',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: 45.0,
            ),
          ],
        ),
        EffectSlot(
          slotIndex: 2,
          effectId: '0x03000010',
          effectName: 'Bass Drive',
          isEnabled: false,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p0',
                name: 'Gain',
                min: 0,
                max: 100,
                defaultValue: 40,
              ),
              currentValue: 35.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'p1',
                name: 'Blend',
                min: 0,
                max: 100,
                defaultValue: 50,
              ),
              currentValue: 50.0,
            ),
          ],
        ),
      ],
      metadata: {'tempo': 120},
    );
  }

  static Patch _createSampleLine6Patch() {
    return const Patch(
      id: 'line6_sample_svt_classic',
      name: 'Classic SVT',
      deviceFamily: DeviceFamily.line6BassPodPro,
      tags: ['rock', 'vintage', 'svt'],
      author: 'Line 6 Factory',
      slots: [
        EffectSlot(
          slotIndex: 0,
          effectId: 'line6_amp_1',
          effectName: 'Classic (SVT)',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'amp_model',
                name: 'Amp Model',
                min: 0,
                max: 15,
                defaultValue: 1,
              ),
              currentValue: 1.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'drive',
                name: 'Drive',
                min: 0,
                max: 127,
                defaultValue: 64,
              ),
              currentValue: 72.0,
            ),
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'bass',
                name: 'Bass',
                min: 0,
                max: 127,
                defaultValue: 64,
              ),
              currentValue: 68.0,
            ),
          ],
        ),
        EffectSlot(
          slotIndex: 1,
          effectId: 'line6_cab_6',
          effectName: '8x10 1974 Classic',
          isEnabled: true,
          parameters: [
            ParameterValue(
              descriptor: ParameterDescriptor(
                id: 'cab_model',
                name: 'Cabinet Model',
                min: 0,
                max: 7,
                defaultValue: 6,
              ),
              currentValue: 6.0,
            ),
          ],
        ),
      ],
    );
  }
}
