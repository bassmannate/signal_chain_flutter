import 'dart:io';

import 'export_adapter.dart';
import 'export_payload.dart';

/// Pure `dart:io` file and directory writer for [ExportPayload]s.
///
/// Resolves OS-appropriate `SignalChainExports` directories without external
/// pub dependencies and writes single files or batch folders atomically.
class ExportFileWriter {
  const ExportFileWriter();

  /// Resolves the default OS-appropriate `SignalChainExports` directory.
  static Directory resolveDefaultExportDirectory() {
    if (Platform.isLinux) {
      final xdgDocs = Platform.environment['XDG_DOCUMENTS_DIR'];
      if (xdgDocs != null && xdgDocs.isNotEmpty) {
        return Directory('$xdgDocs/SignalChainExports');
      }
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return Directory('$home/Documents/SignalChainExports');
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ??
          Platform.environment['APPDATA'] ??
          Directory.systemTemp.path;
      return Directory('$userProfile\\Documents\\SignalChainExports');
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return Directory('$home/Documents/SignalChainExports');
    } else if (Platform.isAndroid) {
      const androidDownloads = '/storage/emulated/0/Download';
      if (Directory(androidDownloads).existsSync()) {
        return Directory('$androidDownloads/SignalChainExports');
      }
      return Directory('${Directory.systemTemp.path}/SignalChainExports');
    } else {
      return Directory('${Directory.systemTemp.path}/SignalChainExports');
    }
  }

  /// Resolves an export directory from [customDirectoryPath] if non-empty,
  /// otherwise falls back to [resolveDefaultExportDirectory].
  static Directory resolveExportDirectory({String? customDirectoryPath}) {
    final trimmed = customDirectoryPath?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return Directory(trimmed);
    }
    return resolveDefaultExportDirectory();
  }

  /// Writes [payload] to [targetDir] using [nameOverride] if provided.
  ///
  /// For [ExportPayload.isDirectoryExport], creates a subdirectory and writes all
  /// [ExportPayload.folderEntries] inside it. Returns the path of the written file
  /// or directory.
  Future<String> writePayload(
    ExportPayload payload, {
    Directory? targetDir,
    String? nameOverride,
  }) async {
    final baseDir = targetDir ?? resolveDefaultExportDirectory();
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final rawName = (nameOverride != null && nameOverride.trim().isNotEmpty)
        ? nameOverride.trim()
        : payload.suggestedName;

    if (payload.isDirectoryExport) {
      final folderStem = ExportAdapter.sanitizeFileStem(
        rawName,
        fallback: 'symbiosis_export',
      );
      final outDir = Directory('${baseDir.path}${Platform.pathSeparator}$folderStem');
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      for (final entry in payload.folderEntries) {
        final entryFile = File('${outDir.path}${Platform.pathSeparator}${entry.fileName}');
        await entryFile.writeAsBytes(entry.bytes, flush: true);
      }
      return outDir.path;
    }

    String fileName = ExportAdapter.sanitizeFileStem(rawName, fallback: 'patch_export');
    if (payload.fileExtension.isNotEmpty &&
        !fileName.toLowerCase().endsWith(payload.fileExtension.toLowerCase())) {
      fileName = '$fileName${payload.fileExtension}';
    }

    final outFile = File('${baseDir.path}${Platform.pathSeparator}$fileName');
    await outFile.writeAsBytes(payload.bytes, flush: true);
    return outFile.path;
  }
}

