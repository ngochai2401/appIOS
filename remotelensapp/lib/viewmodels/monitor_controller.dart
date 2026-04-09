import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'package:remotelens_app/models/captured_media.dart';
import 'package:remotelens_app/viewmodels/call_controller.dart';

class MonitorController extends GetxController {
  final CallController callController;
  final String masterCode;

  MonitorController({required this.callController, required this.masterCode});

  // ==================== OBSERVABLES ====================
  final isAudioEnabled = true.obs;
  final isRecording = false.obs;
  final isCapturing = false.obs;
  final isProcessingVideo = false.obs;
  final mediaList = <CapturedMedia>[].obs;
  final recordingDuration = Duration.zero.obs; // ← thời gian quay realtime

  final GlobalKey repaintKey = GlobalKey();

  // Recording
  MediaRecorder? _mediaRecorder;
  String? _currentVideoPath;
  Timer? _recordingTimer;

  // Listener
  late final VoidCallback _pcListener;
  StreamSubscription? _remoteStreamSub;

  // ==================== INIT & DISPOSE ====================
  @override
  void onInit() {
    super.onInit();

    _pcListener = () => update();
    callController.webrtc.isPeerConnected.addListener(_pcListener);
    callController.addListener(_onCallChanged);

    _remoteStreamSub = callController.webrtc.onRemoteStream.listen(
      (_) => update(),
    );
  }

  @override
  void onClose() {
    _recordingTimer?.cancel();
    callController.webrtc.isPeerConnected.removeListener(_pcListener);
    callController.removeListener(_onCallChanged);
    _remoteStreamSub?.cancel();
    super.onClose();
  }

  void _onCallChanged() => update();

  // ==================== GETTERS ====================
  MediaStream? get remoteStream =>
      callController.webrtc.remoteRenderer.srcObject;
  bool get hasRemoteStream => remoteStream != null;

  bool get isConnected =>
      hasRemoteStream ||
      callController.stateText.toLowerCase().contains('connected');

  CapturedMedia? get latestMedia => mediaList.isEmpty ? null : mediaList.first;

  // ==================== AUDIO ====================
  void toggleAudio() {
    isAudioEnabled.value = !isAudioEnabled.value;
    final tracks = remoteStream?.getAudioTracks() ?? [];
    for (final track in tracks) {
      track.enabled = isAudioEnabled.value;
    }
  }

