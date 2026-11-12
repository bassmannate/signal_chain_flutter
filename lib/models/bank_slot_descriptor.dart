import 'device_family.dart';
import 'patch.dart';

/// Represents a persistent hardware memory bank preset slot (e.g. slots 0–99).
///
/// Distinguishes remote hardware memory indices from local file presets
/// and stores synchronization state.
class BankSlotDescriptor {
  /// Zero-based slot index on hardware (typically 0–99).
  final int index;

  /// User-visible preset name stored in this slot.
  final String name;

  /// Hardware device family associated with this bank slot.
  final DeviceFamily deviceFamily;

  /// True if the slot is uninitialized, empty, or blank.
  final bool isEmpty;

  /// True if the slot data has been fetched from hardware.
  final bool isLoaded;

  /// Full decoded patch data if fetched, or null if only index/name is known.
  final Patch? patch;

  /// Optional extra hardware metadata.
  final Map<String, dynamic> metadata;

  const BankSlotDescriptor({
    required this.index,
    required this.name,
    this.deviceFamily = DeviceFamily.zoomMs60bPlus,
    this.isEmpty = false,
    this.isLoaded = false,
    this.patch,
    this.metadata = const {},
  });

  /// 2-digit padded slot index (e.g., "00", "01", "99").
  String get formattedSlotIndex => index.toString().padLeft(2, '0');

  /// Bank and patch index format (e.g., Zoom format "1-1" to "10-10").
  String get bankAndProgramNumber {
    final bank = (index ~/ 10) + 1;
    final prog = (index % 10) + 1;
    return '$bank-$prog';
  }

  /// Human-readable slot label (e.g., "#00 (1-1)").
  String get slotLabel => '#$formattedSlotIndex ($bankAndProgramNumber)';

  BankSlotDescriptor copyWith({
    int? index,
    String? name,
    DeviceFamily? deviceFamily,
    bool? isEmpty,
    bool? isLoaded,
    Patch? patch,
    Map<String, dynamic>? metadata,
  }) {
    return BankSlotDescriptor(
      index: index ?? this.index,
      name: name ?? this.name,
      deviceFamily: deviceFamily ?? this.deviceFamily,
      isEmpty: isEmpty ?? this.isEmpty,
      isLoaded: isLoaded ?? this.isLoaded,
      patch: patch ?? this.patch,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BankSlotDescriptor &&
        other.index == index &&
        other.name == name &&
        other.deviceFamily == deviceFamily &&
        other.isEmpty == isEmpty &&
        other.isLoaded == isLoaded;
  }

  @override
  int get hashCode => Object.hash(index, name, deviceFamily, isEmpty, isLoaded);

  @override
  String toString() =>
      'BankSlotDescriptor(index: $index, name: "$name", loaded: $isLoaded, empty: $isEmpty)';
}

