import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/signaling_message.dart';

class SignalingService {
  WebSocketChannel? _channel;
  late String _url;

  bool _isConnecting = false;
  bool _disposed = false;
  bool _wsConnected = false;

  Timer? _reconnectTimer;

  final StreamController<SignalingMessage> _messageCtrl =
      StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get messages => _messageCtrl.stream;

  final StreamController<void> _connectedCtrl =
      StreamController<void>.broadcast();
  Stream<void> get onConnected => _connectedCtrl.stream;

  bool get isConnected => _wsConnected;

  Future<void> connect(String url) async {
    if (_isConnecting || _disposed) return;
    if (_wsConnected) return; // ✅ đã connected thì bỏ qua
    _isConnecting = true;
    _url = url;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      debugPrint('WS CONNECTING...');
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      await channel.ready;

      _wsConnected = true;
      debugPrint('WS CONNECTED: $url');

      if (!_disposed) {
        try {
          _connectedCtrl.add(null);
        } catch (_) {}
      }

      channel.stream.listen(
        (event) {
          try {
            final map = jsonDecode(event.toString()) as Map<String, dynamic>;
            _messageCtrl.add(SignalingMessage.fromJson(map));
          } catch (e) {
            debugPrint('WS PARSE ERROR: $e');
          }
        },
        onError: (e) {
          debugPrint('WS ERROR: $e');
          _wsConnected = false;
          if (!_disposed) _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WS CLOSED');
          _wsConnected = false;
          if (!_disposed) _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('WS CONNECT ERROR: $e');
      _wsConnected = false;
      if (!_disposed) _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;

    debugPrint('WS schedule reconnect sau 3s...');
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_disposed || _wsConnected) return;
      await connect(_url);
    });
  }

  Future<void> reconnect() async {
    debugPrint('WS MANUAL RECONNECT...');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wsConnected = false;
    await _safeClose();
    await connect(_url);
  }

  void send(SignalingMessage message) {
    if (!_wsConnected) {
      debugPrint('WS NOT CONNECTED → skip send');
      return;
    }
    final json = jsonEncode(message.toJson());
    debugPrint('WS SEND: $json');
    _channel?.sink.add(json);
  }

  Future<void> _safeClose() async {
    _wsConnected = false;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _safeClose();
    try {
      await _messageCtrl.close();
    } catch (_) {}
    try {
      await _connectedCtrl.close();
    } catch (_) {}
  }
}
