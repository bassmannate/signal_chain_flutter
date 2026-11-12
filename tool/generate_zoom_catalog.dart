import 'dart:convert';
import 'dart:io';

/// Specification for a single Zoom MS Plus pedal catalog target.
class _PedalCatalogTarget {
  final String pedalKey;
  final String enumName;
  final String constantName;
  final String jsonPath;
  final String? nameOverridePath;
  final String outputPath;
  final String description;

  const _PedalCatalogTarget({
    required this.pedalKey,
    required this.enumName,
    required this.constantName,
    required this.jsonPath,
    this.nameOverridePath,
    required this.outputPath,
    required this.description,
  });
}

class _NameOverride {
  final String name;
  final String? category;

  const _NameOverride({required this.name, this.category});
}

const List<_PedalCatalogTarget> _defaultTargets = [
  _PedalCatalogTarget(
    pedalKey: 'ms60bp',
    enumName: 'DeviceFamily.zoomMs60bPlus',
    constantName: 'zoomMs60bPlusCatalogData',
    jsonPath: 'tool/reference/zoom-effect-mappings-ms60bp.json',
    nameOverridePath: 'tool/reference/zoom-effect-ids-ms60bp.js',
    outputPath: 'lib/catalog/zoom_ms60b_plus_catalog_data.dart',
    description: 'Zoom MS-60B+',
  ),
  _PedalCatalogTarget(
    pedalKey: 'ms50gp',
    enumName: 'DeviceFamily.zoomMs50gPlus',
    constantName: 'zoomMs50gPlusCatalogData',
    jsonPath: 'tool/reference/zoom-effect-mappings-ms50gp.json',
    nameOverridePath: 'tool/reference/zoom-effect-ids-ms50gp.js',
    outputPath: 'lib/catalog/zoom_ms50g_plus_catalog_data.dart',
    description: 'Zoom MS-50G+',
  ),
  _PedalCatalogTarget(
    pedalKey: 'ms70cdrp',
    enumName: 'DeviceFamily.zoomMs70cdrPlus',
    constantName: 'zoomMs70cdrPlusCatalogData',
    jsonPath: 'tool/reference/zoom-effect-mappings-ms70cdrp.json',
    nameOverridePath: 'tool/reference/zoom-effect-ids-ms70cdrp.js',
    outputPath: 'lib/catalog/zoom_ms70cdr_plus_catalog_data.dart',
    description: 'Zoom MS-70CDR+',
  ),
  _PedalCatalogTarget(
    pedalKey: 'ms200dp',
    enumName: 'DeviceFamily.zoomMs200dPlus',
    constantName: 'zoomMs200dPlusCatalogData',
    jsonPath: 'tool/reference/zoom-effect-mappings-ms200dp.json',
    nameOverridePath: 'tool/reference/zoom-effect-ids-full-names-ms200dp.js',
    outputPath: 'lib/catalog/zoom_ms200d_plus_catalog_data.dart',
    description: 'Zoom MS-200D+',
  ),
];

/// Deterministic, pure-Dart catalog generator that ingests Zoom MS Plus JSON
/// mappings and JS/CSV name-override definitions to generate typed Dart catalogs
/// for MS-60B+, MS-50G+, MS-70CDR+, and MS-200D+.
void main(List<String> args) {
  if (args.isNotEmpty) {
    // Optional single-target mode:
    // dart run tool/generate_zoom_catalog.dart <input.json> [output.dart] [names.csv|names.js] [pedalKey]
    final inputPath = args[0];
    if (!File(inputPath).existsSync()) {
      stderr.writeln('Error: Could not locate input JSON at $inputPath');
      exit(1);
    }
    final outputPath = args.length > 1 ? args[1] : 'lib/catalog/zoom_ms60b_plus_catalog_data.dart';
    final overridePath = args.length > 2 ? args[2] : null;
    final pedalKey = args.length > 3 ? args[3] : _inferPedalKey(inputPath);
    final target = _targetForPedalKey(pedalKey, inputPath, outputPath, overridePath);
    final count = _generatePedalCatalog(target);
    stdout.writeln('Successfully generated $count effects for ${target.description} to ${target.outputPath}');
    return;
  }

  for (final target in _defaultTargets) {
    if (!File(target.jsonPath).existsSync()) {
      stderr.writeln('Error: Could not locate ${target.jsonPath}');
      exit(1);
    }
    final count = _generatePedalCatalog(target);
    stdout.writeln('Generated $count effects for ${target.description} -> ${target.outputPath}');
  }

  _writeUmbrellaCatalogFile('lib/catalog/zoom_ms_plus_catalog_data.dart');
  stdout.writeln('Updated umbrella export file -> lib/catalog/zoom_ms_plus_catalog_data.dart');
}

