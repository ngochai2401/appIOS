import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final InternetConnectionChecker _internetChecker =
      InternetConnectionChecker.createInstance(
        checkTimeout: const Duration(seconds: 3),
        checkInterval: const Duration(seconds: 6),
      );

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;

  bool _hasInternet = true;
  Timer? _debounceTimer;
  StreamSubscription? _connectivitySub;

  void init() {
    _connectivitySub?.cancel();

    _connectivitySub = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      // Không có mạng vật lý (WiFi + Mobile data đều mất)
      if (!hasNetwork) {
        _updateConnectionStatus(false);
        return;
      }

      // Có mạng vật lý → kiểm tra internet thật sự
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
        try {
          final hasInternet = await _internetChecker.hasConnection;
          _updateConnectionStatus(hasInternet);
        } catch (e) {
          _updateConnectionStatus(false);
        }
      });
    });
  }

  void _updateConnectionStatus(bool hasInternet) {
    debugPrint(
      "_updateConnectionStatus: hasInternet=$hasInternet, _hasInternet=$_hasInternet",
    ); // ← thêm
    if (_hasInternet != hasInternet) {
      _hasInternet = hasInternet;
      _connectionController.add(hasInternet);
      debugPrint('ConnectivityService: Internet = $hasInternet');
    }
  }

  /// Kiểm tra nhanh hiện tại
  Future<bool> hasNetwork() async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  Future<bool> hasInternet() async {
    return await _internetChecker.hasConnection;
  }

  /// Force check lại (dùng khi cần)
  Future<void> checkNow() async {
    _debounceTimer?.cancel();
    try {
      final hasNet = await hasNetwork();
      if (!hasNet) {
        _updateConnectionStatus(false);
        return;
      }
      final hasInet = await _internetChecker.hasConnection;
      _updateConnectionStatus(hasInet);
    } catch (_) {
      _updateConnectionStatus(false);
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _connectivitySub?.cancel();
    _connectionController.close();
  }
}