  // ==================== CAPTURE PHOTO ====================
  Future<void> captureViewerFrame() async {
    if (isCapturing.value) return;
    if (!hasRemoteStream) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.snackbar('Thông báo', 'Chưa có hình ảnh từ camera');
      });
      return;
    }

    try {
      isCapturing.value = true;

      final boundary =
          repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Get.snackbar('Lỗi', 'Không lấy được khung hình');
        });
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      final result = await GallerySaver.saveImage(
        file.path,
        albumName: 'RemoteLens',
      );

      if (result == true) {
        mediaList.insert(
          0,
          CapturedMedia(path: file.path, type: MediaType.image),
        );
        // GetBuilder cần update() để refresh thumbnail.
        update();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Get.snackbar('Thành công', 'Ảnh đã lưu vào thư viện');
        });
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.snackbar('Lỗi', 'Chụp ảnh thất bại: $e');
      });
    } finally {
      isCapturing.value = false;
    }
  }

  // ==================== RECORDING ====================
  Future<void> toggleRecordRemoteCamera() async {
    if (!isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.snackbar('Thông báo', 'Chưa kết nối tới camera');
      });
      return;
    }

    if (isRecording.value) {
      await _stopRecordRemoteStream();
    } else {
      await _startRecordRemoteStream();
    }
  }

  Future<void> _startRecordRemoteStream() async {
    if (!hasRemoteStream) return;

    try {
      final videoTracks = remoteStream!.getVideoTracks();
      if (videoTracks.isEmpty) return;

      final path = await _createVideoPath();
      final recorder = MediaRecorder();

      await recorder.start(
        path,
        videoTrack: videoTracks.first,
        // INPUT/OUTPUT để ghi audio từ remote (đầu kia nói)
        rotationDegrees: 0,
        audioChannel: RecorderAudioChannel.OUTPUT,
      );

      _mediaRecorder = recorder;
      _currentVideoPath = path;
      isRecording.value = true;
      _startRecordingTimer();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.context != null) {
          Get.snackbar(
            'Đang quay',
            'Bắt đầu ghi hình',
            duration: const Duration(seconds: 1),
          );
        }
      });
    } catch (e) {
      debugPrint('Record error: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.context != null) {
          Get.snackbar('Lỗi', 'Không thể bắt đầu quay: $e');
        }
      });
    }
  }

  Future<void> _stopRecordRemoteStream() async {
    _recordingTimer?.cancel();
    recordingDuration.value = Duration.zero;

    try {
      await _mediaRecorder?.stop();

      final originalPath = _currentVideoPath;
      _mediaRecorder = null;
      _currentVideoPath = null;
      isRecording.value = false;

      if (originalPath == null) return;

      final originalFile = File(originalPath);
      // MediaRecorder đôi khi trả về trước khi file kịp finalize hoàn toàn.
      // Poll vài giây để đảm bảo file đã có dữ liệu trước khi FFmpeg xử lý.
      int originalBytes = 0;
      const pollStep = Duration(milliseconds: 200);
      const maxWait = Duration(seconds: 3);
      final deadline = DateTime.now().add(maxWait);
      while (DateTime.now().isBefore(deadline)) {
        if (originalFile.existsSync()) {
          originalBytes = originalFile.lengthSync();
          if (originalBytes > 0) break;
        }
        await Future.delayed(pollStep);
      }

      if (originalBytes <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Get.context != null) {
            Get.snackbar(
              'Lỗi',
              'Không ghi được video (file rỗng). Hãy record lại khi camera ổn định.',
              duration: const Duration(seconds: 3),
            );
          }
        });
        return;
      }

      isProcessingVideo.value = true;
      update();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.context != null) {
          Get.snackbar(
            'Đang xử lý',
            'Đang tối ưu video...',
            duration: const Duration(seconds: 3),
          );
        }
      });

      final fixedPath = originalPath.replaceFirst('.mp4', '_fixed.mp4');

      final session = await FFmpegKit.execute(
        '-i "$originalPath" '
        '-vf scale=trunc(iw/2)*2:trunc(ih/2)*2 '
        '-r 30 '
        '-c:v libx264 -preset veryfast -crf 23 '
        '-c:a aac -b:a 128k '
        '-movflags +faststart '
        '"$fixedPath"',
      );

      final returnCode = await session.getReturnCode();
      final bool isFfmpegSuccess = ReturnCode.isSuccess(returnCode);
      debugPrint('FFmpeg returnCode=$returnCode, success=$isFfmpegSuccess');

      final String finalPath = isFfmpegSuccess ? fixedPath : originalPath;

      // Nếu video output lỗi/empty thì đừng add vào danh sách để tránh PreviewScreen bị xoay mãi.
      final outFile = File(finalPath);
      if (!outFile.existsSync() || outFile.lengthSync() <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Get.context != null) {
            Get.snackbar(
              'Lỗi',
              'Không tối ưu được video (file rỗng sau FFmpeg). Hãy record lại.',
              duration: const Duration(seconds: 3),
            );
          }
        });
        return;
      }

      if (isFfmpegSuccess) {
        try {
          File(originalPath).deleteSync();
        } catch (_) {}
      }

      await Gal.putVideo(finalPath, album: 'RemoteLens');

      mediaList.insert(
        0,
        CapturedMedia(path: finalPath, type: MediaType.video),
      );
      // GetBuilder cần update() để refresh thumbnail.
      update();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.context != null) {
          Get.snackbar(
            'Thành công',
            'Video đã lưu và sẵn sàng xem',
            duration: const Duration(seconds: 3),
          );
        }
      });
    } catch (e) {
      debugPrint('Record error: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.context != null) {
          Get.snackbar('Lỗi', 'Dừng quay thất bại: $e');
        }
      });
    } finally {
      isProcessingVideo.value = false;
      update();
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    recordingDuration.value = Duration.zero;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordingDuration.value += const Duration(seconds: 1);
    });
  }

  Future<String> _createVideoPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/monitor_record_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  // ==================== REMOTE COMMANDS ====================
  void toggleFlashRemoteCamera() {
    if (!isConnected) return;
    callController.sendCommand(
      type: 'toggle_flash',
      payload: {'masterCode': masterCode},
    );
  }

  void switchRemoteCamera() {
    if (!isConnected) return;
    callController.sendCommand(
      type: 'switch_camera',
      payload: {'masterCode': masterCode},
    );
  }
}
