import 'package:flutter/foundation.dart';

/// A single song/cue entry inside a [Setlist] referencing a library [Patch] by [patchId].
@immutable
class SetlistEntry {
  final String id;
  final String patchId;
  final String? songTitle;
  final String? performanceNotes;
  final int? tempoOverride;

  const SetlistEntry({
    required this.id,
    required this.patchId,
    this.songTitle,
    this.performanceNotes,
    this.tempoOverride,
  });

  SetlistEntry copyWith({
    String? id,
    String? patchId,
    String? songTitle,
    bool clearSongTitle = false,
    String? performanceNotes,
    bool clearPerformanceNotes = false,
    int? tempoOverride,
    bool clearTempoOverride = false,
  }) {
    return SetlistEntry(
      id: id ?? this.id,
      patchId: patchId ?? this.patchId,
      songTitle: clearSongTitle ? null : (songTitle ?? this.songTitle),
      performanceNotes: clearPerformanceNotes
          ? null
          : (performanceNotes ?? this.performanceNotes),
      tempoOverride:
          clearTempoOverride ? null : (tempoOverride ?? this.tempoOverride),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patchId': patchId,
      if (songTitle != null && songTitle!.isNotEmpty) 'songTitle': songTitle,
      if (performanceNotes != null && performanceNotes!.isNotEmpty)
        'performanceNotes': performanceNotes,
      if (tempoOverride != null) 'tempoOverride': tempoOverride,
    };
  }

  factory SetlistEntry.fromJson(Map<String, dynamic> json) {
    return SetlistEntry(
      id: json['id'] as String? ?? '',
      patchId: json['patchId'] as String? ?? '',
      songTitle: json['songTitle'] as String?,
      performanceNotes: json['performanceNotes'] as String?,
      tempoOverride: (json['tempoOverride'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SetlistEntry &&
        other.id == id &&
        other.patchId == patchId &&
        other.songTitle == songTitle &&
        other.performanceNotes == performanceNotes &&
        other.tempoOverride == tempoOverride;
  }

  @override
  int get hashCode =>
      Object.hash(id, patchId, songTitle, performanceNotes, tempoOverride);
}

/// Ordered gig or rehearsal setlist referencing saved library presets.
@immutable
class Setlist {
  final String id;
  final String name;
  final List<SetlistEntry> entries;
  final DateTime? updatedAt;
  final String? notes;

  const Setlist({
    required this.id,
    required this.name,
    this.entries = const [],
    this.updatedAt,
    this.notes,
  });

  Setlist copyWith({
    String? id,
    String? name,
    List<SetlistEntry>? entries,
    DateTime? updatedAt,
    String? notes,
    bool clearNotes = false,
  }) {
    return Setlist(
      id: id ?? this.id,
      name: name ?? this.name,
      entries: entries ?? this.entries,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'entries': entries.map((e) => e.toJson()).toList(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }

  factory Setlist.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final parsedEntries = <SetlistEntry>[];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map<String, dynamic>) {
          parsedEntries.add(SetlistEntry.fromJson(item));
        } else if (item is Map) {
          parsedEntries.add(
            SetlistEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    DateTime? parsedUpdated;
    final rawUpdated = json['updatedAt'];
    if (rawUpdated is String) {
      parsedUpdated = DateTime.tryParse(rawUpdated);
    }

    return Setlist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Setlist',
      entries: List.unmodifiable(parsedEntries),
      updatedAt: parsedUpdated,
      notes: json['notes'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Setlist &&
        other.id == id &&
        other.name == name &&
        listEquals(other.entries, entries) &&
        other.updatedAt == updatedAt &&
        other.notes == notes;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAll(entries), updatedAt, notes);
}

