import 'dart:io';

import '../cache/lru_cache_singleton.dart';
import 'download_status.dart';
import 'download_task.dart';

/// Tracks download cache progress and provides cache snapshots.
class DownloadCacheRegistry {
  DownloadCacheRegistry._();

  static final DownloadCacheRegistry _instance = DownloadCacheRegistry._();

  factory DownloadCacheRegistry() => _instance;

  /// Active precacheByte keys to avoid duplicate enqueue.
  final Set<String> _precacheByteKeys = {};

  /// Cached video info keyed by matchUrl.
  final Map<String, CachedVideoInfo> _cacheInfo = {};

  /// Maps matchUrl to original url for quick lookup.
  final Map<String, String> _urlByKey = {};

  /// Try to mark a precacheByte run. Returns false if the same key is already running.
  bool startPrecacheByte(String key) {
    if (_precacheByteKeys.contains(key)) return false;
    _precacheByteKeys.add(key);
    return true;
  }

  /// Finish a precacheByte run for the given key.
  void finishPrecacheByte(String key) {
    _precacheByteKeys.remove(key);
  }

  /// Update registry from a download task message.
  void updateFromTask(DownloadTask task) {
    final String key = task.matchUrl;
    _urlByKey[key] = task.url;
    final int cachedBytes = task.status.isCompleted
        ? (task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes)
        : task.downloadedBytes;
    final CachedVideoInfo newInfo = CachedVideoInfo(
      key: key,
      url: task.url,
      startRange: task.startRange,
      endRange: task.endRange,
      cachedBytes: cachedBytes,
      totalBytes: task.totalBytes,
      cacheDir: task.cacheDir,
    );
    _cacheInfo[key] = newInfo.mergeWith(_cacheInfo[key]);
  }

  /// Returns current cached video info merged with on-disk snapshot.
  Future<List<CachedVideoInfo>> snapshot() async {
    final Map<String, CachedVideoInfo> result = Map.of(_cacheInfo);
    final map = DownloadCacheRegistry._storageMapSafe();
    for (final entry in map.entries) {
      final key = entry.key;
      final file = entry.value;
      if (file is! File) continue;
      final stat = await file.stat();
      result[key] = CachedVideoInfo(
        key: key,
        url: _urlByKey[key] ?? key,
        startRange: result[key]?.startRange ?? 0,
        endRange: result[key]?.endRange,
        cachedBytes: stat.size,
        totalBytes: result[key]?.totalBytes ?? stat.size,
        cacheDir: file.parent.path,
      ).mergeWith(result[key]);
    }
    return result.values.toList();
  }

  static Map<String, FileSystemEntity> _storageMapSafe() {
    try {
      return LruCacheSingleton().storageMap();
    } catch (_) {
      return {};
    }
  }
}

/// Cached video metadata.
class CachedVideoInfo {
  final String key;
  final String url;
  final int startRange;
  final int? endRange;
  final int cachedBytes;
  final int totalBytes;
  final String? cacheDir;

  const CachedVideoInfo({
    required this.key,
    required this.url,
    required this.startRange,
    required this.endRange,
    required this.cachedBytes,
    required this.totalBytes,
    this.cacheDir,
  });

  CachedVideoInfo mergeWith(CachedVideoInfo? other) {
    if (other == null) return this;
    return CachedVideoInfo(
      key: key,
      url: url.isNotEmpty ? url : other.url,
      startRange: startRange,
      endRange: endRange ?? other.endRange,
      cachedBytes: cachedBytes > 0 ? cachedBytes : other.cachedBytes,
      totalBytes: totalBytes > 0 ? totalBytes : other.totalBytes,
      cacheDir: cacheDir ?? other.cacheDir,
    );
  }

  Map<String, Object?> toMap() => {
        'key': key,
        'url': url,
        'startRange': startRange,
        'endRange': endRange,
        'cachedBytes': cachedBytes,
        'totalBytes': totalBytes,
        'cacheDir': cacheDir,
      };
}

extension _DownloadStatusCheck on DownloadStatus {
  bool get isCompleted =>
      this == DownloadStatus.COMPLETED || this == DownloadStatus.FINISHED;
}

