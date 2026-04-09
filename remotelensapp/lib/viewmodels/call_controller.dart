import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:remotelens_app/models/signaling_message.dart';
import 'package:remotelens_app/services/connectivity_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

enum CallRole { master, viewer }

class CallController extends ChangeNotifier {
  final SignalingService signaling;
  final WebRtcService webrtc;
  final ConnectivityService connectivity;

  CallController({
    required this.signaling,
    required this.webrtc,
    required this.connectivity,
  });

  String? roomId;
  String? selfId;
  CallRole? role;

  String _stateText = 'idle';
  String get stateText => _stateText;
  VoidCallback? onRoomExpired;
  DateTime _lastPing = DateTime.now();
  Timer? _heartbeatTimer;

  String get prettyState {
    final s = _stateText.toLowerCase();
    if (s.contains('reconnecting')) return 'Đang kết nối lại...';
    if (s.contains('disconnected')) return 'Mất kết nối';
    if (s.contains('failed')) return 'Kết nối thất bại';
    if (s.contains('closed')) return 'Đã đóng kết nối';
    if (s.contains('connecting')) return 'Đang kết nối...';
    if (s.contains('connected')) return 'Đã kết nối';
    if (s.contains('waiting-viewer')) return 'Đang chờ viewer...';
    if (s.contains('viewer-ready')) return 'Viewer sẵn sàng';
    return _stateText;
  }

  StreamSubscription? _signalSub;
  StreamSubscription? _iceSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _wsConnectedSub;

  bool _localMediaOpened = false;
  bool _offerSent = false;
  bool _isReconnecting = false;
  bool _initialized = false;
  Completer<void>? _joinCompleter;

  static const int _autoExitSeconds = 20; // Thời gian tự thoát (giây)
  VoidCallback? isEndTime;
  Timer? _disconnectTimer;

  Future<void> Function(SignalingMessage msg)? onRemoteCommand;
  void Function(String message)? onKicked;

  Future<void> init({
    required String signalingUrl,
    required String roomId,
    required String selfId,
    required CallRole role,
  }) async {
    this.roomId = roomId;
    this.selfId = selfId;
    this.role = role;

    _joinCompleter = Completer<void>();

    await signaling.connect(signalingUrl);
    await webrtc.init();

    _signalSub = signaling.messages.listen(_onSignal);
    _listenIceCandidate();

    _stateSub = webrtc.onConnectionState.listen((state) {
      _stateText = state.name;
      debugPrint('PC STATE = $state');

      // Mất kết nối
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        debugPrint("DISCONNECTED → start timer");
        _offerSent = false;
        webrtc.remoteRenderer.srcObject = null;
        _stateText = 'reconnecting';
        _startDisconnectTimer();
      }
      //Close
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _offerSent = false;
        webrtc.remoteRenderer.srcObject = null;
        _startDisconnectTimer();
      }
      //KẾT NỐI LẠI OK
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        debugPrint("✅ CONNECTED → cancel timer");

        _cancelDisconnectTimer();
      }

