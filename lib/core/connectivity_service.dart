// lib/core/connectivity_service.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'trusted_clock_service.dart';

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

  Stream<bool> get onlineStream       => _onlineController.stream;
  Stream<bool> get hasInterfaceStream => _hasInterfaceController.stream;

  bool _isOnline     = false;
  bool _hasInterface = false;

  bool get isOnline     => _isOnline;
  bool get hasInterface => _hasInterface;

  StreamSubscription? _subscription;
  Timer?              _pollingTimer;

  bool      _syncing         = false;
  DateTime? _ultimaVerificacion; // cuándo se hizo el último hayInternetReal()

  static const _pollOfflineSeconds = 5;
  static const _pollOnlineSeconds  = 30;

  // Si el último ping HTTP tiene menos de este tiempo, checkOnline() devuelve
  // el estado cacheado en vez de hacer otro ping.
  static const _maxEdadCacheSegundos = 20;

  Future<void> init() async {
    final results = await _connectivity.checkConnectivity();
    _hasInterface = _checkHasInterface(results);
    _isOnline     = _hasInterface ? await ApiService.hayInternetReal() : false;
    _ultimaVerificacion = DateTime.now();

    _onlineController.add(_isOnline);
    _hasInterfaceController.add(_hasInterface);

    _subscription =
        _connectivity.onConnectivityChanged.listen((results) async {
      await _evaluar(results);
    });

    _startPolling();
  }

  // ─── Polling ──────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollingTimer?.cancel();
    final interval = _isOnline ? _pollOnlineSeconds : _pollOfflineSeconds;
    _pollingTimer = Timer(Duration(seconds: interval), () async {
      final results = await _connectivity.checkConnectivity();
      await _evaluar(results);
      _startPolling();
    });
  }

  // ─── Evaluación central ───────────────────────────────────────────────────

  Future<void> _evaluar(List<ConnectivityResult> results) async {
    final interfaceActiva = _checkHasInterface(results);
    final online          = interfaceActiva
        ? await ApiService.hayInternetReal()
        : false;
    _ultimaVerificacion = DateTime.now();

    final yaEstabaOnline = _isOnline;

    _updateInterface(interfaceActiva);
    _update(online);

    if (online && !yaEstabaOnline) {
      await _sync();
    }
  }

  // ─── Sync al reconectarse ─────────────────────────────────────────────────

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      // Re-validar hora al reconectarse
      final resultadoReloj =
          await TrustedClockService().sincronizarConServidor();
      debugPrint(
        '🕐 ConnectivityService: reloj tras reconexión → '
        '${resultadoReloj.mensaje}',
      );

      // sincronizarCompleto ya incluye subirProductosPendientes() internamente
      await SyncService.sincronizarCompleto(soloSubida: true);
    } catch (_) {}
    _syncing = false;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool _checkHasInterface(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi)   ||
           results.contains(ConnectivityResult.mobile) ||
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

  /// Devuelve el estado de conexión real.
  ///
  /// Si el último ping HTTP tiene menos de [_maxEdadCacheSegundos], devuelve
  /// el estado cacheado directamente — sin hacer otro request HTTP. Esto evita
  /// el ping duplicado que ocurría cuando SyncService llamaba checkOnline()
  /// justo después de que _evaluar() ya había hecho uno.
  ///
  /// Si la interfaz de red no está activa, devuelve false sin ping.
  /// Si el caché está vencido, hace un ping HTTP y actualiza el estado.
  Future<bool> checkOnline() async {
    // Sin interfaz → offline seguro, sin ping
    final results = await _connectivity.checkConnectivity();
    if (!_checkHasInterface(results)) {
      _updateInterface(false);
      _update(false);
      return false;
    }

    // Estado reciente → devolver caché
    if (_ultimaVerificacion != null) {
      final edad = DateTime.now().difference(_ultimaVerificacion!).inSeconds;
      if (edad < _maxEdadCacheSegundos) {
        return _isOnline;
      }
    }

    // Caché vencido → ping real
    final online = await ApiService.hayInternetReal();
    _ultimaVerificacion = DateTime.now();
    _update(online);
    return online;
  }

  void dispose() {
    _subscription?.cancel();
    _pollingTimer?.cancel();
    _onlineController.close();
    _hasInterfaceController.close();
  }
}