import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../core/diagnostics/app_diagnostics_log.dart';
import '../../core/midi/composite_midi_transport.dart';
import '../../core/storage/custom_effect_repository.dart';
import '../../core/storage/file_system_custom_effect_repository.dart';
import '../../core/storage/file_system_patch_library_repository.dart';
import '../connection/device_connection_controller.dart';
import '../library/patch_library_controller.dart';
import '../theme/studio_theme.dart';

enum _LogFilter {
  all('All'),
  connection('Connection'),
  discovery('Discovery'),
  transfer('Transfer'),
  writes('Writes');

  final String label;

  const _LogFilter(this.label);

  bool matches(DiagnosticLogEntry entry) {
    switch (this) {
      case _LogFilter.all:
        return true;
      case _LogFilter.connection:
        return entry.category == 'Connection';
      case _LogFilter.discovery:
        return entry.category == 'Discovery' ||
            entry.category == 'CustomEffects';
      case _LogFilter.transfer:
        return entry.category == 'ZoomFileTransfer' ||
            entry.category == 'Transfer';
      case _LogFilter.writes:
        return entry.category == 'Writes';
    }
  }
}

/// Modal dialog presenting app version/metadata, live environment & hardware
/// summary, and a filterable live diagnostics log viewer.
class AboutDiagnosticsDialog extends StatefulWidget {
  final DeviceConnectionController connectionController;
  final PatchLibraryController? libraryController;
  final CustomEffectRepository? customEffectRepository;
  final AppDiagnosticsLog diagnosticsLog;
  final int initialTabIndex;

  AboutDiagnosticsDialog({
    super.key,
    required this.connectionController,
    this.libraryController,
    this.customEffectRepository,
    AppDiagnosticsLog? diagnosticsLog,
    this.initialTabIndex = 0,
  }) : diagnosticsLog = diagnosticsLog ?? connectionController.diagnosticsLog;

  /// Opens [AboutDiagnosticsDialog] modally.
  static Future<void> show({
    required BuildContext context,
    required DeviceConnectionController connectionController,
    PatchLibraryController? libraryController,
    CustomEffectRepository? customEffectRepository,
    AppDiagnosticsLog? diagnosticsLog,
    int initialTabIndex = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AboutDiagnosticsDialog(
        connectionController: connectionController,
        libraryController: libraryController,
        customEffectRepository: customEffectRepository,
        diagnosticsLog: diagnosticsLog,
        initialTabIndex: initialTabIndex,
      ),
    );
  }

  @override
  State<AboutDiagnosticsDialog> createState() => _AboutDiagnosticsDialogState();
}

class _AboutDiagnosticsDialogState extends State<AboutDiagnosticsDialog> {
  final ScrollController _logScrollController = ScrollController();
  _LogFilter _selectedFilter = _LogFilter.all;
  bool _autoScroll = true;
  int _lastObservedEntryCount = -1;

