import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kDebugMode;

/// Severity level for entries stored in [AppDiagnosticsLog].
enum DiagnosticLogLevel {
  info('INFO'),
  warn('WARN'),
  error('ERROR');

  final String label;

  const DiagnosticLogLevel(this.label);
}

/// Immutable timestamped record in [AppDiagnosticsLog].
class DiagnosticLogEntry {
  final DateTime timestamp;
  final String category;
  final String message;
  final DiagnosticLogLevel level;

  const DiagnosticLogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.level = DiagnosticLogLevel.info,
  });

  /// Formats [timestamp] as local `HH:MM:SS.mmm`.
  String formatTimestamp() {
    final local = timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }

  /// Formats the entry as a single plain-text diagnostic line.
  String formatLine() =>
      '[${formatTimestamp()}] [${level.label}] [$category] $message';
}

/// Lightweight in-memory ring-buffer logger for connection, discovery, file
/// transfer, and hardware write diagnostics.
class AppDiagnosticsLog extends ChangeNotifier {
  static const int defaultMaxEntries = 500;

  static final AppDiagnosticsLog instance = AppDiagnosticsLog();

  static bool get _isFlutterTest =>
      const bool.fromEnvironment('FLUTTER_TEST') ||
      Platform.environment['FLUTTER_TEST'] == 'true';

  final int maxEntries;
  final bool mirrorToDebugPrint;
  final ListQueue<DiagnosticLogEntry> _entries = ListQueue<DiagnosticLogEntry>();

  AppDiagnosticsLog({
    this.maxEntries = defaultMaxEntries,
    bool? mirrorToDebugPrint,
  }) : mirrorToDebugPrint = mirrorToDebugPrint ?? !_isFlutterTest;

  /// Chronological snapshot of buffered entries (oldest to newest).
  List<DiagnosticLogEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  /// Appends a diagnostic entry, evicting the oldest entries past [maxEntries].
  void add(
    String category,
    String message, {
    DiagnosticLogLevel level = DiagnosticLogLevel.info,
    DateTime? timestamp,
  }) {
    final entry = DiagnosticLogEntry(
      timestamp: timestamp ?? DateTime.now(),
      category: category,
      message: message,
      level: level,
    );
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    if (mirrorToDebugPrint && kDebugMode) {
      debugPrint(entry.formatLine());
    }
    notifyListeners();
  }

  void info(String category, String message) =>
      add(category, message, level: DiagnosticLogLevel.info);

  void warn(String category, String message) =>
      add(category, message, level: DiagnosticLogLevel.warn);

  void error(String category, String message) =>
      add(category, message, level: DiagnosticLogLevel.error);

  /// Removes all buffered log entries.
  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// Formats all matching entries (or all entries) as newline-delimited text.
  String formatPlainText({bool Function(DiagnosticLogEntry entry)? where}) {
    final iterable = where == null ? _entries : _entries.where(where);
    return iterable.map((e) => e.formatLine()).join('\n');
  }
}

