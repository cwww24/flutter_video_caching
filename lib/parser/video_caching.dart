import 'dart:async';
import 'dart:io';

import 'package:flutter_hls_parser/flutter_hls_parser.dart';

import '../download/download_cache_registry.dart';
import '../ext/log_ext.dart';
import '../ext/string_ext.dart';
import '../ext/uri_ext.dart';
import '../proxy/video_proxy.dart';
import 'url_parser.dart';
import 'url_parser_factory.dart';
import 'url_parser_m3u8.dart';

/// Provides video caching and parsing utilities for different video formats.
/// Supports parsing, caching, and pre-caching of video resources (e.g., MP4, HLS/M3U8).
class VideoCaching {
  /// Parses the given [uri] and handles the video request via the appropriate parser.
  ///
  /// [socket]: The client socket to send the response to.
  /// [uri]: The URI of the video resource to be parsed.
  /// [headers]: HTTP headers for the request.
  ///
  /// Returns a [Future] that completes when the parsing and response are done.
  static Future<void> parse(
    Socket socket,
    Uri uri,
    Map<String, String> headers,
  ) async {
    await UrlParserFactory.createParser(uri).parse(socket, uri, headers);
  }

  /// Whether the video is cached.
  ///
  /// [url]: The video URL to check.
  /// [headers]: Optional HTTP headers to use for the request.
  /// [cacheSegments]: Number of segments to cache.
  ///
  /// Returns `true` if the video is cached, otherwise `false`.
  static Future<bool> isCached(
    String url, {
    Map<String, Object>? headers,
    int cacheSegments = 2,
  }) {
    return UrlParserFactory.createParser(url.toSafeUri())
        .isCached(url, headers, cacheSegments);
  }

  /// Pre-caches the video at the specified [url].
  ///
  /// [url]: The video URL to be pre-cached.
  /// [headers]: Optional HTTP headers for the request.
  /// [cacheSegments]: Number of segments to cache (default: 2).
  /// [downloadNow]: If true, downloads segments immediately; if false, pushes to the queue (default: true).
  /// [progressListen]: If true, returns a [StreamController] with progress updates (default: false).
  ///
  /// Returns a [StreamController] emitting progress/status updates, or `null` if not listening.
  static Future<StreamController<Map>?> precache(
    String url, {
    Map<String, Object>? headers,
    int cacheSegments = 2,
    bool downloadNow = true,
    bool progressListen = false,
  }) {
    return UrlParserFactory.createParser(url.toSafeUri())
        .precache(url, headers, cacheSegments, downloadNow, progressListen);
  }

  /// Pre-caches the given [url] by byte size.
  ///
  /// [cacheBytes]: Target bytes to cache (default ~500KB).
  /// [concurrent]: Maximum concurrent chunk downloads.
  /// [downloadNow]: Whether to download immediately or enqueue.
  /// [progressListen]: Whether to listen to progress events.
  static Future<StreamController<Map>?> precacheByte(
    String url, {
    Map<String, Object>? headers,
    int cacheBytes = 500 * 1024,
    int concurrent = 1,
    int maxQueueTasks = 3,
    bool downloadNow = true,
    bool progressListen = false,
  }) async {
    final String key = url.toSafeUri().toString();
    final registry = DownloadCacheRegistry();
    if (!registry.startPrecacheByte(key)) {
      logD('[VideoProxy] precacheByte skip duplicate: $url');
      return null;
    }
    try {
      if (cacheBytes <= 0) cacheBytes = 500 * 1024;
      if (concurrent <= 0) concurrent = 1;
      return await UrlParserFactory.createParser(url.toSafeUri()).precacheByte(
        url,
        headers,
        cacheBytes,
        concurrent,
        maxQueueTasks,
        downloadNow,
        progressListen,
      );
    } finally {
      registry.finishPrecacheByte(key);
    }
  }

  /// Parses the HLS master playlist from the given [url].
  ///
  /// [url]: The URL of the HLS master playlist.
  /// [headers]: Optional HTTP headers for the request.
  ///
  /// Returns an [HlsMasterPlaylist] instance if successful, otherwise returns `null`.
  static Future<HlsMasterPlaylist?> parseHlsMasterPlaylist(
    String url, {
    Map<String, Object>? headers,
  }) async {
    Uri uri = url.toSafeUri();
    UrlParser parser = UrlParserFactory.createParser(uri);
    if (parser is! UrlParserM3U8) return null;
    HlsPlaylist? playlist = await parser.parsePlaylist(uri,
        headers: headers, hlsKey: uri.generateMd5);
    return playlist is HlsMasterPlaylist ? playlist : null;
  }

  /// Cancels all download tasks related to the specified video URL.
  ///
  /// This method stops all ongoing downloads for a video, including:
  /// - Tasks matching the exact URL
  /// - Tasks matching the cache key (matchUrl) for MP4 segments
  /// - Tasks matching the HLS key for HLS segments
  ///
  /// [url]: The video URL to cancel all related tasks for.
  /// [headers]: Optional HTTP headers used for matching tasks (for custom cache ID).
  ///
  /// This is useful when a video player is closed and you want to stop
  /// all background downloads for that video.
  static void cancelVideoTasks(String url, {Map<String, Object>? headers}) {
    VideoProxy.downloadManager.cancelVideoTasks(url, headers: headers);
  }

  /// Returns the current total number of proxy tasks (including all statuses).
  ///
  /// Example usage:
  /// ```dart
  /// int count = VideoCaching.getTaskCount();
  /// print('Current task count: $count');
  /// ```
  static int getTaskCount() {
    return VideoProxy.getTaskCount();
  }

  /// Returns the current number of active (downloading) proxy tasks.
  ///
  /// Example usage:
  /// ```dart
  /// int activeCount = VideoCaching.getActiveTaskCount();
  /// print('Active task count: $activeCount');
  /// ```
  static int getActiveTaskCount() {
    return VideoProxy.getActiveTaskCount();
  }

  /// Returns a stream of task count updates.
  /// Listeners will be notified whenever the number of tasks changes.
  ///
  /// Example usage:
  /// ```dart
  /// VideoCaching.taskCountStream.listen((count) {
  ///   print('Task count changed to: $count');
  /// });
  /// ```
  static Stream<int> get taskCountStream => VideoProxy.taskCountStream;

  /// Returns cached video information snapshot.
  static Future<List<CachedVideoInfo>> getCachedVideos() {
    return DownloadCacheRegistry().snapshot();
  }
}
