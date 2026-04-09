import 'dart:math';

import 'package:flutter/material.dart';
import 'package:remotelens_app/services/connectivity_service.dart';
import 'package:remotelens_app/viewmodels/call_controller.dart';
import 'package:remotelens_app/config/config.dart';
import 'package:remotelens_app/services/signaling_service.dart';
import 'package:remotelens_app/views/camera_screen.dart';
import 'package:remotelens_app/views/monitor_screen.dart';
import 'package:remotelens_app/services/webrtc_service.dart';
import 'dart:async';

class SelectionLandingScreen extends StatefulWidget {
  const SelectionLandingScreen({super.key});

  @override
  State<SelectionLandingScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<SelectionLandingScreen> {
  late final TextEditingController roomCtrl;
  late final TextEditingController idCtrl;

  static String get signalingUrl => AppConfig.signalingUrl;

  @override
  void initState() {
    super.initState();
    roomCtrl = TextEditingController(text: _generateRoomId());
    idCtrl = TextEditingController(text: _generateSelfId());
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  String _generateRoomId() {
    return '${_generateRandomString(5)}';
  }

  String _generateSelfId() {
    return '${_generateRandomString(5)}';
  }

  void _regenerateRoomId() {
    setState(() {
      roomCtrl.text = _generateRoomId();
    });
  }

  void _regenerateSelfId() {
    setState(() {
      idCtrl.text = _generateSelfId();
    });
  }

  Future<void> _openPage(CallController controller, bool showLocal) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallPage(controller: controller, showLocal: showLocal),
      ),
    );

