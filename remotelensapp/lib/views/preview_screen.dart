import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:remotelens_app/models/captured_media.dart';
import 'package:video_player/video_player.dart';

class PreviewScreen extends StatefulWidget {
  final List<CapturedMedia> mediaList;

  const PreviewScreen({super.key, required this.mediaList});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late PageController _pageController;
  int currentIndex = 0;

  // Cache controller để tránh tạo lại nhiều lần
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, ChewieController> _chewieControllers = {};
  final Map<int, String> _videoInitErrors = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _initializeCurrentMedia(0);
  }

  Future<void> _initializeCurrentMedia(int index) async {
    final media = widget.mediaList[index];
    if (media.type != MediaType.video) return;

    // Tạo controller nếu chưa có
    if (!_videoControllers.containsKey(index)) {
      try {
        final file = File(media.path);
        if (!file.existsSync() || file.lengthSync() <= 0) {
          _videoInitErrors[index] = 'File video không tồn tại hoặc rỗng';
          if (mounted) setState(() {});
          return;
        }

        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        // `MonitorController` đã chặn video rỗng rồi, nên chỉ cần đảm bảo
        // controller đã initialize là đủ để tránh spinner vô hạn.
        if (!controller.value.isInitialized) {
          throw Exception('Video không khởi tạo được.');
        }

        final chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true, // Tự động play khi swipe đến
          looping: false,
          showControls: true,
          allowFullScreen: true,
          allowMuting: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: const Color(0xFF00E5FF),
            handleColor: Colors.white,
            backgroundColor: Colors.grey.shade800,
          ),
          placeholder: const Center(
            child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
          ),
          errorBuilder: (context, errorMessage) => Center(
            child: Text(
              'Không phát được video\n$errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        );

        _videoControllers[index] = controller;
        _chewieControllers[index] = chewieController;
        _videoInitErrors.remove(index);
      } catch (e) {
        _videoInitErrors[index] = 'Lỗi khởi tạo video: $e';
        _chewieControllers.remove(index);
        // Nếu đã tạo controller trước khi lỗi, đảm bảo dispose để tránh leak.
        if (_videoControllers.containsKey(index)) {
          try {
            _videoControllers[index]?.dispose();
          } catch (_) {}
          _videoControllers.remove(index);
        }
      } finally {
        // Quan trọng: phải gọi setState để PageView rebuild
        if (mounted) setState(() {});
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() => currentIndex = index);
    _initializeCurrentMedia(index); // Khởi tạo video mới khi swipe
  }

  @override
  void dispose() {
    // Dispose tất cả controller
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    for (final chewie in _chewieControllers.values) {
      chewie.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${currentIndex + 1}/${widget.mediaList.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: widget.mediaList.isEmpty
          ? const Center(
              child: Text(
                "Không có file",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaList.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final media = widget.mediaList[index];

                if (media.type == MediaType.image) {
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Center(
                      child: Image.file(
                        File(media.path),
                        fit: BoxFit.contain,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text(
                            "Không tải được ảnh",
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // ==================== VIDEO ====================
                final initError = _videoInitErrors[index];
                if (initError != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        initError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                final chewieController = _chewieControllers[index];
                if (chewieController == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                  );
                }

                return Center(child: Chewie(controller: chewieController));
              },
            ),
    );
  }
}
