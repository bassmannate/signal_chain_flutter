import 'dart:convert';
import 'dart:io';

import '../export/export_format.dart';
import 'app_preferences_repository.dart';

/// Pure `dart:io` JSON preferences repository storing settings atomically in
/// the user's XDG/AppData configuration directory.
class FileSystemPreferencesRepository extends AppPreferencesRepository {
  final File preferencesFile;

  const FileSystemPreferencesRepository({required this.preferencesFile});

  Future<Map<String, dynamic>> _readAll() async {
    if (!await preferencesFile.exists()) {
      return {};
    }
    try {
      final raw = await preferencesFile.readAsString();
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Gracefully recover from corrupted JSON
    }
    return {};
  }

  Future<void> _writeAll(Map<String, dynamic> data) async {
    final parent = preferencesFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final tempFile = File(
      '${preferencesFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(encoder.convert(data), flush: true);

    try {
      await tempFile.rename(preferencesFile.path);
    } catch (_) {
      await tempFile.copy(preferencesFile.path);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<ExportFormat?> getDefaultExportFormat() async {
    final data = await _readAll();
    return ExportFormat.fromStorageString(data['defaultExportFormat'] as String?);
  }

  @override
  Future<void> setDefaultExportFormat(ExportFormat? format) async {
    final data = await _readAll();
    data['version'] = 1;
    if (format == null) {
      data.remove('defaultExportFormat');
    } else {
      data['defaultExportFormat'] = format.storageKey;
    }
    await _writeAll(data);
  }
}

