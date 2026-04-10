import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  Timer? _pollingTimer; // ← NUEVO

  bool _syncing = false;

  // Cada cuánto revisar cuando NO hay internet (segundos)
  static const _pollOfflineSeconds = 5;
  // Cada cuánto revisar cuando SÍ hay internet (segundos)
  static const _pollOnlineSeconds  = 30;

  Future<void> init() async {
    _isOnline = await checkOnline();
    _onlineController.add(_isOnline);

    // Escuchar cambios de interfaz (igual que antes)
    _subscription =
        _connectivity.onConnectivityChanged.listen((results) async {
      await _evaluar(results);
    });

    // Iniciar polling
    _startPolling();
  }

  // ─── Polling ────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollingTimer?.cancel();

    final interval = _isOnline
        ? _pollOnlineSeconds
        : _pollOfflineSeconds;

    _pollingTimer = Timer(Duration(seconds: interval), () async {
      final results = await _connectivity.checkConnectivity();
      await _evaluar(results);
      _startPolling(); // re-schedule (intervalo puede cambiar)
    });
  }

  // ─── Evaluación central ──────────────────────────────────────────────────

  Future<void> _evaluar(List<ConnectivityResult> results) async {
    if (!_hasInterface(results)) {
      _update(false);
      return;
    }

    final online = await _checkInternetReal();
    final yaEstabaOnline = _isOnline;

    _update(online);

    // Sincronizar solo al RECUPERAR conexión
    if (online && !yaEstabaOnline) {
      await _sync();
    }
  }

  // ─── Sync ────────────────────────────────────────────────────────────────

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await SyncService.sincronizarCompleto();
    } catch (_) {}
    _syncing = false;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  bool _hasInterface(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi)    ||
           results.contains(ConnectivityResult.mobile)  ||
           results.contains(ConnectivityResult.ethernet);
  }

  void _update(bool value) {
    if (_isOnline != value) {
      _isOnline = value;
      _onlineController.add(value);
      _startPolling(); // cambió el estado → ajustar intervalo
    }
  }

  Future<bool> _checkInternetReal() async {
    try {
      final result = await InternetAddress.lookup('prologics.co')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    if (!_hasInterface(results)) return false;
    return await _checkInternetReal();
  }

  void dispose() {
    _subscription?.cancel();
    _pollingTimer?.cancel(); // ← NUEVO
    _onlineController.close();
  }
}