  @override
  void initState() {
    super.initState();
    _lastObservedEntryCount = widget.diagnosticsLog.length;
    widget.diagnosticsLog.addListener(_onLogUpdated);
    if (widget.initialTabIndex == 1 && _autoScroll) {
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    widget.diagnosticsLog.removeListener(_onLogUpdated);
    _logScrollController.dispose();
    super.dispose();
  }

  void _onLogUpdated() {
    final currentCount = widget.diagnosticsLog.length;
    if (_autoScroll && currentCount > _lastObservedEntryCount) {
      _scheduleScrollToBottom();
    }
    _lastObservedEntryCount = currentCount;
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logScrollController.hasClients) return;
      _logScrollController.jumpTo(
        _logScrollController.position.maxScrollExtent,
      );
    });
  }

  String _resolveTransportLabel() {
    final transport = widget.connectionController.transport;
    if (transport is CompositeMidiTransport) {
      return (transport.activeTransport ?? transport).runtimeType.toString();
    }
    return transport.runtimeType.toString();
  }

  String _resolveConnectionSummary() {
    final conn = widget.connectionController;
    if (!conn.isConnected) {
      return 'Disconnected';
    }
    final portName = conn.connectedPort?.name ?? 'Unknown Port';
    return 'Connected ($portName via ${_resolveTransportLabel()})';
  }

  String _resolveOnboardEffectsSummary() {
    final conn = widget.connectionController;
    if (conn.isScanningEffects) {
      return conn.effectScanStatusMessage ?? 'Scanning...';
    }
    if (!conn.isConnected) {
      return 'Not connected';
    }
    if (conn.installedEffectIds == null) {
      return conn.effectScanError ?? 'Not scanned';
    }
    return '${conn.discoveredStockIds.length} stock, '
        '${conn.discoveredCrossModelIds.length} cross-model, '
        '${conn.discoveredCustomIds.length} custom';
  }

  String _resolvePresetsPath() {
    final repo = widget.libraryController?.repository;
    if (repo is FileSystemPatchLibraryRepository) {
      return repo.storageDir.path;
    }
    return 'In-memory (session only)';
  }

  String _resolveCustomEffectsPath() {
    final repo =
        widget.customEffectRepository ??
        widget.connectionController.customEffectRepository;
    if (repo is FileSystemCustomEffectRepository) {
      return repo.storageFile.path;
    }
    return 'In-memory (session only)';
  }

  String _buildEnvironmentHeader() {
    final conn = widget.connectionController;
    final lines = <String>[
      '${AppInfo.appName} v${AppInfo.version} (${AppInfo.license})',
      'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
      'Connection: ${_resolveConnectionSummary()}',
      'Active Device Family: ${conn.activeFamily.displayName}',
      'Onboard Effects: ${_resolveOnboardEffectsSummary()}',
      'Presets Storage: ${_resolvePresetsPath()}',
      'Custom Effects Storage: ${_resolveCustomEffectsPath()}',
    ];
    return lines.join('\n');
  }

  Future<void> _copyTextWithFeedback(String text, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(confirmation),
        backgroundColor: StudioTheme.colorConnected,
      ),
    );
  }

  Future<void> _copyFullDiagnostics() async {
    final header = _buildEnvironmentHeader();
    final logText = widget.diagnosticsLog.formatPlainText();
    final combined = logText.isEmpty
        ? '$header\n\n<no diagnostic entries>'
        : '$header\n\n$logText';
    await _copyTextWithFeedback(
      combined,
      'Copied environment summary and diagnostics log to clipboard.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final isCompact = mediaSize.width < 600;
    final isShort = mediaSize.height < 520;
    final dialogWidth = math.min(680.0, math.max(280.0, mediaSize.width - 24));
    final dialogHeight = math.min(
      560.0,
      math.max(300.0, mediaSize.height - (isShort ? 40 : 96)),
    );

    return AlertDialog(
      backgroundColor: StudioTheme.surfaceElevated,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 28,
        vertical: isShort ? 10 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      title: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 20,
            color: StudioTheme.colorModulation,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'About & Diagnostics Log',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            'v${AppInfo.version}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StudioTheme.colorModulation,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: DefaultTabController(
          length: 2,
          initialIndex: widget.initialTabIndex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TabBar(
                indicatorColor: StudioTheme.colorModulation,
                labelColor: StudioTheme.colorModulation,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(key: Key('about_tab'), text: 'About'),
                  Tab(key: Key('diagnostics_log_tab'), text: 'Diagnostics Log'),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildAboutTab(),
                    _buildDiagnosticsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('about_diagnostics_close_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildAboutTab() {
    return ListenableBuilder(
      listenable: widget.connectionController,
      builder: (context, _) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          AppInfo.appName,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: StudioTheme.colorModulation.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: StudioTheme.colorModulation.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: const Text(
                            'v${AppInfo.version}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: StudioTheme.colorModulation,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: StudioTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: StudioTheme.surfaceBorder),
                          ),
                          child: const Text(
                            '${AppInfo.license} License',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      AppInfo.description,
                      style: TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'Repo: ',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const Expanded(
                          child: SelectableText(
                            AppInfo.repositoryUrl,
                            style: TextStyle(
                              fontSize: 12,
                              color: StudioTheme.colorModulation,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('copy_repo_url_button'),
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy Repository URL',
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: () => _copyTextWithFeedback(
                            AppInfo.repositoryUrl,
                            'Copied repository URL to clipboard.',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                key: const Key('environment_hardware_summary_card'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.memory,
                          size: 16,
                          color: StudioTheme.colorConnected,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Environment & Hardware Summary',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SummaryRow(
                      label: 'Platform',
                      value:
                          '${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
                    ),
                    _SummaryRow(
                      label: 'Connection',
                      value: _resolveConnectionSummary(),
                      valueColor: widget.connectionController.isConnected
                          ? StudioTheme.colorConnected
                          : Colors.white70,
                    ),
                    _SummaryRow(
                      label: 'Device Family',
                      value:
                          widget.connectionController.activeFamily.displayName,
                    ),
                    _SummaryRow(
                      label: 'Onboard Effects',
                      value: _resolveOnboardEffectsSummary(),
                    ),
                    _SummaryRow(
                      label: 'Presets Path',
                      value: _resolvePresetsPath(),
                      monospace: true,
                    ),
                    _SummaryRow(
                      label: 'Custom .ZD2 Path',
                      value: _resolveCustomEffectsPath(),
                      monospace: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagnosticsTab() {
    return ListenableBuilder(
      listenable: widget.diagnosticsLog,
      builder: (context, _) {
        final filteredEntries = widget.diagnosticsLog.entries
            .where(_selectedFilter.matches)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final filter in _LogFilter.values)
                  ChoiceChip(
                    key: Key('log_filter_${filter.name}'),
                    label: Text(filter.label),
                    selected: _selectedFilter == filter,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                      if (_autoScroll) {
                        _scheduleScrollToBottom();
                      }
                    },
                  ),
                FilterChip(
                  key: const Key('diagnostics_autoscroll_toggle'),
                  label: const Text('Auto-scroll'),
                  selected: _autoScroll,
                  visualDensity: VisualDensity.compact,
                  onSelected: (selected) {
                    setState(() {
                      _autoScroll = selected;
                    });
                    if (selected) {
                      _scheduleScrollToBottom();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                key: const Key('diagnostics_log_viewport'),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: StudioTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: filteredEntries.isEmpty
                    ? const Center(
                        child: Text(
                          'No diagnostic log entries.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _logScrollController,
                        itemCount: filteredEntries.length,
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: SelectableText(
                              entry.formatLine(),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                height: 1.35,
                                color: _colorForLevel(entry.level),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${filteredEntries.length} / ${widget.diagnosticsLog.length} entries',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('diagnostics_clear_log_button'),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: const Text('Clear Log'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: StudioTheme.surfaceBorder),
                      ),
                      onPressed: widget.diagnosticsLog.isEmpty
                          ? null
                          : () => widget.diagnosticsLog.clear(),
                    ),
                    ElevatedButton.icon(
                      key: const Key('diagnostics_copy_log_button'),
                      icon: const Icon(Icons.copy_all_outlined, size: 16),
                      label: const Text('Copy Log'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StudioTheme.colorModulation,
                        foregroundColor: Colors.black,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _copyFullDiagnostics,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static Color _colorForLevel(DiagnosticLogLevel level) {
    switch (level) {
      case DiagnosticLogLevel.info:
        return Colors.white70;
      case DiagnosticLogLevel.warn:
        return StudioTheme.colorDirty;
      case DiagnosticLogLevel.error:
        return StudioTheme.colorDisconnected;
    }
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool monospace;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor ?? Colors.white,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
