import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiosk_mode/kiosk_mode.dart';

class KioskService extends ChangeNotifier {
  static const String _pin = '1234';
  static const Duration _timeout = Duration(minutes: 5);

  // ── Estado kiosco ──
  bool _isKioskActive = false;
  Timer? _timeoutTimer;
  bool get isKioskActive => _isKioskActive;
  void Function()? onTimeout;

  // ── Tap secreto (vive en el service, no en el widget) ──
  int _tapCount = 0;
  DateTime? _firstTap;
  static const int _tapsRequired = 5;
  static const Duration _tapWindow = Duration(seconds: 4);
  void Function()? onSecretTapsDetected; // callback → muestra el PIN dialog

  /// Llama esto en cada tap de la zona secreta
  void registerSecretTap() {
    if (!_isKioskActive) return;
    final now = DateTime.now();
    if (_firstTap == null || now.difference(_firstTap!) > _tapWindow) {
      _firstTap = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    debugPrint('Tap secreto: $_tapCount/$_tapsRequired');
    if (_tapCount >= _tapsRequired) {
      _tapCount = 0;
      _firstTap = null;
      onSecretTapsDetected?.call();
    }
  }

  Future<void> activate() async {
    _isKioskActive = true;
    _tapCount = 0;
    _firstTap = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    try {
      await startKioskMode();
    } catch (e) {
      debugPrint('No se pudo activar kiosco real: $e');
    }
    _resetTimer();
    notifyListeners();
  }

  Future<bool> deactivate(String pin) async {
    if (pin == _pin) {
      _isKioskActive = false;
      _tapCount = 0;
      _firstTap = null;
      _timeoutTimer?.cancel();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      try {
        await stopKioskMode();
      } catch (e) {
        debugPrint('No se pudo salir del kiosco real: $e');
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  void forceDeactivate() {
    _isKioskActive = false;
    _tapCount = 0;
    _firstTap = null;
    _timeoutTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    try { stopKioskMode(); } catch (_) {}
    notifyListeners();
  }

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