      notifyListeners();
    });

    _wsConnectedSub = signaling.onConnected.listen((_) async {
      if (!_initialized) return;
      debugPrint('WS reconnected → gửi join');
      await softReconnect();
    });

    _connectivitySub = connectivity.connectionStream.listen((
      hasInternet,
    ) async {
      debugPrint('NETWORK: hasInternet=$hasInternet');
      if (hasInternet) {
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        if (!isConnected && !_isReconnecting) {
          debugPrint('Mạng bật lại → trigger reconnect');
          await Future.delayed(const Duration(milliseconds: 1000));
          await signaling.reconnect();
          await softReconnect(); // thêm 31/03 cải thiện reconnect
        }
      } else if (!hasInternet) {
        if (_disconnectTimer == null || !_disconnectTimer!.isActive) {
          _disconnectTimer = Timer(Duration(seconds: _autoExitSeconds), () {
            isEndTime?.call();
          });
        }
      }
    });

    signaling.send(
      SignalingMessage(
        type: 'join',
        roomId: roomId,
        senderId: selfId,
        role: role == CallRole.master ? "master" : "viewer",
      ),
    );

    if (role == CallRole.viewer) {
      await _joinCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception(
          'Không nhận được phản hồi từ server. \n Hãy xem lại bạn bật wifi chưa?',
        ),
      );
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> softReconnect() async {
    if (_isReconnecting) return;
    if (roomId == null || selfId == null || role == null) return;

    _isReconnecting = true;
    debugPrint('REJOIN as ${role!.name}...');

    try {
      await webrtc.recreatePeerConnection();
      _localMediaOpened = false;

      await webrtc.openLocalMedia(audio: true, video: role == CallRole.master);
      _localMediaOpened = true;

      _listenIceCandidate();

      _offerSent = false;
      _stateText = role == CallRole.master ? 'waiting-viewer' : 'viewer-ready';
      notifyListeners();

      if (!signaling.isConnected) {
        debugPrint('WS chưa sẵn sàng, chờ _wsConnectedSub retry...');
        return;
      }
      signaling.send(
        SignalingMessage(
          type: 'join',
          roomId: roomId!,
          senderId: selfId!,
          role: role == CallRole.master ? 'master' : 'viewer',
        ),
      );
    } catch (e) {
      debugPrint('_rejoin error: $e');
    } finally {
      _isReconnecting = false;
    }
  }

  void _startDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = Timer(Duration(seconds: _autoExitSeconds), () {
      debugPrint("🔥 AUTO EXIT TRIGGERED");
      isEndTime?.call();
    });
  }

  void _cancelDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
  }

  void _listenIceCandidate() {
    _iceSub?.cancel();
    _iceSub = webrtc.onIceCandidate.listen((c) {
      if (roomId == null || selfId == null) return;
      signaling.send(
        SignalingMessage(
          type: 'ice-candidate',
          roomId: roomId!,
          senderId: selfId!,
          role: role == CallRole.master ? "master" : "viewer",
          payload: {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        ),
      );
    });
  }

  Future<void> startMaster() async {
    if (_localMediaOpened) return;
    await webrtc.openLocalMedia(audio: true, video: true);
    _localMediaOpened = true;
    _stateText = 'waiting-viewer';
    notifyListeners();
  }

  Future<void> startViewer() async {
    if (_localMediaOpened) return;
    await webrtc.openLocalMedia(audio: true, video: false);
    _localMediaOpened = true;
    _stateText = 'viewer-ready';
    notifyListeners();
  }

  Future<void> _sendOfferIfNeeded() async {
    if (role != CallRole.master || !_localMediaOpened || _offerSent) return;

    final offer = await webrtc.createOffer();
    signaling.send(
      SignalingMessage(
        type: 'offer',
        roomId: roomId!,
        senderId: selfId!,
        role: "master",
        payload: {'sdp': offer.sdp, 'type': offer.type},
      ),
    );
    _offerSent = true;
    debugPrint('MASTER: offer sent');
  }

  void sendCommand({required String type, Map<String, dynamic>? payload}) {
    if (roomId == null || selfId == null) return;
    signaling.send(
      SignalingMessage(
        type: type,
        roomId: roomId!,
        senderId: selfId!,
        role: role == CallRole.master ? "master" : "viewer",
        payload: payload ?? {},
      ),
    );
  }

  void _startHeartbeatWatch() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final lost = DateTime.now().difference(_lastPing).inSeconds > 10;
      if (lost) {
        webrtc.isPeerConnected.value = false; // dùng đúng tên của bạn
      }
    });
  }

  Future<void> leaveRoom() async {
    if (roomId != null && selfId != null) {
      signaling.send(
        SignalingMessage(
          type: 'leave',
          roomId: roomId!,
          senderId: selfId!,
          role: role == CallRole.master ? 'master' : 'viewer',
        ),
      );
    }
    await disposeAll();
  }

  bool get hasRemoteStream => webrtc.remoteRenderer.srcObject != null;

  bool get isConnected {
    final s = _stateText.toLowerCase();
    return (s.contains('connected') &&
            !s.contains('disconnected') &&
            !s.contains('failed') &&
            !s.contains('closed') &&
            !s.contains('reconnecting')) ||
        hasRemoteStream;
  }

  Future<void> _onSignal(SignalingMessage msg) async {
    if (msg.roomId != roomId || msg.senderId == selfId) return;

    switch (msg.type) {
      case 'peer-joined':
        if (role == CallRole.master) {
          _offerSent = false;
          await webrtc.recreatePeerConnection();
          _localMediaOpened = false;
          await webrtc.openLocalMedia(audio: true, video: true);
          _localMediaOpened = true;
          _listenIceCandidate();
          await _sendOfferIfNeeded();
        }
        break;

      case 'offer':
      case 'answer':
      case 'ice-candidate':
      case 'joined':
      case 'error':
        // Giữ nguyên logic cũ của bạn
        if (msg.type == 'offer' && role == CallRole.viewer) {
          if (!_localMediaOpened) {
            await webrtc.openLocalMedia(audio: true, video: false);
            _localMediaOpened = true;
          }
          await webrtc.setRemoteDescription(
            msg.payload!['sdp'] as String,
            msg.payload!['type'] as String,
          );
          final answer = await webrtc.createAnswer();
          signaling.send(
            SignalingMessage(
              type: 'answer',
              roomId: roomId!,
              senderId: selfId!,
              role: "viewer",
              payload: {'sdp': answer.sdp, 'type': answer.type},
            ),
          );
        } else if (msg.type == 'answer' && role == CallRole.master) {
          await webrtc.setRemoteDescription(
            msg.payload!['sdp'] as String,
            msg.payload!['type'] as String,
          );
        } else if (msg.type == 'ice-candidate') {
          final payload = msg.payload!;
          final dynamic rawIndex = payload['sdpMLineIndex'];
          await webrtc.addCandidate(
            payload['candidate'] as String,
            payload['sdpMid'] as String?,
            rawIndex is int ? rawIndex : int.tryParse(rawIndex.toString()),
          );
        } else if (msg.type == 'joined' &&
            role == CallRole.viewer &&
            _joinCompleter != null &&
            !_joinCompleter!.isCompleted) {
          _joinCompleter!.complete();
          _startHeartbeatWatch();
        } else if (msg.type == 'error' &&
            role == CallRole.viewer &&
            _joinCompleter != null &&
            !_joinCompleter!.isCompleted) {
          _joinCompleter!.completeError(
            Exception(msg.payload?['message']?.toString() ?? 'Lỗi server'),
          );
        }
        break;

      case 'room-expired':
        _stateText = 'room-expired';
        notifyListeners();
        onRoomExpired?.call();
        break;

      case 'peer-left':
        final reason = msg.payload?['reason'] ?? 'normal';
        final message = msg.payload?['message'] ?? 'Kết nối bị ngắt';

        debugPrint('PEER LEFT: ${msg.senderId} - Reason: $reason');

        if (reason == 'timeout' || reason == 'kicked' || reason == 'closed') {
          _stateText = 'peer-disconnected';

          if (role == CallRole.viewer && onKicked != null) {
            onKicked!(message); // ← Monitor nhận thông báo
          } else if (role == CallRole.master && onRemoteCommand != null) {
            onRemoteCommand!(
              SignalingMessage(
                type: 'show_toast',
                payload: {
                  'message': 'Monitor đã ngắt kết nối',
                  'duration': 2500,
                },
              ),
            );
          }
        } else {
          _stateText = 'peer-left';
          if (onRemoteCommand != null) {
            onRemoteCommand!(
              SignalingMessage(
                type: 'show_toast',
                payload: {'message': message, 'duration': 3000},
              ),
            );
          }
        }
        notifyListeners();
        break;
      case 'ping':
        _lastPing = DateTime.now();
        break;

      case 'capture_photo':
      case 'start_record':
      case 'stop_record':
      case 'toggle_flash':
      case 'switch_camera':
      case 'zoom_set':
      case 'zoom_reset':
        if (role == CallRole.master && onRemoteCommand != null) {
          await onRemoteCommand!(msg);
        }
        break;
    }
  }

  Future<void> disposeAll() async {
    _disconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _signalSub?.cancel();
    await _iceSub?.cancel();
    await _stateSub?.cancel();
    await _connectivitySub?.cancel();
    await _wsConnectedSub?.cancel();
    await signaling.dispose();
    await webrtc.dispose();
  }

  @override
  void dispose() {
    disposeAll();
    super.dispose();
  }
}
