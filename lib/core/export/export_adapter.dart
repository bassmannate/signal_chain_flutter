import '../../models/device_family.dart';
import '../../models/patch.dart';
import 'export_format.dart';
import 'export_payload.dart';

/// Abstract contract for external and native patch/library format serializers.
abstract class ExportAdapter {
  const ExportAdapter();

  ExportFormat get format;
  String get displayName => format.displayName;
  String get subtitle => format.subtitle;
  String get fileExtension => format.fileExtension;

  /// Returns true if this format supports exporting [family].
  bool supportsDevice(DeviceFamily family);

  /// Serializes a single [Patch] into an [ExportPayload].
  ExportPayload exportPatch(Patch patch);

  /// Serializes a collection of [patches] into an [ExportPayload].
  ExportPayload exportLibrary(
    List<Patch> patches, {
    String libraryName = 'signal_chain_library',
  });

  /// Sanitizes a patch or library name into a safe cross-platform filename stem.
  static String sanitizeFileStem(String rawName, {String fallback = 'patch'}) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return fallback;
    final sanitized = trimmed
        .replaceAll(RegExp(r'[^\w\-\. ]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? fallback : sanitized;
  }
}

