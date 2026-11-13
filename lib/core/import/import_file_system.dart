import 'dart:io';
import 'dart:typed_data';

import '../export/export_file_writer.dart';

/// Lightweight metadata entry for a file or directory in [ImportFileSystem].
class ImportFsEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;

  const ImportFsEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedAt,
  });
}

/// Named shortcut directory shown in the file browser quick-locations bar.
class ImportQuickLocation {
  final String label;
  final String path;

  const ImportQuickLocation({
    required this.label,
    required this.path,
  });
}

/// Pure-Dart filesystem abstraction enabling deterministic in-memory widget tests
/// without unguarded `dart:io` disk access.
abstract class ImportFileSystem {
  const ImportFileSystem();

  String get pathSeparator;
  Future<String> resolveDefaultImportDirectory();
  Future<List<ImportQuickLocation>> getQuickLocations();
  Future<bool> directoryExists(String path);
  Future<bool> fileExists(String path);
  Future<String?> parentDirectory(String path);
  Future<List<ImportFsEntry>> listDirectory(
    String path, {
    Set<String>? allowedExtensions,
  });
  Future<Uint8List> readFileBytes(String path);

  /// Extracts the basename from [path] across POSIX and Windows separators.
  static String baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final idx = trimmed.lastIndexOf('/');
    return idx == -1 ? trimmed : trimmed.substring(idx + 1);
  }

  /// Returns true if [fileName] ends with any extension in [allowedExtensions].
  static bool matchesAllowedExtension(
    String fileName,
    Set<String>? allowedExtensions,
  ) {
    if (allowedExtensions == null || allowedExtensions.isEmpty) return true;
    final lower = fileName.toLowerCase();
    return allowedExtensions.any((ext) => lower.endsWith(ext.toLowerCase()));
  }
}

/// Production `dart:io` implementation of [ImportFileSystem].
class LocalImportFileSystem extends ImportFileSystem {
  const LocalImportFileSystem();

  @override
  String get pathSeparator => Platform.pathSeparator;

  static String _resolveDocumentsDirectoryPath() {
    if (Platform.isLinux) {
      final xdgDocs = Platform.environment['XDG_DOCUMENTS_DIR'];
      if (xdgDocs != null && xdgDocs.isNotEmpty) {
        return xdgDocs;
      }
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return '$home/Documents';
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ??
          Platform.environment['APPDATA'] ??
          Directory.systemTemp.path;
      return '$userProfile\\Documents';
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return '$home/Documents';
    } else if (Platform.isAndroid) {
      const androidDownloads = '/storage/emulated/0/Download';
      if (Directory(androidDownloads).existsSync()) {
        return androidDownloads;
      }
      return Directory.systemTemp.path;
    }
    return Directory.systemTemp.path;
  }

  static String _resolveHomeDirectoryPath() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ??
          Platform.environment['APPDATA'] ??
          Directory.systemTemp.path;
    }
    return Platform.environment['HOME'] ?? Directory.systemTemp.path;
  }

  @override
  Future<String> resolveDefaultImportDirectory() async {
    final exportsDir = ExportFileWriter.resolveDefaultExportDirectory();
    if (await exportsDir.exists()) {
      return exportsDir.path;
    }
    final docsPath = _resolveDocumentsDirectoryPath();
    if (await Directory(docsPath).exists()) {
      return docsPath;
    }
    final homePath = _resolveHomeDirectoryPath();
    if (await Directory(homePath).exists()) {
      return homePath;
    }
    return Directory.systemTemp.path;
  }

  @override
  Future<List<ImportQuickLocation>> getQuickLocations() async {
    final locations = <ImportQuickLocation>[];
    final seen = <String>{};

    void addIfUnique(String label, String path) {
      if (seen.add(path)) {
        locations.add(ImportQuickLocation(label: label, path: path));
      }
    }

    addIfUnique(
      'SignalChainExports',
      ExportFileWriter.resolveDefaultExportDirectory().path,
    );
    addIfUnique('Documents', _resolveDocumentsDirectoryPath());
    addIfUnique('Home', _resolveHomeDirectoryPath());
    return locations;
  }

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<String?> parentDirectory(String path) async {
    final dir = Directory(path);
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    return parent.path;
  }

  @override
  Future<List<ImportFsEntry>> listDirectory(
    String path, {
    Set<String>? allowedExtensions,
  }) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw FileSystemException('Directory does not exist', path);
    }

    final entries = <ImportFsEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = ImportFileSystem.baseName(entity.path);
      if (name.startsWith('.')) continue;

      if (entity is Directory) {
        entries.add(ImportFsEntry(
          name: name,
          path: entity.path,
          isDirectory: true,
        ));
      } else if (entity is File) {
        if (!ImportFileSystem.matchesAllowedExtension(name, allowedExtensions)) {
          continue;
        }
        try {
          final stat = await entity.stat();
          entries.add(ImportFsEntry(
            name: name,
            path: entity.path,
            isDirectory: false,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ));
        } catch (_) {
          entries.add(ImportFsEntry(
            name: name,
            path: entity.path,
            isDirectory: false,
          ));
        }
      }
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', path);
    }
    return file.readAsBytes();
  }
}

