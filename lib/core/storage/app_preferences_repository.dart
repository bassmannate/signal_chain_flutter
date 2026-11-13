import '../export/export_format.dart';

/// Abstract contract for persisting lightweight user preferences (such as the
/// default export format) without external pub dependencies.
abstract class AppPreferencesRepository {
  const AppPreferencesRepository();

  Future<ExportFormat?> getDefaultExportFormat();
  Future<void> setDefaultExportFormat(ExportFormat? format);
}

/// Pure in-memory implementation of [AppPreferencesRepository] for tests.
class InMemoryPreferencesRepository extends AppPreferencesRepository {
  ExportFormat? _defaultExportFormat;

  InMemoryPreferencesRepository({ExportFormat? initialDefaultExportFormat})
      : _defaultExportFormat = initialDefaultExportFormat;

  @override
  Future<ExportFormat?> getDefaultExportFormat() async => _defaultExportFormat;

  @override
  Future<void> setDefaultExportFormat(ExportFormat? format) async {
    _defaultExportFormat = format;
  }
}

