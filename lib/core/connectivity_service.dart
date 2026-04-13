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

  Stream<bool> get onlineStream => _onlineController.stream;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  StreamSubscription? _subscription;
  Timer? _pollingTimer;

  bool _syncing = false;

  // Polling cuando NO hay internet: cada 5 s (recuperación rápida)
  // Polling cuando SÍ hay internet: cada 30 s (heartbeat suave)
  static const _pollOfflineSeconds = 5;
  static const _pollOnlineSeconds  = 30;

  Future<void> init() async {
    _isOnline = await checkOnline();
    _onlineController.add(_isOnline);

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
      _startPolling(); // re-schedule: el intervalo puede haber cambiado
    });
  }

  // ─── Evaluación central ──────────────────────────────────────────────────

  Future<void> _evaluar(List<ConnectivityResult> results) async {
    if (!_hasInterface(results)) {
      _update(false);
      return;
    }

    // FIX: usar HTTP real en vez de DNS lookup.
    // InternetAddress.lookup resuelve aunque el servidor esté caído o el
    // proxy bloquee HTTP; ApiService.hayInternetReal() hace un HEAD directo.
    final online         = await ApiService.hayInternetReal();
    final yaEstabaOnline = _isOnline;

    _update(online);

    // Sincronizar solo al RECUPERAR conexión, y solo subir:
    // no tiene sentido hacer el GET de descarga en cada reconexión.
    if (online && !yaEstabaOnline) {
      await _sync();
    }
  }

  // ─── Sync ─────────────────────────────────────────────────────────────────

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      // soloSubida: true → omite el GET de descarga, solo vacía la cola.
      await SyncService.sincronizarCompleto(soloSubida: true);
    } catch (_) {}
    _syncing = false;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool _hasInterface(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi)     ||
           results.contains(ConnectivityResult.mobile)   ||
           results.contains(ConnectivityResult.ethernet);
  }

  void _update(bool value) {
    if (_isOnline != value) {
      _isOnline = value;
      _onlineController.add(value);
      _startPolling(); // cambió el estado → ajustar intervalo
    }
  }

  // checkOnline() también usa HTTP real para ser consistente.
  Future<bool> checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    if (!_hasInterface(results)) return false;
    return ApiService.hayInternetReal();
  }

  void dispose() {
    _subscription?.cancel();
    _pollingTimer?.cancel();
    _onlineController.close();
  }
}