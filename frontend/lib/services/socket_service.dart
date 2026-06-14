import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects to the combined_asl_live.py WebSocket server.
/// - Device A: registers its session ID with the Python server on connect.
/// - Device B: receives the stored session ID automatically on connect.
class SocketService {
  static const int _wsPort = 8765;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  String _host = 'localhost';

  void setHost(String host) {
    _host = host.trim().isEmpty ? 'localhost' : host.trim();
  }

  String get wsUrl => 'ws://$_host:$_wsPort';
  bool get isDeviceB => _host != 'localhost';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  // Called when a sign is detected (Device A)
  void Function(String sign, double confidence, String source)? _onSign;

  // Called when Python relays Device A's session ID (Device B auto-join)
  void Function(String sessionId)? onSessionInfo;

  // Called when a new camera frame arrives as base64 JPEG string
  void Function(String base64Jpeg)? onFrame;

  // Called when Python relays a screen_switch command from the other device
  void Function(String screen)? onScreenSwitch;

  // Device A provides its session ID to register with the Python server
  String? _mySessionId;

  bool _manuallyDisconnected = false;

  void connect(
    void Function(String sign, double confidence, String source) onSign, {
    String? mySessionId,
  }) {
    _onSign = onSign;
    _mySessionId = mySessionId;
    _manuallyDisconnected = false;
    _tryConnect();
  }

  Future<void> _tryConnect() async {
    if (_manuallyDisconnected) return;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
      print('[SocketService] Connected to $wsUrl');

      // Device A: register session ID with Python server so Device B gets it
      if (!isDeviceB && _mySessionId != null && _mySessionId!.isNotEmpty) {
        _channel!.sink.add(jsonEncode({
          'type': 'session_register',
          'session_id': _mySessionId,
        }));
        print('[SocketService] Registered session: $_mySessionId');
      }

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (err) {
          print('[SocketService] Stream error: $err');
          _scheduleReconnect();
        },
        onDone: () {
          print('[SocketService] Connection closed — reconnecting...');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('[SocketService] Could not connect: $e');
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;

      // ── Camera frame (base64 JPEG) from Python ─────────────────
      if (data['type'] == 'frame') {
        final b64 = data['data'] as String? ?? '';
        if (b64.isNotEmpty && onFrame != null) {
          onFrame!(b64);
        }
        return;
      }

      // ── Screen switch relay from Python ─────────────────────────
      if (data['type'] == 'screen_switch') {
        final screen = data['screen'] as String? ?? '';
        if (screen.isNotEmpty && onScreenSwitch != null) {
          print('[SocketService] screen_switch received: $screen');
          onScreenSwitch!(screen);
        }
        return;
      }

      // ── Session relay message from Python (Device B receives this) ──
      if (data['type'] == 'session_info') {
        final sid = data['session_id'] as String? ?? '';
        if (sid.isNotEmpty && onSessionInfo != null) {
          print('[SocketService] Received session_info: $sid');
          onSessionInfo!(sid);
        }
        return;
      }

      // ── Normal sign detection message ───────────────────────────
      final sign       = data['sign']       as String? ?? '';
      final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
      final source     = data['source']     as String? ?? '';

      if (sign.isNotEmpty && _onSign != null) {
        _onSign!(sign, confidence, source);
      }
    } catch (e) {
      print('[SocketService] Failed to parse message: $e  raw=$raw');
    }
  }

  /// Send a screen switch command — Python will relay it to all other clients.
  /// [screen] should be "input" or "output".
  void sendScreenSwitch(String screen) {
    try {
      _channel?.sink.add(jsonEncode({'type': 'screen_switch', 'screen': screen}));
      print('[SocketService] Sent screen_switch: $screen');
    } catch (e) {
      print('[SocketService] sendScreenSwitch error: $e');
    }
  }

  void _scheduleReconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (_manuallyDisconnected) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _tryConnect);
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    print('[SocketService] Disconnected.');
  }
}
