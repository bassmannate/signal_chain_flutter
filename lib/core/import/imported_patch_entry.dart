import '../../models/device_family.dart';
import '../../models/patch.dart';
import 'import_format.dart';

/// Represents a single decoded [Patch] produced by an [ImportAdapter].
class ImportedPatchEntry {
  final Patch patch;
  final ImportFormat detectedFormat;
  final DeviceFamily inferredDeviceFamily;
  final String sourceName;
  final String? sourcePath;
  final int? messageIndex;
  final List<String> warnings;

  const ImportedPatchEntry({
    required this.patch,
    required this.detectedFormat,
    required this.inferredDeviceFamily,
    required this.sourceName,
    this.sourcePath,
    this.messageIndex,
    this.warnings = const [],
  });

  /// Returns true when this patch targets a different known device than [activeFamily].
  bool isDeviceMismatch(DeviceFamily activeFamily) =>
      inferredDeviceFamily != DeviceFamily.unknown &&
      activeFamily != DeviceFamily.unknown &&
      inferredDeviceFamily != activeFamily;

  ImportedPatchEntry copyWith({
    Patch? patch,
    ImportFormat? detectedFormat,
    DeviceFamily? inferredDeviceFamily,
    String? sourceName,
    String? sourcePath,
    int? messageIndex,
    List<String>? warnings,
  }) {
    return ImportedPatchEntry(
      patch: patch ?? this.patch,
      detectedFormat: detectedFormat ?? this.detectedFormat,
      inferredDeviceFamily: inferredDeviceFamily ?? this.inferredDeviceFamily,
      sourceName: sourceName ?? this.sourceName,
      sourcePath: sourcePath ?? this.sourcePath,
      messageIndex: messageIndex ?? this.messageIndex,
      warnings: warnings ?? this.warnings,
    );
  }
}

