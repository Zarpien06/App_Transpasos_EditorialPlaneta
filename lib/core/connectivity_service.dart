// lib/core/connectivity_service.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';

class ConnectivityService {
  static final ConnectivityService _instance =
      ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _hasInterfaceController =
      StreamController<bool>.broadcast();

  Stream<bool> get onlineStream => _onlineController.stream;
  Stream<bool> get hasInterfaceStream => _hasInterfaceController.stream;

  bool _isOnline = false;
  bool _hasInterface = false;

  bool get isOnline => _isOnline;
  // true = hay WiFi/mobile/ethernet, aunque hayInternetReal() sea false
  bool get hasInterface => _hasInterface;

  StreamSubscription? _subscription;
  Timer? _pollingTimer;

  bool _syncing = false;

  static const _pollOfflineSeconds = 5;
  static const _pollOnlineSeconds  = 30;

  Future<void> init() async {
    final results = await _connectivity.checkConnectivity();
    _hasInterface = _checkHasInterface(results);
    _isOnline = _hasInterface ? await ApiService.hayInternetReal() : false;

    _onlineController.add(_isOnline);
    _hasInterfaceController.add(_hasInterface);

    _subscription =
        _connectivity.onConnectivityChanged.listen((results) async {
      await _evaluar(results);
    });

    _startPolling();
  }

  // ─── Polling ─────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollingTimer?.cancel();

    final interval =
        _isOnline ? _pollOnlineSeconds : _pollOfflineSeconds;

    _pollingTimer = Timer(Duration(seconds: interval), () async {
      final results = await _connectivity.checkConnectivity();
      await _evaluar(results);
      _startPolling();
    });
  }

  // ─── Evaluación central ──────────────────────────────────────────────────

  Future<void> _evaluar(List<ConnectivityResult> results) async {
    final interfaceActiva = _checkHasInterface(results);
    final online = interfaceActiva ? await ApiService.hayInternetReal() : false;
    final yaEstabaOnline = _isOnline;

    _updateInterface(interfaceActiva);
    _update(online);

    if (online && !yaEstabaOnline) {
      await _sync();
    }
  }

  // ─── Sync ─────────────────────────────────────────────────────────────────

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await SyncService.sincronizarCompleto(soloSubida: true);
      await SyncService.subirProductosPendientes();
    } catch (_) {}
    _syncing = false;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool _checkHasInterface(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi)     ||
           results.contains(ConnectivityResult.mobile)   ||
           results.contains(ConnectivityResult.ethernet);
  }

  void _updateInterface(bool value) {
    if (_hasInterface != value) {
      _hasInterface = value;
      _hasInterfaceController.add(value);
    }
  }

  void _update(bool value) {
    if (_isOnline != value) {
      _isOnline = value;
      _onlineController.add(value);
      _startPolling();
    }
  }

  Future<bool> checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    if (!_checkHasInterface(results)) return false;
    return ApiService.hayInternetReal();
  }

  void dispose() {
    _subscription?.cancel();
    _pollingTimer?.cancel();
    _onlineController.close();
    _hasInterfaceController.close();
  }
}