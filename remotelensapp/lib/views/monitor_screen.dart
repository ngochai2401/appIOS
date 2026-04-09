import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';

import 'package:remotelens_app/models/captured_media.dart';
import 'package:remotelens_app/viewmodels/call_controller.dart';
import 'package:remotelens_app/viewmodels/monitor_controller.dart';
import 'package:remotelens_app/views/preview_screen.dart';

class MonitorScreen extends StatefulWidget {
  final String masterCode;
  final CallController c;

  const MonitorScreen({super.key, required this.masterCode, required this.c});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final TransformationController _transformController =
      TransformationController();

  @override
  void initState() {
    super.initState();

    // Xử lý khi bị kick hoặc camera ngắt kết nối
    widget.c.onKicked = (message) {
      if (!mounted) return;
      _showDisconnectDialog(message);
    };

    widget.c.onRoomExpired = () {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Phòng đã hết hạn'),
          content: const Text(
            'Phòng đã bị xoá do mất kết nối quá lâu.\nVui lòng quay lại và kết nối lại.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Đồng ý'),
            ),
          ],
        ),
      );
    };
    widget.c.isEndTime = () {
      _showDisconnectDialog("Đường truyền kết nối của bạn có vấn đề...");
    };
  }

  void _showDisconnectDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Camera đã ngắt kết nối'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.c.onKicked = null;
    widget.c.onRoomExpired = null;
    _transformController.dispose();
    super.dispose();
  }

  Future<void> confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngắt kết nối?'),
        content: const Text('Bạn có muốn ngắt kết nối khỏi camera không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ngắt'),
          ),
        ],
      ),
    );

    if (shouldExit == true && context.mounted) {
      await widget.c.leaveRoom();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mc = Get.put(
      MonitorController(
        callController: widget.c,
        masterCode: widget.masterCode,
      ),
      tag: widget.masterCode,
    );

    final RTCVideoRenderer remoteRenderer = widget.c.webrtc.remoteRenderer;
    const Color appCyan = Color(0xFF00E5FF);

    // Trạng thái kết nối hoàn chỉnh
    final bool isFullyConnected = mc.isConnected && mc.hasRemoteStream;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await confirmExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GetBuilder<MonitorController>(
          tag: widget.masterCode,
          builder: (_) {
            return Stack(
              children: [
                // ==================== VIDEO STREAM ====================
                Positioned.fill(
                  child: RepaintBoundary(
                    key: mc.repaintKey,
                    child: Container(
                      color: Colors.black,
                      child: mc.hasRemoteStream
                          ? InteractiveViewer(
                              transformationController: _transformController,
                              panEnabled: true,
                              scaleEnabled: true,
                              minScale: 1.0,
                              maxScale: 5.0,
                              // transformationController tự repaint, không cần setState.
                              child: RTCVideoView(
                                remoteRenderer,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),

                // ==================== OVERLAY LOADING / MẤT KẾT NỐI ====================
                if (!isFullyConnected)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.85),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.cyan,
                              strokeWidth: 6,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              widget.c.stateText.toLowerCase().contains(
                                    'reconnecting',
                                  )
                                  ? 'Đang kết nối lại camera...'
                                  : mc.isConnected
                                  ? 'Đang chờ hình từ camera...'
                                  : 'Mất kết nối, đang thử kết nối lại...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.c.prettyState,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ==================== THANH TRẠNG THÁI TRÊN CÙNG ====================
                Positioned(
                  top: 38,
                  left: 16,
                  // right: 16,
                  child: _buildConnectionStatus(
                    isConnected: isFullyConnected,
                    stateText: widget.c.stateText,
                  ),
                ),
                // ==================== CONTROLS ====================
                if (isFullyConnected)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        child: Obx(() {
                          final duration = mc.recordingDuration.value;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ==================== TIMER KHI ĐANG QUAY ====================
                              if (mc.isRecording.value)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.fiber_manual_record,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${duration.inMinutes.toString().padLeft(2, '0')}:'
                                        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 8),

                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Thumbnail
                                  _buildLatestMediaThumb(
                                    media: mc.latestMedia,
                                    appCyan: appCyan,
                                    onTap: () {
                                      if (mc.isProcessingVideo.value) {
                                        return;
                                      }
                                      if (mc.mediaList.isEmpty) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PreviewScreen(
                                            mediaList: mc.mediaList.toList(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const Spacer(),

                                  // Shutter
                                  _buildShutterButton(
                                    icon: Icons.camera_alt,
                                    onPressed: () async =>
                                        await mc.captureViewerFrame(),
                                    appCyan: appCyan,
                                  ),
                                  const SizedBox(width: 16),

                                  // Record button
                                  _buildRecordButton(
                                    isRecording: mc.isRecording.value,
                                    onPressed: () async =>
                                        await mc.toggleRecordRemoteCamera(),
                                  ),
                                  const Spacer(),

                                  // Các nút nhỏ
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildSmallControlButton(
                                        icon: mc.isAudioEnabled.value
                                            ? Icons.volume_up
                                            : Icons.volume_off,
                                        onPressed: mc.toggleAudio,
                                        appCyan: appCyan,
                                        isActive: mc.isAudioEnabled.value,
                                      ),
                                      const SizedBox(height: 10),
                                      _buildSmallControlButton(
                                        icon: Icons.flash_on,
                                        onPressed: mc.toggleFlashRemoteCamera,
                                        appCyan: appCyan,
                                      ),
                                      const SizedBox(height: 10),
                                      _buildSmallControlButton(
                                        icon: Icons.cameraswitch,
                                        onPressed: mc.switchRemoteCamera,
                                        appCyan: appCyan,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==================== CÁC HÀM BUILD KHÁC (giữ nguyên) ====================
  Widget _buildConnectionStatus({
    required bool isConnected,
    required String stateText,
  }) {
    final lower = stateText.toLowerCase();
    Color dotColor = Colors.orange;
    String label = 'ĐANG KẾT NỐI';

    if (lower.contains('disconnected') ||
        lower.contains('failed') ||
        lower.contains('closed')) {
      dotColor = Colors.redAccent;
      label = 'MẤT KẾT NỐI';
    } else if (isConnected) {
      dotColor = Colors.green;
      label = 'ĐÃ KẾT NỐI';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
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

  Widget buildZoomControls(CallController c) {
    // Giữ nguyên code cũ của bạn nếu cần dùng
    return Container(); // tạm để trống, bạn có thể dán lại nếu dùng
  }

  Widget _buildLatestMediaThumb({
    required CapturedMedia? media,
    required Color appCyan,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: appCyan, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: media == null
            ? const Icon(Icons.photo_library, color: Colors.white54, size: 24)
            : media.type == MediaType.image
            ? Image.file(
                File(media.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54),
                ),
              )
            : Container(
                color: Colors.black54,
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildShutterButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color appCyan,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.black, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordButton({
    required bool isRecording,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(
            color: isRecording ? Colors.red : Colors.white70,
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(
            isRecording ? Icons.stop : Icons.videocam,
            color: isRecording ? Colors.red : Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildSmallControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color appCyan,
    bool isActive = true,
  }) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
        border: isActive ? Border.all(color: appCyan, width: 1.2) : null,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: isActive ? appCyan : Colors.white70, size: 22),
      ),
    );
  }
}