/// Deterministic in-memory [ImportFileSystem] for unit and widget tests.
class InMemoryImportFileSystem extends ImportFileSystem {
  final String defaultDir;
  final String documentsDir;
  final String homeDir;
  final Set<String> _directories = {};
  final Map<String, Uint8List> _files = {};

  InMemoryImportFileSystem({
    this.defaultDir = '/memory/Documents/SignalChainExports',
    this.documentsDir = '/memory/Documents',
    this.homeDir = '/memory',
    Map<String, Uint8List>? initialFiles,
    Iterable<String>? initialDirectories,
  }) {
    _ensureParentDirs(homeDir);
    _ensureParentDirs(documentsDir);
    _ensureParentDirs(defaultDir);
    if (initialDirectories != null) {
      for (final dir in initialDirectories) {
        addDirectory(dir);
      }
    }
    if (initialFiles != null) {
      for (final entry in initialFiles.entries) {
        addFile(entry.key, entry.value);
      }
    }
  }

  @override
  String get pathSeparator => '/';

  static String _normalize(String path) {
    final replaced = path.replaceAll('\\', '/');
    if (replaced.length > 1 && replaced.endsWith('/')) {
      return replaced.substring(0, replaced.length - 1);
    }
    return replaced.isEmpty ? '/' : replaced;
  }

  void _ensureParentDirs(String dirPath) {
    var current = _normalize(dirPath);
    while (current.isNotEmpty) {
      _directories.add(current);
      if (current == '/') break;
      final idx = current.lastIndexOf('/');
      if (idx <= 0) {
        _directories.add('/');
        break;
      }
      current = current.substring(0, idx);
    }
  }

  /// Registers a directory (and its ancestor directories) in memory.
  void addDirectory(String path) {
    _ensureParentDirs(path);
  }

  /// Registers a file at [path] with [bytes], creating parent directories automatically.
  void addFile(String path, Uint8List bytes) {
    final normalized = _normalize(path);
    final idx = normalized.lastIndexOf('/');
    if (idx > 0) {
      _ensureParentDirs(normalized.substring(0, idx));
    } else {
      _directories.add('/');
    }
    _files[normalized] = Uint8List.fromList(bytes);
  }

  @override
  Future<String> resolveDefaultImportDirectory() async {
    if (await directoryExists(defaultDir)) return defaultDir;
    if (await directoryExists(documentsDir)) return documentsDir;
    return homeDir;
  }

  @override
  Future<List<ImportQuickLocation>> getQuickLocations() async => [
        ImportQuickLocation(label: 'SignalChainExports', path: defaultDir),
        ImportQuickLocation(label: 'Documents', path: documentsDir),
        ImportQuickLocation(label: 'Home', path: homeDir),
      ];

  @override
  Future<bool> directoryExists(String path) async =>
      _directories.contains(_normalize(path));

  @override
  Future<bool> fileExists(String path) async =>
      _files.containsKey(_normalize(path));

  @override
  Future<String?> parentDirectory(String path) async {
    final normalized = _normalize(path);
    if (normalized == '/' || !normalized.contains('/')) return null;
    final idx = normalized.lastIndexOf('/');
    if (idx <= 0) return '/';
    return normalized.substring(0, idx);
  }

  @override
  Future<List<ImportFsEntry>> listDirectory(
    String path, {
    Set<String>? allowedExtensions,
  }) async {
    final normalized = _normalize(path);
    if (!_directories.contains(normalized)) {
      throw FileSystemException('Directory does not exist', path);
    }

    final prefix = normalized == '/' ? '/' : '$normalized/';
    final entries = <ImportFsEntry>[];

    for (final dir in _directories) {
      if (dir == normalized || !dir.startsWith(prefix)) continue;
      final rest = dir.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      entries.add(ImportFsEntry(
        name: rest,
        path: dir,
        isDirectory: true,
      ));
    }

    for (final entry in _files.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rest = entry.key.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      if (!ImportFileSystem.matchesAllowedExtension(rest, allowedExtensions)) {
        continue;
      }
      entries.add(ImportFsEntry(
        name: rest,
        path: entry.key,
        isDirectory: false,
        sizeBytes: entry.value.length,
      ));
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    final normalized = _normalize(path);
    final bytes = _files[normalized];
    if (bytes == null) {
      throw FileSystemException('File does not exist', path);
    }
    return Uint8List.fromList(bytes);
  }
}

