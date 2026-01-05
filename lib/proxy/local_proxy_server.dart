import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../ext/log_ext.dart';
import '../ext/socket_ext.dart';
import '../ext/string_ext.dart';
import '../global/config.dart';
import '../parser/video_caching.dart';

/// A local HTTP proxy server implementation.
/// Listens on a specified IP and port, accepts incoming socket connections,
/// parses HTTP requests, and delegates video caching logic.
class LocalProxyServer {
  /// Constructor for LocalProxyServer.
  /// Optionally accepts an IP and port to bind the server.
  LocalProxyServer({this.ip, this.port}) {
    // Set global config values if provided.
    Config.ip = ip ?? Config.ip;
    Config.port = port ?? Config.port;
    _errorController = StreamController<Exception>.broadcast();
  }

  /// Proxy Server IP address.
  final String? ip;

  /// Proxy Server port number.
  final int? port;

  /// The underlying server socket instance.
  ServerSocket? server;

  /// Stream controller for broadcasting server errors.
  StreamController<Exception>? _errorController;

  /// Stream of server errors for listeners to subscribe to.
  /// Listeners will be notified when the proxy server encounters an error or closes unexpectedly.
  Stream<Exception> get onError => _errorController?.stream ?? const Stream.empty();

  /// Starts the proxy server.
  /// Binds to the configured IP and port, and listens for incoming connections.
  /// If the port is already in use, it will try the next port.
  Future<void> start() async {
    try {
      final InternetAddress internetAddress = InternetAddress(Config.ip);
      server = await ServerSocket.bind(internetAddress, Config.port);
      logD('Proxy server started ${server?.address.address}:${server?.port}');
      if (server == null) {
        retry();
      } else {
        startHealthCheck();
        server?.listen(
          _handleConnection,
          onError: (error) {
            logW('Proxy server error: $error');
            _errorController?.add(Exception('Proxy server error: $error'));
            retry();
          },
          onDone: () {
            logW('Proxy server closed');
            _errorController?.add(Exception('Proxy server closed unexpectedly'));
            retry();
          },
        );
      }
    } on SocketException catch (e) {
      logW('Proxy server Socket close: $e');
      _errorController?.add(e);
      // If the port is occupied (error code 98), increment port and retry.
      if (e.osError?.errorCode == 98) {
        Config.port = Config.port + 1;
        start();
      } else {
        retry();
      }
    } catch (e) {
      logW('Proxy server start error: $e');
      _errorController?.add(Exception('Proxy server start error: $e'));
      retry();
    }
  }

  Timer? _healthCheckTimer;

