import 'dart:typed_data';

import 'export_format.dart';

/// Represents a single file entry inside a multi-file folder export (e.g. Symbiosis bank backup).
class ExportFileEntry {
  final String fileName;
  final Uint8List bytes;

  const ExportFileEntry({
    required this.fileName,
    required this.bytes,
  });
}

/// Immutable result of an [ExportAdapter] serialization operation.
///
/// Supports single-file exports (via [bytes] and [suggestedName]) as well as
/// directory-based batch exports (via [folderEntries] when [isDirectoryExport] is true).
class ExportPayload {
  final ExportFormat format;
  final String suggestedName;
  final String fileExtension;
  final bool isBinary;
  final bool isDirectoryExport;
  final Uint8List bytes;
  final List<ExportFileEntry> folderEntries;
  final String previewText;
  final int exportedPatchCount;
  final int skippedPatchCount;
  final List<String> warnings;

  const ExportPayload({
    required this.format,
    required this.suggestedName,
    required this.fileExtension,
    required this.isBinary,
    this.isDirectoryExport = false,
    required this.bytes,
    this.folderEntries = const [],
    required this.previewText,
    required this.exportedPatchCount,
    this.skippedPatchCount = 0,
    this.warnings = const [],
  });
}

