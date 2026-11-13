import 'dart:typed_data';

import '../../models/device_family.dart';
import 'import_batch_result.dart';
import 'import_format.dart';

/// Abstract contract for external and native patch/library format decoders.
abstract class ImportAdapter {
  const ImportAdapter();

  ImportFormat get format;

  /// Returns true if this adapter can decode [bytes] (using magic headers and/or [fileName]).
  bool canHandle({required Uint8List bytes, String? fileName});

  /// Decodes [bytes] into an [ImportBatchResult].
  ///
  /// Implementations must handle malformed or truncated inputs gracefully by
  /// recording [ImportDiagnostic] errors instead of throwing uncaught exceptions.
  ImportBatchResult importBytes(
    Uint8List bytes, {
    required String sourceName,
    String? sourcePath,
    DeviceFamily? targetDeviceHint,
  });
}

