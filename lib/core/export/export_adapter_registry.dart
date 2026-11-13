import '../../models/device_family.dart';
import 'adapters/native_json_export_adapter.dart';
import 'adapters/raw_sysex_export_adapter.dart';
import 'adapters/symbiosis_export_adapter.dart';
import 'adapters/zoom_multistomp_studio_export_adapter.dart';
import 'adapters/zoom_ptcf_export_adapter.dart';
import 'export_adapter.dart';
import 'export_format.dart';

/// Central registry mapping [ExportFormat]s to their [ExportAdapter] implementations.
class ExportAdapterRegistry {
  final Map<ExportFormat, ExportAdapter> _adapters;

  ExportAdapterRegistry({required List<ExportAdapter> adapters})
      : _adapters = {for (final a in adapters) a.format: a};

  /// Standard built-in registry with all 5 supported export formats.
  factory ExportAdapterRegistry.standard() {
    return ExportAdapterRegistry(
      adapters: const [
        NativeJsonExportAdapter(),
        ZoomPtcfExportAdapter(),
        SymbiosisExportAdapter(),
        ZoomMultistompStudioExportAdapter(),
        RawSysExExportAdapter(),
      ],
    );
  }

  List<ExportAdapter> get allAdapters => _adapters.values.toList(growable: false);

  ExportAdapter adapterFor(ExportFormat format) {
    final adapter = _adapters[format];
    if (adapter == null) {
      throw StateError('No ExportAdapter registered for $format');
    }
    return adapter;
  }

  /// Returns all adapters compatible with [family] (or all adapters if [family] is null).
  List<ExportAdapter> adaptersForDevice(DeviceFamily? family) {
    if (family == null) return allAdapters;
    return _adapters.values
        .where((a) => a.supportsDevice(family))
        .toList(growable: false);
  }
}

