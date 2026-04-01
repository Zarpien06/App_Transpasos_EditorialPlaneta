// lib/core/kiosk_service.dart
// 🔒 KIOSKO REAL — usa startLockTask() de Android nativo

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KioskService extends ChangeNotifier {
  static const String _pin     = 'sistemas';
  static const Duration _timeout = Duration(minutes: 5);
  static const String _prefKey = 'kiosko_activo';

  // Canal nativo Android
  static const _channel = MethodChannel('com.example.traspasos_planeta/kiosk');

  bool   _isKioskActive = false;
  Timer? _timeoutTimer;
  void Function()? onTimeout;

  bool get isKioskActive => _isKioskActive;

  // ── CARGAR ESTADO PERSISTIDO ───────────────────────────────
  Future<void> cargarEstadoPersistido() async {
    final prefs = await SharedPreferences.getInstance();
    final debeEstarActivo = prefs.getBool(_prefKey) ?? false;
    if (debeEstarActivo) await _activarInterno();
  }

  Future<void> _persistir(bool activo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, activo);
  }

  // ── ACTIVAR ────────────────────────────────────────────────
  Future<void> activate() async => await _activarInterno();

  Future<void> _activarInterno() async {
    try {
      // 🔒 Llama a startLockTask() en Android — bloqueo REAL
      await _channel.invokeMethod('startKiosk');
    } catch (e) {
      debugPrint('Error activando kiosk nativo: $e');
    }

    _isKioskActive = true;
    await _persistir(true);

    // Ocultar barras también
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _resetTimer();
    notifyListeners();
  }

  // ── DESACTIVAR CON PIN ─────────────────────────────────────
  Future<bool> deactivate(String pin) async {
    if (pin != _pin) return false;
    await _desactivarInterno();
    return true;
  }

  // ── FORZAR DESACTIVACIÓN (desde admin) ────────────────────
  Future<void> forceDeactivate() async => await _desactivarInterno();

  Future<void> _desactivarInterno() async {
    try {
      // 🔓 Llama a stopLockTask() en Android
      await _channel.invokeMethod('stopKiosk');
    } catch (e) {
      debugPrint('Error desactivando kiosk nativo: $e');
    }

    _isKioskActive = false;
    await _persistir(false);
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    notifyListeners();
  }

  // ── INACTIVIDAD ────────────────────────────────────────────
  void registerActivity() {
    if (_isKioskActive) _resetTimer();
  }

  void _resetTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, () => onTimeout?.call());
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }
}