String _inferPedalKey(String path) {
  final lower = path.toLowerCase();
  if (lower.contains('ms50gp') || lower.contains('ms50g')) return 'ms50gp';
  if (lower.contains('ms70cdrp') || lower.contains('ms70cdr')) return 'ms70cdrp';
  if (lower.contains('ms200dp') || lower.contains('ms200d')) return 'ms200dp';
  return 'ms60bp';
}

_PedalCatalogTarget _targetForPedalKey(
  String pedalKey,
  String jsonPath,
  String outputPath,
  String? overridePath,
) {
  final base = _defaultTargets.firstWhere(
    (t) => t.pedalKey == pedalKey,
    orElse: () => _defaultTargets.first,
  );
  return _PedalCatalogTarget(
    pedalKey: base.pedalKey,
    enumName: base.enumName,
    constantName: base.constantName,
    jsonPath: jsonPath,
    nameOverridePath: overridePath ?? base.nameOverridePath,
    outputPath: outputPath,
    description: base.description,
  );
}

int _generatePedalCatalog(_PedalCatalogTarget target) {
  final jsonContent = File(target.jsonPath).readAsStringSync();
  final Map<String, dynamic> rawMap = json.decode(jsonContent) as Map<String, dynamic>;

  final Map<String, _NameOverride> overrides = {};
  if (target.nameOverridePath != null && File(target.nameOverridePath!).existsSync()) {
    overrides.addAll(_loadNameOverrides(target.nameOverridePath!));
  }

  final buffer = StringBuffer();
  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// Generated by tool/generate_zoom_catalog.dart from ${target.jsonPath}');
  buffer.writeln();
  buffer.writeln("import '../models/device_family.dart';");
  buffer.writeln("import '../models/parameter_descriptor.dart';");
  buffer.writeln("import '../protocols/catalogs/effect_catalog.dart';");
  buffer.writeln();
  buffer.writeln('/// Complete built-in effect catalog data for ${target.description}.');
  buffer.writeln('const List<EffectDefinition> ${target.constantName} = [');

  // Deterministic ordering by effect key
  final sortedKeys = rawMap.keys.toList()..sort();

  for (final key in sortedKeys) {
    final effectData = rawMap[key] as Map<String, dynamic>;
    final normalizedKey = key.toLowerCase().padLeft(8, '0');
    final override = overrides[normalizedKey];

    final name = override?.name ?? (effectData['name'] as String? ?? 'Unknown');
    final hexId = '0x${key.toUpperCase()}';
    final category = override?.category ?? _resolveCategory(key, name, target.pedalKey);
    final rawParams = (effectData['parameters'] as List<dynamic>?) ?? [];

    buffer.writeln('  EffectDefinition(');
    buffer.writeln('    effectId: "$hexId",');
    buffer.writeln('    name: ${_escapeString(name)},');
    buffer.writeln('    category: ${_escapeString(category)},');
    buffer.writeln('    deviceFamily: ${target.enumName},');
    buffer.writeln('    parameters: [');

    for (int pIdx = 0; pIdx < rawParams.length; pIdx++) {
      final pMap = rawParams[pIdx] as Map<String, dynamic>;
      final pName = pMap['name'] as String? ?? 'Param $pIdx';
      final cleanIdName = _sanitizeIdentifier(pName);
      final pId = '${cleanIdName}_$pIdx';
      final maxVal = (pMap['max'] as num?)?.toDouble() ?? 100.0;
      final defaultVal = (pMap['default'] as num?)?.toDouble() ?? 0.0;
      final rawVals = (pMap['values'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList();

      List<String>? cleanedVals;
      int detectedOffset = 0;
      bool hasCustomLabels = false;

      if (rawVals != null && rawVals.isNotEmpty) {
        cleanedVals = rawVals.map(_cleanValueString).toList();
        try {
          final ints = cleanedVals.map((s) => int.parse(s)).toList();
          final firstDiff = ints[0] - 0;
          bool allMatch = true;
          for (int i = 0; i < ints.length; i++) {
            if (ints[i] - i != firstDiff) {
              allMatch = false;
              break;
            }
          }
          if (allMatch) {
            detectedOffset = firstDiff;
          } else {
            hasCustomLabels = true;
          }
        } catch (_) {
          hasCustomLabels = true;
        }
      }

      buffer.writeln('      ParameterDescriptor(');
      buffer.writeln('        id: "$pId",');
      buffer.writeln('        name: ${_escapeString(pName)},');
      buffer.writeln('        min: 0,');
      buffer.writeln('        max: ${_formatDouble(maxVal)},');
      buffer.writeln('        defaultValue: ${_formatDouble(defaultVal)},');
      if (detectedOffset != 0) {
        buffer.writeln('        displayOffset: $detectedOffset,');
      }
      if (hasCustomLabels && cleanedVals != null && cleanedVals.isNotEmpty) {
        final labelItems = cleanedVals.map((s) => _escapeString(s)).join(', ');
        buffer.writeln('        labels: [$labelItems],');
        buffer.writeln('        valueLabels: [$labelItems],');
      }
      buffer.writeln('      ),');
    }

    buffer.writeln('    ],');
    buffer.writeln('  ),');
  }

  buffer.writeln('];');

  final outputFile = File(target.outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(buffer.toString());

  return sortedKeys.length;
}

void _writeUmbrellaCatalogFile(String outputPath) {
  final buffer = StringBuffer();
  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// Generated by tool/generate_zoom_catalog.dart');
  buffer.writeln();
  buffer.writeln("import '../protocols/catalogs/effect_catalog.dart';");
  buffer.writeln("import 'zoom_ms60b_plus_catalog_data.dart';");
  buffer.writeln();
  buffer.writeln("export 'zoom_ms50g_plus_catalog_data.dart';");
  buffer.writeln("export 'zoom_ms60b_plus_catalog_data.dart';");
  buffer.writeln("export 'zoom_ms70cdr_plus_catalog_data.dart';");
  buffer.writeln("export 'zoom_ms200d_plus_catalog_data.dart';");
  buffer.writeln();
  buffer.writeln('/// Backward-compatible alias for the Zoom MS-60B+ built-in effect catalog.');
  buffer.writeln('const List<EffectDefinition> zoomMsPlusCatalogData = zoomMs60bPlusCatalogData;');

  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buffer.toString());
}

/// Loads effect name (and optional category) overrides from either a `.csv` file
/// (`hexId,name[,category]`) or a `.js`/`.ts` ID-map (`0x01000010: "NAME"`).
Map<String, _NameOverride> _loadNameOverrides(String path) {
  final content = File(path).readAsStringSync();
  final lowerPath = path.toLowerCase();
  final result = <String, _NameOverride>{};

  if (lowerPath.endsWith('.csv')) {
    final lines = const LineSplitter().convert(content);
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final fields = _parseCsvRow(line);
      if (fields.length < 2) continue;
      final rawId = fields[0].trim().toLowerCase().replaceFirst('0x', '');
      if (rawId == 'id' || rawId == 'effect_id' || rawId == 'effectid') continue;
      if (!RegExp(r'^[0-9a-f]+$').hasMatch(rawId)) continue;
      final normalized = rawId.padLeft(8, '0');
      final name = fields[1].trim();
      final category = fields.length >= 3 && fields[2].trim().isNotEmpty
          ? fields[2].trim()
          : null;
      if (name.isNotEmpty) {
        result[normalized] = _NameOverride(name: name, category: category);
      }
    }
    return result;
  }

  // Parse JS/TS map entries: `0x01000010: "FAT BOOST",`
  final pattern = RegExp(r'0x([0-9a-fA-F]+)\s*:\s*"([^"]+)"');
  for (final match in pattern.allMatches(content)) {
    final normalized = match.group(1)!.toLowerCase().padLeft(8, '0');
    final name = match.group(2)!.trim();
    if (name.isNotEmpty) {
      result[normalized] = _NameOverride(name: name);
    }
  }
  return result;
}

List<String> _parseCsvRow(String row) {
  final fields = <String>[];
  final current = StringBuffer();
  bool inQuotes = false;

  for (int i = 0; i < row.length; i++) {
    final ch = row[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
        current.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  fields.add(current.toString());
  return fields;
}

String _resolveCategory(String hexKey, String name, String pedalKey) {
  final prefix = hexKey.substring(0, 2).toLowerCase();

  if (pedalKey == 'ms200dp') {
    switch (prefix) {
      case '01':
        return 'Boost / Drive';
      case '02':
        return 'Overdrive';
      case '03':
        return 'Distortion';
      case '04':
        return 'Fuzz';
      case '05':
        return 'Amp Model';
      case '06':
        final upperName = name.toUpperCase();
        if (upperName.contains('EQ')) {
          return 'Filter / EQ';
        }
        return 'Dynamics';
      case '07':
        return 'Special / SFX';
      case '1d':
        return 'Drive / Distortion';
      default:
        return 'Other';
    }
  }

  if (pedalKey == 'ms50gp' || pedalKey == 'ms70cdrp') {
    switch (prefix) {
      case '01':
        return 'Dynamics';
      case '02':
        return 'Filter / EQ';
      case '03':
        return 'Drive / Distortion';
      case '04':
        return 'Amp Model';
      case '05':
        return 'Amp Model';
      case '06':
        return 'Modulation';
      case '07':
        return 'Special / SFX';
      case '08':
        return 'Delay';
      case '09':
        return 'Reverb';
      default:
        return 'Other';
    }
  }

  // Default: MS-60B+
  switch (prefix) {
    case '01':
      return 'Dynamics';
    case '02':
      return 'Filter / EQ';
    case '03':
      return 'Drive / Distortion';
    case '04':
      return 'Preamp';
    case '05':
      return 'Amp Model';
    case '06':
      return 'Modulation';
    case '07':
      return 'Pitch / Octave';
    case '08':
      return 'Bass Synth';
    case '09':
      return 'Special / SFX';
    case '0a':
      return 'Delay';
    case '0b':
      return 'Reverb';
    default:
      return 'Other';
  }
}

String _sanitizeIdentifier(String name) {
  var s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  s = s.replaceAll(RegExp(r'^_|_$'), '');
  if (s.isEmpty) s = 'param';
  return s;
}

String _formatDouble(double val) {
  if (val == val.roundToDouble()) {
    return '${val.toInt()}.0';
  }
  return val.toString();
}

String _cleanValueString(String s) {
  var str = s.trim();
  str = str.replaceAll('&#119138;', '𝅚');
  str = str.replaceAll('&#119137;', '𝅙');
  str = str.replaceAll('&#119136;', '𝅘');
  str = str.replaceAll('&#119135;', '♩');
  str = str.replaceAll('&#119134;', '𝅗');
  return str;
}

String _escapeString(String str) {
  final escaped = str
      .replaceAll(r'\', r'\\')
      .replaceAll(r'"', r'\"')
      .replaceAll(r'$', r'\$');
  return '"$escaped"';
}