  void startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        final socket = await Socket.connect(
          Config.ip,
          Config.port,
          timeout: Duration(seconds: 1),
        );
        socket.destroy();
        logD('Proxy server health check pass...');
      } catch (e) {
        logW('Server seems down: $e');
        _errorController?.add(Exception('Proxy server health check failed: $e'));
        retry();
      }
    });
  }

  void retry() {
    logD('Proxy server restarting...');
    server?.close();
    Future.delayed(Duration(seconds: 1), start);
  }

  /// Shuts down the proxy server and closes the socket.
  Future<void> close() async {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    await server?.close();
    await _errorController?.close();
    _errorController = null;
  }

  /// Handles an incoming socket connection.
  /// Reads data from the socket, parses the HTTP request,
  /// extracts method, path, protocol, and headers,
  /// and delegates further processing to VideoCaching.
  Future<void> _handleConnection(Socket socket) async {
    final DateTime startTime = DateTime.now();
    bool logged = false;
    try {
      logV('_handleConnection start');
      StringBuffer buffer = StringBuffer();
      // Read data from the socket stream.
      await for (Uint8List data in socket) {
        buffer.write(String.fromCharCodes(data));

        // Wait until the end of HTTP headers (\r\n\r\n) is detected.
        if (!buffer.toString().contains(httpTerminal)) continue;

        // Extract raw HTTP headers.
        String? rawHeaders = buffer.toString().split(httpTerminal).firstOrNull;
        List<String> lines = rawHeaders?.split('\r\n') ?? <String>[];

        // Parse the request line (e.g., GET /path HTTP/1.1).
        List<String>? requestLine = lines.firstOrNull?.split(' ') ?? <String>[];
        String method = requestLine.isNotEmpty ? requestLine[0] : '';
        String path = requestLine.length > 1 ? requestLine[1] : '/';
        String protocol = requestLine.length > 2 ? requestLine[2] : 'HTTP/1.1';

        // Parse HTTP headers into a map.
        Map<String, String> headers = <String, String>{};
        for (String line in lines.skip(1)) {
          int index = line.indexOf(':');
          if (index > 0) {
            String key = line.substring(0, index).trim().toLowerCase();
            String value = line.substring(index + 1).trim();
            headers[key] = value;
          }
        }

        // If no headers are found, send a 400 Bad Request response.
        if (headers.isEmpty) {
          await send400(socket);
          return;
        }

        // Convert the path to a Uri object.
        // Support both absolute URI format (http://host/path) and relative path format
        Uri originUri;
        if (path.startsWith('http://') || path.startsWith('https://')) {
          // Absolute URI format (proxy-style request)
          originUri = path.toSafeUri();
        } else {
          // Relative path format - try to restore from origin param or build from Host header
          String originUrl = path.toOriginUrl();
          if (originUrl == path && !path.startsWith('http')) {
            // No origin param found, try to build from Host header
            String? host = headers['host'];
            if (host != null && host.isNotEmpty) {
              // Build full URL from Host header
              String scheme = headers.containsKey('x-forwarded-proto') 
                  ? headers['x-forwarded-proto']! 
                  : 'http';
              originUrl = '$scheme://$host$path';
              originUri = originUrl.toSafeUri();
            } else {
              // Fallback to original behavior
              originUri = path.toOriginUri();
            }
          } else {
            originUri = originUrl.toSafeUri();
          }
        }
        logD('Handling Connections ============>'  'protocol: $protocol, method: $method, path: $path ''headers: $headers ' 'originUri: $originUri');

        // Clean headers: remove proxy server's Host header to avoid conflicts
        // when requesting local network servers. HttpClient will automatically
        // set the correct Host header from the URI, so we should remove
        // any Host header that points to the proxy server itself.
        Map<String, String> cleanedHeaders = Map<String, String>.from(headers);
        String? hostHeader = cleanedHeaders['host'];
        if (hostHeader != null) {
          // Check if Host header points to proxy server
          bool isProxyHost = hostHeader == Config.serverUrl ||
              hostHeader == '${Config.ip}:${Config.port}' ||
              (hostHeader == Config.ip && originUri.host != Config.ip);
          
          // If Host header points to proxy server, remove it
          // Otherwise, keep it if it matches the target server (for local network)
          if (isProxyHost) {
            cleanedHeaders.remove('host');
          } else {
            // Verify the Host header matches the target URI
            // If not, remove it to let HttpClient set it correctly
            String expectedHost = originUri.hasPort 
                ? '${originUri.host}:${originUri.port}'
                : originUri.host;
            if (hostHeader != expectedHost && hostHeader != originUri.host) {
              cleanedHeaders.remove('host');
            }
          }
        }
        // Also remove other proxy-related headers that might interfere
        cleanedHeaders.remove('x-forwarded-host');
        cleanedHeaders.remove('x-forwarded-for');

        // Delegate request handling to VideoCaching.
        await VideoCaching.parse(socket, originUri, cleanedHeaders);
        if (!logged) {
          logged = true;
          final int cost =
              DateTime.now().difference(startTime).inMilliseconds;
          logI('[VideoProxy] request success ${originUri.toString()} '
              'cost:${cost}ms');
        }
        break;
      }
    } catch (e) {
      logW('⚠ ⚠ ⚠ Socket connections close: $e');
    } finally {
      // Ensure the socket is closed after handling.
      await socket.close();
    }
  }

  /// Sends a 400 Bad Request HTTP response to the client.
  Future<void> send400(Socket socket) async {
    logD('HTTP/1.1 400 Bad Request');
    final String headers = <String>[
      'HTTP/1.1 400 Bad Request',
      'Content-Type: text/plain',
      'Bad Request'
    ].join(httpTerminal);
    await socket.append(headers);
  }
}
