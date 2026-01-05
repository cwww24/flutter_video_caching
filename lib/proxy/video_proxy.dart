import 'dart:io';

import 'package:flutter_hls_parser/flutter_hls_parser.dart';
import 'package:flutter_video_caching/http/http_client_default.dart';

import '../download/download_manager.dart';
import '../ext/file_ext.dart';
import '../global/config.dart';
import '../http/http_client_builder.dart';
import '../match/url_matcher.dart';
import '../match/url_matcher_default.dart';
import 'local_proxy_server.dart';

/// Manages the initialization and configuration of the local video proxy server,
/// HLS playlist parser, download manager, and URL matcher for video streaming and caching.
class VideoProxy {
  /// The local HTTP proxy server instance.
  static late LocalProxyServer _localProxyServer;

  /// HLS playlist parser instance for parsing HLS playlists.
  static late HlsPlaylistParser hlsPlaylistParser;

  /// Download manager instance for handling video segment downloads.
  static late DownloadManager downloadManager;

  /// URL matcher implementation for filtering and matching video URLs.
  static late UrlMatcher urlMatcherImpl;

  /// HTTP client builder for creating HTTP clients.
  static late HttpClientBuilder httpClientBuilderImpl;

  /// Initializes the video proxy server and related components.
  ///
  /// [ip]: Optional IP address for the proxy server to bind.<br>
  /// [port]: Optional port number for the proxy server to listen on.<br>
  /// [maxMemoryCacheSize]: Maximum memory cache size in MB (default: 100).<br>
  /// [maxStorageCacheSize]: Maximum storage cache size in MB (default: 1024).<br>
  /// [logPrint]: Enables or disables logging output (default: false).<br>
  /// [segmentSize]: Size of each video segment in MB (default: 2).<br>
  /// [maxConcurrentDownloads]: Maximum number of concurrent downloads (default: 8).<br>
  /// [cacheRootPath]: Optional custom root path for cache directory. If not provided, uses the default application cache directory.<br>
  /// [urlMatcher]: Optional custom URL matcher for video URL filtering.<br>
  /// [httpClientBuilder]: Optional custom HTTP client builder for creating HTTP clients.<br>
  static Future<void> init({
    String? ip,
    int? port,
    int maxMemoryCacheSize = 100,
    int maxStorageCacheSize = 1024 * 100,
    bool logPrint = false,
    int segmentSize = 2,
    int maxConcurrentDownloads = 8,
    String? cacheRootPath,
    UrlMatcher? urlMatcher,
    HttpClientBuilder? httpClientBuilder,
  }) async {
    // Set global configuration values for cache sizes and segment size.
    Config.memoryCacheSize = maxMemoryCacheSize * Config.mbSize;
    Config.storageCacheSize = maxStorageCacheSize * Config.mbSize;
    Config.segmentSize = segmentSize * Config.mbSize;

    // Set custom cache root path if provided.
    if (cacheRootPath != null && cacheRootPath.isNotEmpty) {
      FileExt.setCustomCacheRootPath(cacheRootPath);
    }

    // Enable or disable logging.
    Config.logPrint = logPrint;

    // Initialize and start the local proxy server.
    _localProxyServer = LocalProxyServer(ip: ip, port: port);
    await _localProxyServer.start();

    // Create the HLS playlist parser instance.
    hlsPlaylistParser = HlsPlaylistParser.create();

    // Initialize the download manager with the specified concurrency.
    downloadManager = DownloadManager(maxConcurrentDownloads);

    // Set the URL matcher implementation (custom or default).
    urlMatcherImpl = urlMatcher ?? UrlMatcherDefault();

    // Set the HTTP client builder
    httpClientBuilderImpl = httpClientBuilder ?? HttpClientDefault();
  }

  /// Returns a stream of exceptions that occur when the proxy server encounters errors
  /// or closes unexpectedly. Listeners can subscribe to this stream to be notified
  /// of proxy server issues.
  ///
  /// Example usage:
  /// ```dart
  /// VideoProxy.onError.listen((exception) {
  ///   print('Proxy server error: $exception');
  ///   // Handle the error, e.g., restart the proxy or notify the user
  /// });
  /// ```
  static Stream<Exception> get onError => _localProxyServer.onError;

  /// Tests whether the proxy server is running and accessible.
  ///
  /// This method attempts to connect to the proxy server and returns `true`
  /// if the connection is successful, `false` otherwise.
  ///
  /// [timeout]: Optional timeout duration for the connection test (default: 3 seconds).
  ///
  /// Returns `true` if the proxy server is accessible, `false` otherwise.
  ///
  /// Example usage:
  /// ```dart
  /// bool isWorking = await VideoProxy.testProxy();
  /// if (isWorking) {
  ///   print('Proxy server is running');
  /// } else {
  ///   print('Proxy server is not accessible');
  /// }
  /// ```
  static Future<bool> testProxy({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(
        Config.ip,
        Config.port,
        timeout: timeout,
      );
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Returns the current total number of proxy tasks (including all statuses).
  ///
  /// Example usage:
  /// ```dart
  /// int count = VideoProxy.getTaskCount();
  /// print('Current task count: $count');
  /// ```
  static int getTaskCount() {
    return downloadManager.taskCount;
  }

  /// Returns the current number of active (downloading) proxy tasks.
  ///
  /// Example usage:
  /// ```dart
  /// int activeCount = VideoProxy.getActiveTaskCount();
  /// print('Active task count: $activeCount');
  /// ```
  static int getActiveTaskCount() {
    return downloadManager.activeTaskCount;
  }

  /// Returns a stream of task count updates.
  /// Listeners will be notified whenever the number of tasks changes.
  ///
  /// Example usage:
  /// ```dart
  /// VideoProxy.taskCountStream.listen((count) {
  ///   print('Task count changed to: $count');
  /// });
  /// ```
  static Stream<int> get taskCountStream => downloadManager.taskCountStream;
}
