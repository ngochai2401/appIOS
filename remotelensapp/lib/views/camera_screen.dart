import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:remotelens_app/models/signaling_message.dart';
import 'package:remotelens_app/services/connectivity_service.dart';
import 'package:remotelens_app/viewmodels/call_controller.dart';

class CameraScreen extends StatefulWidget {
  final String? connectionCode;
  final CallController c;

  const CameraScreen({super.key, this.connectionCode, required this.c});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isFrontCamera = false;
  bool _isFlashOn = false;
  bool _isRecording = false;
  bool _isBusy = false;
  double _currentZoom = 1.0;

  @override
  void initState() {
    super.initState();
    widget.c.addListener(_refresh);
    widget.c.onRemoteCommand = _handleRemoteCommand;
    widget.c.onKicked = (msg) => _showMessage(msg);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.c.onRoomExpired = null;
    widget.c.removeListener(_refresh);
    widget.c.onKicked = null;
    if (widget.c.onRemoteCommand == _handleRemoteCommand) {
      widget.c.onRemoteCommand = null;
    }
    super.dispose();
  }

  bool get _hasLocalStream {
    return widget.c.webrtc.localRenderer.srcObject != null;
  }

  bool get _isConnected {
    final state = widget.c.stateText.toLowerCase();
    return state.contains('connected') ||
        widget.c.webrtc.remoteRenderer.srcObject != null;
  }

  String get _displayCode {
    if (widget.connectionCode != null && widget.connectionCode!.isNotEmpty) {
      return widget.connectionCode!;
    }
    return widget.c.roomId ?? '---';
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dừng chia sẻ?'),
        content: const Text('Bạn có muốn dừng chia sẻ camera không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dừng'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _switchCamera() async {
    try {
      await widget.c.webrtc.switchCamera();

      if (!mounted) return;
      setState(() {
        _isFrontCamera = !_isFrontCamera;
        if (_isFrontCamera) {
          _isFlashOn = false;
        }
      });

      _showMessage('Đã đổi camera');
    } catch (e) {
      _showMessage('Không đổi được camera: $e');
    }
  }

  Future<void> _toggleFlash() async {
    try {
      if (_isFrontCamera) {
        _showMessage('Flash chỉ dùng được với camera sau');
        return;
      }

      final supported = await widget.c.webrtc.hasTorch();
      if (!supported) {
        _showMessage('Thiết bị hoặc track này không hỗ trợ flash');
        return;
      }

      await widget.c.webrtc.setTorch(!_isFlashOn);

      if (!mounted) return;
      setState(() {
        _isFlashOn = !_isFlashOn;
      });

      _showMessage(_isFlashOn ? 'Đã bật flash' : 'Đã tắt flash');
    } catch (e) {
      _showMessage('Bật/tắt flash thất bại: $e');
    }
  }

  Future<void> _startRecord() async {
    try {
      if (_isRecording) return;
      if (!_hasLocalStream) {
        _showMessage('Camera chưa sẵn sàng để quay');
        return;
      }

      setState(() {
        _isRecording = true;
      });

      _showMessage('Đã nhận lệnh bắt đầu quay');
    } catch (e) {
      _showMessage('Bắt đầu quay thất bại: $e');
    }
  }

  Future<void> _stopRecord() async {
    try {
      if (!_isRecording) return;

      setState(() {
        _isRecording = false;
      });

      _showMessage('Đã nhận lệnh dừng quay');
    } catch (e) {
      _showMessage('Dừng quay thất bại: $e');
    }
  }

  Future<void> _handleRemoteCommand(SignalingMessage msg) async {
    if (_isBusy) return;

    try {
      _isBusy = true;

      switch (msg.type) {
        case 'start_record':
          await _startRecord();
          break;

        case 'stop_record':
          await _stopRecord();
          break;

        case 'toggle_flash':
          await _toggleFlash();
          break;

        case 'switch_camera':
          await _switchCamera();
          break;

        case 'zoom_set':
          final raw = msg.payload?['zoom'];
          final zoom = raw is num ? raw.toDouble() : double.tryParse('$raw');

          if (zoom != null) {
            await _setZoom(zoom);
          } else {
            _showMessage('Payload zoom không hợp lệ');
          }
          break;

        case 'zoom_reset':
          await _resetZoom();
          break;
      }
    } catch (e) {
      _showMessage('Xử lý lệnh thất bại: $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _setZoom(double value) async {
    try {
      await widget.c.webrtc.setZoom(value);

      if (!mounted) return;
      setState(() {
        _currentZoom = widget.c.webrtc.zoomLevel;
      });

      _showMessage('Zoom: ${_currentZoom.toStringAsFixed(1)}x');
    } catch (e) {
      _showMessage('$e');
    }
  }

  Future<void> _resetZoom() async {
    try {
      await widget.c.webrtc.resetZoom();

      if (!mounted) return;
      setState(() {
        _currentZoom = widget.c.webrtc.zoomLevel;
      });

      _showMessage('Đã reset zoom');
    } catch (e) {
      _showMessage('$e');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final localRenderer = widget.c.webrtc.localRenderer;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _confirmExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: _hasLocalStream
                  ? RTCVideoView(
                      localRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      mirror: _isFrontCamera,
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.cyan),
                    ),
            ),

            _buildCameraGrid(),

            Positioned(
              top: 48,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Flexible(flex: 4, child: _buildConnectionStatus()),
                  const SizedBox(width: 10),
                  Flexible(flex: 3, child: _buildConnectionCode()),
                ],
              ),
            ),

            Positioned(
              top: 110,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Zoom ${_currentZoom.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            if (!_isConnected)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.cyan),
                      const SizedBox(height: 16),
                      const Text(
                        'Đang chờ Monitor kết nối...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'State: ${widget.c.stateText}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Center(child: _buildAudioMeter()),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 20,
                      left: 30,
                      right: 30,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBottomButton(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          onTap: _toggleFlash,
                        ),
                        _buildBottomButton(
                          Icons.cameraswitch_outlined,
                          onTap: _switchCamera,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_isRecording)
              Positioned(
                top: 110,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fiber_manual_record,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraGrid() {
    return Column(
      children: [
        Expanded(child: Container(decoration: _gridBorder(bottom: true))),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: _gridBorder(right: true, bottom: true),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: _gridBorder(right: true, bottom: true),
                ),
              ),
              Expanded(child: Container(decoration: _gridBorder(bottom: true))),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: Container(decoration: _gridBorder(right: true))),
              Expanded(child: Container(decoration: _gridBorder(right: true))),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _gridBorder({bool right = false, bool bottom = false}) {
    final lineColor = Colors.white.withOpacity(0.25);
    return BoxDecoration(
      border: Border(
        right: right ? BorderSide(color: lineColor, width: 1) : BorderSide.none,
        bottom: bottom
            ? BorderSide(color: lineColor, width: 1)
            : BorderSide.none,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.orangeAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _isConnected ? 'ĐÃ KẾT NỐI' : 'ĐANG CHỜ MONITOR',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCode() {
    return GestureDetector(
      onTap: () {
        _showMessage('Mã kết nối: $_displayCode');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.cyan.withOpacity(0.15),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.cyan, width: 1.5),
        ),
        child: Text(
          'MÃ: $_displayCode',
          style: const TextStyle(
            color: Colors.cyan,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioMeter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, color: Colors.cyan, size: 16),
          SizedBox(width: 12),
          Text('-12dB', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBottomButton(IconData icon, {VoidCallback? onTap}) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 24),
        onPressed: onTap,
      ),
    );
  }
}
