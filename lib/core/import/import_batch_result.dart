import 'imported_patch_entry.dart';

/// Severity level for non-patch diagnostics produced during import.
enum ImportDiagnosticSeverity {
  warning,
  skipped,
  error,
}

/// Structured diagnostic message for a skipped, warned, or failed import item.
class ImportDiagnostic {
  final ImportDiagnosticSeverity severity;
  final String sourceName;
  final String? sourcePath;
  final String message;

  const ImportDiagnostic({
    required this.severity,
    required this.sourceName,
    this.sourcePath,
    required this.message,
  });
}

/// Aggregated result of importing one or more files, folders, or text payloads.
class ImportBatchResult {
  final List<ImportedPatchEntry> entries;
  final List<ImportDiagnostic> diagnostics;
  final int totalSourcesScanned;

  const ImportBatchResult({
    this.entries = const [],
    this.diagnostics = const [],
    this.totalSourcesScanned = 0,
  });

  int get importedCount => entries.length;

  int get skippedCount => diagnostics
      .where((d) => d.severity == ImportDiagnosticSeverity.skipped)
      .length;

  int get errorCount => diagnostics
      .where((d) => d.severity == ImportDiagnosticSeverity.error)
      .length;

  int get warningCount =>
      diagnostics
          .where((d) => d.severity == ImportDiagnosticSeverity.warning)
          .length +
      entries.fold<int>(0, (sum, entry) => sum + entry.warnings.length);

  bool get hasEntries => entries.isNotEmpty;
  bool get hasErrors => errorCount > 0;
  bool get hasWarnings => warningCount > 0;

  /// Collects all unique warning messages from diagnostics and decoded entries.
  List<String> get allWarnings {
    final seen = <String>{};
    final result = <String>[];
    for (final d in diagnostics) {
      if (d.severity == ImportDiagnosticSeverity.warning && seen.add(d.message)) {
        result.add(d.message);
      }
    }
    for (final e in entries) {
      for (final w in e.warnings) {
        if (seen.add(w)) {
          result.add(w);
        }
      }
    }
    return result;
  }

  /// Collects all error messages from diagnostics.
  List<String> get allErrors => diagnostics
      .where((d) => d.severity == ImportDiagnosticSeverity.error)
      .map((d) => '${d.sourceName}: ${d.message}')
      .toList(growable: false);

  /// Merges [other] into a new [ImportBatchResult].
  ImportBatchResult merge(ImportBatchResult other) {
    return ImportBatchResult(
      entries: [...entries, ...other.entries],
      diagnostics: [...diagnostics, ...other.diagnostics],
      totalSourcesScanned: totalSourcesScanned + other.totalSourcesScanned,
    );
  }
}

