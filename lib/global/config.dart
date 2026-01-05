import 'package:flutter/foundation.dart';

/// A global configuration class for application-wide settings.
class Config {
  /// Indicates whether the app is running in debug mode.
  static const bool isDebug = kDebugMode;

  /// Controls whether log output is enabled.
  /// Can be toggled at runtime.
  static bool logPrint = false;

  /// The server IP address used for network requests.
  static String ip = '127.0.0.1';

  /// The server port used for network requests.
  static int port = 20250;

  /// Returns the server URL in the format "ip:port".
  static String get serverUrl => "$ip:$port";

  /// The size of one megabyte in bytes.
  static int mbSize = 1000 * 1000;

  /// The size of one gigabyte in bytes.
  static int gbSize = 1000 * mbSize;

  /// The maximum size for in-memory cache (in bytes).
  /// Default is 100MB.
  static int memoryCacheSize = 100 * mbSize; // 100MB

  /// The maximum size for storage cache (in bytes).
  /// Default is 1GB.
  static int storageCacheSize = 1 * gbSize; // 1GB

  /// The size of each data segment (in bytes) for chunked operations.
  static int segmentSize = 2000000;

  /// The size of the first segment (in bytes) for faster video startup.
  /// This is typically smaller than [segmentSize] to reduce initial buffering time.
  /// Default is the same as [segmentSize]. Set to a smaller value (e.g., 500KB) for faster startup.
  static int firstSegmentSize = 2000000;

  /// A custom cache identifier string.
  static String customCacheId = 'Custom-Cache-ID';
}
