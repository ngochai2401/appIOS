import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final StreamController<RTCIceCandidate> _iceCtrl =
      StreamController<RTCIceCandidate>.broadcast();
  Stream<RTCIceCandidate> get onIceCandidate => _iceCtrl.stream;

  final StreamController<RTCPeerConnectionState> _stateCtrl =
      StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get onConnectionState => _stateCtrl.stream;

  final StreamController<MediaStream?> _remoteStreamCtrl =
      StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onRemoteStream => _remoteStreamCtrl.stream;

  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;
  bool _zoomSupported = true;

  double get zoomLevel => _zoomLevel;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  bool get zoomSupported => _zoomSupported;

  final ValueNotifier<bool> isPeerConnected = ValueNotifier(false);

  bool _disposed = false;
  bool _renderersInitialized = false;

  Future<void> init() async {
    _disposed = false;

    if (!_renderersInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    }

    await _createPeerConnection();
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun.cloudflare.com:3478'},
      ],
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onIceCandidate = (candidate) {
      debugPrint('LOCAL ICE: ${candidate.candidate}');
      if (_disposed) return;
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        try {
          _iceCtrl.add(candidate);
        } catch (_) {}
      }
    };

    _peerConnection!.onTrack = (event) async {
      if (_disposed) return;

      debugPrint(
        'onTrack fired: kind=${event.track.kind} streams=${event.streams.length}',
      );

      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('remote');
        _remoteStream!.addTrack(event.track);
      }

      remoteRenderer.srcObject = _remoteStream;
      debugPrint('remoteRenderer assigned: ${_remoteStream?.id}');

      try {
        _remoteStreamCtrl.add(_remoteStream);
      } catch (_) {}
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('PC STATE = $state');
      if (_disposed || state == null) return;

      try {
        _stateCtrl.add(state);
      } catch (_) {}

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        isPeerConnected.value = true;
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        isPeerConnected.value = false;
        try {
          remoteRenderer.srcObject = null;
          _remoteStream = null;
          _remoteStreamCtrl.add(null);
        } catch (_) {}
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('ICE STATE = $state');
      if (_disposed || state == null) return;

      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        isPeerConnected.value = true;
      } else if (state ==
              RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        isPeerConnected.value = false;
      }
    };

    _peerConnection!.onIceGatheringState = (state) {
      debugPrint('ICE GATHERING STATE = $state');
    };

    _peerConnection!.onSignalingState = (state) {
      debugPrint('SIGNALING STATE = $state');
    };

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        debugPrint('re-addTrack on new peer: ${track.kind}');
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }
  }

  Future<void> openLocalMedia({
    required bool audio,
    required bool video,
  }) async {
    if (_localStream != null) {
      debugPrint('openLocalMedia skipped: local stream already exists');
      return;
    }
    final constraints = {
      'audio': audio,
      'video': video
          ? {
              'facingMode': 'environment',
              // ==================== ĐÃ TỐI ƯU CHO RECORD + PLAYBACK ====================
              'width': {'ideal': 640, 'min': 480},
              'height': {'ideal': 480, 'min': 360},
              'frameRate': {'ideal': 15, 'max': 15},
              'aspectRatio': 16 / 9,
            }
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    localRenderer.srcObject = _localStream;
    // Cho renderer init xong trước khi WebRTC bắt đầu consume
    await Future.delayed(const Duration(milliseconds: 300));
    if (_peerConnection != null) {
      for (final track in _localStream!.getTracks()) {
        debugPrint('addTrack: ${track.kind}');
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }
    _zoomLevel = 1.0;
    _minZoom = 1.0;
    _maxZoom = 4.0;
    _zoomSupported = true;
    debugPrint('🎥 Camera constraints applied: 1280x720 @ 30fps');
  }

  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);
    debugPrint('createOffer done');
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(answer);
    debugPrint('createAnswer done');
    return answer;
  }

  Future<void> setRemoteDescription(String sdp, String type) async {
    debugPrint('setRemoteDescription: $type');

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );

    _remoteDescriptionSet = true;

    for (final c in _pendingCandidates) {
      debugPrint('flush pending ICE: ${c.candidate}');
      await _peerConnection!.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  Future<void> addCandidate(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    final ice = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);

    if (!_remoteDescriptionSet) {
      debugPrint('Queue ICE: $candidate');
      _pendingCandidates.add(ice);
      return;
    }

    debugPrint('addCandidate: $candidate');
    await _peerConnection!.addCandidate(ice);
  }

  MediaStreamTrack? get _videoTrack {
    final tracks = _localStream?.getVideoTracks() ?? [];
    return tracks.isEmpty ? null : tracks.first;
  }

  Future<void> setZoom(double value) async {
    final track = _videoTrack;
    if (track == null) throw Exception('Không tìm thấy video track để zoom');

    final newZoom = value.clamp(_minZoom, _maxZoom).toDouble();

    try {
      await track.applyConstraints({
        'advanced': [
          {'zoom': newZoom},
        ],
      });
      _zoomLevel = newZoom;
      _zoomSupported = true;
      debugPrint('ZOOM SET: $_zoomLevel');
    } on UnimplementedError {
      _zoomSupported = false;
      throw Exception('Thiết bị/plugin hiện chưa hỗ trợ zoom WebRTC');
    } catch (e) {
      _zoomSupported = false;
      throw Exception('Zoom không được hỗ trợ: $e');
    }
  }

  Future<void> zoomIn([double step = 0.2]) async => setZoom(_zoomLevel + step);
  Future<void> zoomOut([double step = 0.2]) async => setZoom(_zoomLevel - step);
  Future<void> resetZoom() async => setZoom(_minZoom);

  Future<void> switchCamera() async {
    final track = _videoTrack;
    if (track == null) return;
    await Helper.switchCamera(track);
  }

  Future<bool> hasTorch() async {
    final track = _videoTrack;
    if (track == null) return false;
    return track.hasTorch();
  }

  Future<void> setTorch(bool enabled) async {
    final track = _videoTrack;
    if (track == null)
      throw Exception('Không tìm thấy video track để bật flash');
    await track.setTorch(enabled);
  }

  Future<void> recreatePeerConnection() async {
    debugPrint('recreatePeerConnection called');

    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    isPeerConnected.value = false;

    try {
      remoteRenderer.srcObject = null;
      _remoteStreamCtrl.add(null);
    } catch (_) {}

    try {
      await _peerConnection?.close();
    } catch (_) {}
    try {
      await _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;
    _remoteStream = null;

    try {
      for (final track in _localStream?.getTracks() ?? []) {
        track.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    localRenderer.srcObject = null;

    await _createPeerConnection();
  }

  Future<void> dispose() async {
    _disposed = true;
    isPeerConnected.value = false;

    try {
      _remoteStreamCtrl.add(null);
    } catch (_) {}

    try {
      for (final track in _localStream?.getTracks() ?? []) {
        track.stop();
      }
    } catch (_) {}

    try {
      for (final track in _remoteStream?.getTracks() ?? []) {
        track.stop();
      }
    } catch (_) {}

    try {
      await _peerConnection?.close();
    } catch (_) {}
    try {
      await _peerConnection?.dispose();
    } catch (_) {}
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
    try {
      await _iceCtrl.close();
    } catch (_) {}
    try {
      await _stateCtrl.close();
    } catch (_) {}
    try {
      await _remoteStreamCtrl.close();
    } catch (_) {}
  }
}
