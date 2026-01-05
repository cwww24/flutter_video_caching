import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A utility class for handling cache file operations, such as
/// creating cache directories and deleting them.
class FileExt {
  /// Stores the root path of the cache directory.
  static String _cacheRootPath = "";

  /// Custom cache root path set by the user. If set, this will be used instead of the default application cache directory.
  static String? _customCacheRootPath;

  /// Sets a custom root path for the cache directory.
  ///
  /// [path]: The custom root path to use for caching. If null or empty, the default application cache directory will be used.
  ///
  /// Example usage:
  /// ```dart
  /// FileExt.setCustomCacheRootPath('/storage/emulated/0/VideoCache');
  /// ```
  static void setCustomCacheRootPath(String? path) {
    _customCacheRootPath = path;
    _cacheRootPath = ""; // Reset cached path to force re-initialization
  }

  /// Creates and returns the path to the cache directory.
  ///
  /// If [cacheDir] is provided and not empty, it will be appended
  /// to the root cache path. The method ensures the directory exists,
  /// creating it recursively if necessary.
  ///
  /// Returns a [Future] that completes with the cache directory path.
  static Future<String> createCachePath([String? cacheDir]) async {
    String rootPath = _cacheRootPath;
    // Initialize the root path if it is empty.
    if (rootPath.isEmpty) {
      if (_customCacheRootPath != null && _customCacheRootPath!.isNotEmpty) {
        rootPath = _customCacheRootPath!;
      } else {
        rootPath = (await getApplicationCacheDirectory()).path;
      }
      _cacheRootPath = rootPath;
    }
    // Append 'videos' to the root path.
    rootPath = '$rootPath/videos';
    // Append the custom cache directory if provided.
    if (cacheDir != null && cacheDir.isNotEmpty) {
      rootPath = '$rootPath/$cacheDir';
    }
    // Create the directory if it does not exist.
    if (Directory(rootPath).existsSync()) return rootPath;
    Directory(rootPath).createSync(recursive: true);
    return rootPath;
  }

  /// Deletes a specific cache directory by its [key].
  ///
  /// If the root cache path is not initialized, the method does nothing.
  /// The deletion is recursive.
  static Future<void> deleteCacheDirByKey(String key) async {
    if (_cacheRootPath.isEmpty && _customCacheRootPath == null) return;
    String rootPath = _cacheRootPath.isNotEmpty 
        ? _cacheRootPath 
        : (_customCacheRootPath ?? '');
    if (rootPath.isEmpty) return;
    await Directory('$rootPath/videos/$key').delete(recursive: true);
  }

  /// Deletes the default cache directory.
  ///
  /// If the root cache path is not initialized, the method does nothing.
  /// The deletion is recursive.
  static Future<void> deleteDefaultCacheDir() async {
    if (_cacheRootPath.isEmpty && _customCacheRootPath == null) return;
    String rootPath = _cacheRootPath.isNotEmpty 
        ? _cacheRootPath 
        : (_customCacheRootPath ?? '');
    if (rootPath.isEmpty) return;
    await Directory('$rootPath/videos').delete(recursive: true);
  }

  /// Returns the current root path of the cache directory.
  static String get cacheRootPath => _cacheRootPath;
}
