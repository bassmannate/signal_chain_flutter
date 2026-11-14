import '../export/export_format.dart';

/// Abstract contract for persisting lightweight user preferences (such as the
/// default export format) without external pub dependencies.
abstract class AppPreferencesRepository {
  const AppPreferencesRepository();

  Future<ExportFormat?> getDefaultExportFormat();
  Future<void> setDefaultExportFormat(ExportFormat? format);
  Future<String?> getLastExportDirectory();
  Future<void> setLastExportDirectory(String? directoryPath);
}

/// Pure in-memory implementation of [AppPreferencesRepository] for tests.
class InMemoryPreferencesRepository extends AppPreferencesRepository {
  ExportFormat? _defaultExportFormat;
  String? _lastExportDirectory;

  InMemoryPreferencesRepository({
    ExportFormat? initialDefaultExportFormat,
    String? initialLastExportDirectory,
  })  : _defaultExportFormat = initialDefaultExportFormat,
        _lastExportDirectory = initialLastExportDirectory;

  @override
  Future<ExportFormat?> getDefaultExportFormat() async => _defaultExportFormat;

  @override
  Future<void> setDefaultExportFormat(ExportFormat? format) async {
    _defaultExportFormat = format;
  }

  @override
  Future<String?> getLastExportDirectory() async => _lastExportDirectory;

  @override
  Future<void> setLastExportDirectory(String? directoryPath) async {
    final trimmed = directoryPath?.trim();
    _lastExportDirectory = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

