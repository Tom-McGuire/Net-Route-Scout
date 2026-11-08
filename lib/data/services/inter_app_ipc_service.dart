import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class InterAppIpcService {
  static const int routeScoutIpcPort = 44101;
  static const int arpScoutIpcPort = 44102;

  static ServerSocket? _serverSocket;

  /// Starts listening for IPC messages on the given loopback port.
  static Future<ServerSocket?> startListener(
    int port,
    void Function(Map<String, dynamic> payload) onPayload,
  ) async {
    try {
      // Close previous instance if any
      await stopListener();

      _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: false);
      _serverSocket!.listen(
        (socket) {
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;
              try {
                final decoded = jsonDecode(trimmed);
                if (decoded is Map<String, dynamic>) {
                  onPayload(decoded);
                } else if (decoded is Map) {
                  onPayload(Map<String, dynamic>.from(decoded));
                }
              } catch (e) {
                debugPrint('IPC parse error: $e');
              }
            },
            onError: (e) => debugPrint('IPC socket stream error: $e'),
          );
        },
        onError: (e) => debugPrint('IPC server socket error: $e'),
      );
      debugPrint('InterAppIpcService listening on port $port');
      return _serverSocket;
    } catch (e) {
      debugPrint('Could not bind IPC port $port: $e');
      return null;
    }
  }

  /// Sends a JSON payload to a local loopback port with a short timeout.
  /// Returns true if successfully delivered.
  static Future<bool> sendCommand({
    required int port,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: timeout);
      final jsonLine = '${jsonEncode(payload)}\n';
      socket.write(jsonLine);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      try {
        socket?.destroy();
      } catch (_) {}
      return false;
    }
  }

  /// Stops and closes the active loopback socket listener.
  static Future<void> stopListener() async {
    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;
  }
}
