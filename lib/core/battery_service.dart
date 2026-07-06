// lib/core/battery_service.dart
// 🔋 Servicio de batería — nivel en tiempo real + alerta al 15%
//
// USO:
//   await BatteryService().init();          ← en main.dart junto a ConnectivityService
//   BatteryService().levelStream            ← Stream<int> con el nivel (0-100)
//   BatteryService().isChargingStream       ← Stream<bool> si está cargando
//   BatteryService().lowBatteryStream       ← Stream<bool> true cuando ≤ 15%
//   BatteryService().level                  ← valor síncrono actual
//   BatteryService().isCharging             ← bool síncrono actual
//   BatteryService().isLow                  ← bool síncrono actual (≤ 15%)

import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'trusted_clock_service.dart'; // ← NUEVO: persistir estado del reloj al bajar batería

class BatteryService {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static final BatteryService _instance = BatteryService._internal();
  factory BatteryService() => _instance;
  BatteryService._internal();

  // ─── Dependencia nativa ────────────────────────────────────────────────────
  final Battery _battery = Battery();

  // ─── Umbral de alerta ──────────────────────────────────────────────────────
  static const int _lowThreshold = 15;

  // ─── Estado interno ────────────────────────────────────────────────────────
  int  _level      = 100;
  bool _isCharging = false;

  int  get level      => _level;
  bool get isCharging => _isCharging;
  bool get isLow      => _level <= _lowThreshold && !_isCharging;

  // ─── Streams públicos ──────────────────────────────────────────────────────
  final StreamController<int>  _levelController    = StreamController<int>.broadcast();
  final StreamController<bool> _chargingController = StreamController<bool>.broadcast();
  final StreamController<bool> _lowBatController   = StreamController<bool>.broadcast();

  Stream<int>  get levelStream      => _levelController.stream;
  Stream<bool> get isChargingStream => _chargingController.stream;
  Stream<bool> get lowBatteryStream => _lowBatController.stream;

  // ─── Internos ──────────────────────────────────────────────────────────────
  StreamSubscription? _stateSubscription;
  Timer?              _pollingTimer;

  // Polling cada 60 s para refrescar el nivel (battery_plus no emite nivel en
  // stream, solo el estado de carga). Forzamos lectura periódica.
  static const _pollInterval = Duration(seconds: 60);

  bool _initialized = false;

  // ─── INIT ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Leer estado inicial
    await _refreshLevel();
    await _refreshCharging();

    // Escuchar cambios de estado de carga (conectado/desconectado)
    _stateSubscription = _battery.onBatteryStateChanged.listen((state) async {
      final charging = state == BatteryState.charging ||
                       state == BatteryState.full;
      _updateCharging(charging);
      // Al cambiar estado de carga, releer nivel inmediatamente
      await _refreshLevel();
    });

    // Polling periódico del nivel
    _startPolling();
  }

  // ─── Polling ───────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollInterval, (_) async {
      await _refreshLevel();
    });
  }

  // ─── Lectura de nivel ──────────────────────────────────────────────────────
  Future<void> _refreshLevel() async {
    try {
      final newLevel = await _battery.batteryLevel;
      _updateLevel(newLevel);
    } catch (e) {
      debugPrint('[BatteryService] Error leyendo nivel: $e');
    }
  }

  // ─── Lectura de estado de carga ────────────────────────────────────────────
  Future<void> _refreshCharging() async {
    try {
      final state    = await _battery.batteryState;
      final charging = state == BatteryState.charging ||
                       state == BatteryState.full;
      _updateCharging(charging);
    } catch (e) {
      debugPrint('[BatteryService] Error leyendo estado carga: $e');
    }
  }

  // ─── Actualizar nivel y emitir si cambió ───────────────────────────────────
  void _updateLevel(int newLevel) {
    final wasLow = isLow;

    if (_level != newLevel) {
      _level = newLevel;
      _levelController.add(_level);
    }

    final nowLow = isLow;
    if (wasLow != nowLow) {
      _lowBatController.add(nowLow);

      // ── Persistir estado del reloj cuando la batería entra en zona baja ───
      // TrustedClockService guarda el último timestamp visto en SQLite para
      // poder detectar reinicios o manipulaciones al volver a arrancar.
      if (nowLow) {
        TrustedClockService().persistirEstado().catchError((e) {
          debugPrint('[BatteryService] Error persistiendo reloj: $e');
        });
      }
      // ─────────────────────────────────────────────────────────────────────
    }
  }

  // ─── Actualizar estado de carga y emitir si cambió ─────────────────────────
  void _updateCharging(bool charging) {
    final wasLow = isLow;

    if (_isCharging != charging) {
      _isCharging = charging;
      _chargingController.add(_isCharging);
    }

    // Revaluar alerta de batería baja (si se conectó el cargador → apaga alerta)
    final nowLow = isLow;
    if (wasLow != nowLow) {
      _lowBatController.add(nowLow);
    }
  }

  // ─── Forzar refresco manual (para pruebas o pull-to-refresh) ───────────────
  Future<void> refresh() async {
    await _refreshLevel();
    await _refreshCharging();
  }

  // ─── Dispose ───────────────────────────────────────────────────────────────
  void dispose() {
    _stateSubscription?.cancel();
    _pollingTimer?.cancel();
    _levelController.close();
    _chargingController.close();
    _lowBatController.close();
  }
}