    await controller.disposeAll();
  }

  Future<void> _startAsMaster() async {
    final roomId = roomCtrl.text.trim();
    final selfId = idCtrl.text.trim();

    if (roomId.isEmpty || selfId.isEmpty) {
      _showMessage('Room ID và Self ID không được để trống');
      return;
    }

    try {
      final controller = CallController(
        signaling: SignalingService(),
        webrtc: WebRtcService(),
        connectivity: ConnectivityService(),
      );

      await controller.init(
        signalingUrl: signalingUrl,
        roomId: roomId,
        selfId: selfId,
        role: CallRole.master,
      );

      await controller.startMaster();

      if (!mounted) return;
      await _openPage(controller, true);
    } catch (e) {
      _showMessage('Lỗi start master: $e');
    }
  }

  Future<void> _joinAsViewerWithCode(String roomCode) async {
    final selfId = idCtrl.text.trim();
    final roomId = roomCode.trim();

    if (roomId.isEmpty || selfId.isEmpty) {
      _showMessage('Room ID và Self ID không được để trống');
      return;
    }

    try {
      final controller = CallController(
        signaling: SignalingService(),
        webrtc: WebRtcService(),
        connectivity: ConnectivityService(),
      );

      await controller.init(
        signalingUrl: signalingUrl,
        roomId: roomId,
        selfId: selfId,
        role: CallRole.viewer,
      );

      if (!mounted) return;

      await _openPage(controller, false);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      // _showMessage('Lỗi join viewer: $e');
      _showDialog('$msg');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showDialog(String text) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Thông báo"),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    roomCtrl.dispose();
    idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const Icon(Icons.settings, color: Colors.cyan),
        title: const Text(
          'REMOTELENS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              'Choose Mode',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect two devices to start your session',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 24),

            // _buildInfoBox(),
            const SizedBox(height: 24),

            _buildModeCard(
              title: 'Camera Mode',
              subtitle: "Stream this device's feed to a remote monitor.",
              statusText: 'BROADCASTING (SENDER)',
              buttonText: 'Set as Camera',
              buttonColor: Colors.cyan,
              borderColor: Colors.cyan.withOpacity(0.3),
              icon: Icons.videocam,
              imagePath: 'assets/images/camera.png',
              onPressed: () => {
                _regenerateRoomId(),
                _showConnectionCodeDialog(context),
              },
            ),

            const SizedBox(height: 25),

            _buildModeCard(
              title: 'Monitor Mode',
              subtitle: 'Remotely view the connected camera.',
              statusText: 'RECEIVING (MONITOR)',
              buttonText: 'Set as Monitor',
              buttonColor: const Color(0xFFF500D3),
              borderColor: const Color(0xFFF500D3).withOpacity(0.3),
              icon: Icons.monitor,
              imagePath: 'assets/images/clock.png',
              onPressed: () => _showEnterCodeDialog(context),
            ),

            const SizedBox(height: 30),
            TextButton(
              onPressed: () {},
              child: const Text(
                'Need help connecting? View Tutorial',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget _buildInfoBox() {
  //   return Container(
  //     width: double.infinity,
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       color: const Color(0xFF162529),
  //       borderRadius: BorderRadius.circular(16),
  //       border: Border.all(color: Colors.white12),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const Text(
  //           'Thông tin phiên',
  //           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  //         ),
  //         const SizedBox(height: 12),
  //         Row(
  //           children: [
  //             const Expanded(
  //               flex: 3,
  //               child: Text('Room ID:', style: TextStyle(color: Colors.grey)),
  //             ),
  //             Expanded(
  //               flex: 7,
  //               child: SelectableText(
  //                 roomCtrl.text,
  //                 style: const TextStyle(color: Colors.cyan),
  //               ),
  //             ),
  //             IconButton(
  //               onPressed: _regenerateRoomId,
  //               icon: const Icon(Icons.refresh, color: Colors.cyan),
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: 8),
  //         Row(
  //           children: [
  //             const Expanded(
  //               flex: 3,
  //               child: Text('Self ID:', style: TextStyle(color: Colors.grey)),
  //             ),
  //             Expanded(
  //               flex: 7,
  //               child: SelectableText(
  //                 idCtrl.text,
  //                 style: const TextStyle(color: Colors.white),
  //               ),
  //             ),
  //             IconButton(
  //               onPressed: _regenerateSelfId,
  //               icon: const Icon(Icons.refresh, color: Colors.white70),
  //             ),
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

  void _showConnectionCodeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF162529),
        title: const Text('Mã kết nối', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Chia sẻ mã này với thiết bị Monitor:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyan),
              ),
              child: SelectableText(
                roomCtrl.text,
                style: const TextStyle(
                  color: Colors.cyan,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Thiết bị Camera sẽ tạo offer và bắt đầu phát.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _startAsMaster();
            },
            child: const Text('Bắt đầu phát'),
          ),
        ],
      ),
    );
  }

  void _showEnterCodeDialog(BuildContext context) {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF162529),
        title: const Text(
          'Nhập mã kết nối',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: codeController,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            hintText: 'VD: d5fhd',
            hintStyle: const TextStyle(color: Colors.grey),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade700),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.cyan, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.black26,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF500D3),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final code = codeController.text.trim();

              if (code.isEmpty) {
                _showMessage('Vui lòng nhập mã kết nối');
                return;
              }

              Navigator.pop(dialogContext);
              await _joinAsViewerWithCode(code);
            },
            child: const Text('Kết nối'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required String statusText,
    required String buttonText,
    required Color buttonColor,
    required Color borderColor,
    required IconData icon,
    required String imagePath,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF162529),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  image: DecorationImage(
                    image: AssetImage(imagePath),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 38,
                backgroundColor: Colors.black54,
                child: Icon(icon, color: buttonColor, size: 36),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: buttonColor),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  statusText,
                  style: TextStyle(
                    color: buttonColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CallPage extends StatefulWidget {
  final CallController controller;
  final bool showLocal;

  const CallPage({
    super.key,
    required this.controller,
    required this.showLocal,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Scaffold(
      appBar: AppBar(title: Text('State: ${c.stateText}')),
      body: widget.showLocal
          ? CameraScreen(connectionCode: c.roomId, c: c)
          : MonitorScreen(masterCode: c.roomId!, c: c),
    );
  }
}
