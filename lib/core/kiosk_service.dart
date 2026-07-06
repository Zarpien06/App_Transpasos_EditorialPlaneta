// lib/core/kiosk_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modo kiosco simple sin Device Owner.
///
/// Qué bloquea:
///   ✅ Pantalla siempre encendida
///   ✅ Barra SUPERIOR visible (hora/batería/señal) — SystemUiMode.manual top
///   ✅ Barra INFERIOR oculta (sin botones atrás/inicio/recientes)
///   ✅ Botón Atrás bloqueado (nativo en MainActivity)
///   ✅ Orientación fija portrait
///   ✅ App Pinning (el usuario necesita Atrás+Recientes ~2s para salir)
///   ✅ Watchdog que reactiva si el sistema desancla la app
///   ✅ Persiste estado entre reinicios
///   ✅ Autoarranque vía BootReceiver
///
/// Qué NO puede bloquear (sin Device Owner / root):
///   ❌ Botón Home de forma total
///   ❌ Instalación de apps
///   ❌ Ajustes de sistema
///
/// NOTA sobre el modo UI:
///   Se usa SystemUiMode.manual con overlays:[SystemUiOverlay.top] en lugar
///   de immersiveSticky. Razones:
///     1. immersiveSticky oculta AMBAS barras — nosotros queremos la superior
///     2. Al deslizar desde el borde con immersiveSticky aparece el mensaje
///        "app desfijada" que confunde a los clientes
///     3. manual+top es compatible con gestos de Android 10+
class KioskService extends ChangeNotifier {
  static const String   _pin      = 'sistemas';
  static const Duration _timeout  = Duration(minutes: 5);
  static const Duration _watchdog = Duration(seconds: 3);
  static const String   _prefKey  = 'kiosko_activo';

  static const _channel = MethodChannel('com.ejemplo.traspasos_planeta/kiosk');

  bool   _isKioskActive = false;
  int    _lockTaskMode  = 0;
  Timer? _timeoutTimer;
  Timer? _watchdogTimer;

  /// Callback cuando expira el timeout de inactividad
  void Function()? onTimeout;
  /// Callback cuando el watchdog detectó que salieron y reactivó
  void Function()? onKioskReactivated;

  bool get isKioskActive => _isKioskActive;
  bool get isDeviceOwner => false; // Siempre false — eliminado por diseño
  int  get lockTaskMode  => _lockTaskMode;

  String get nivelSeguridad {
    if (!_isKioskActive) return 'Desactivado';
    return _lockTaskMode == 1
        ? 'App Pinning activo'
        : 'Kiosco parcial (sin pinning)';
  }

  // ── Inicializar ─────────────────────────────────────────────────────────
  Future<void> inicializar() async {
    _channel.setMethodCallHandler(_handleNativeCallback);
    await cargarEstadoPersistido();
  }

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onKioskExited':
        // El sistema desancló la app → reactivar automáticamente
        if (_isKioskActive) {
          await _activarInterno(silencioso: true);
          onKioskReactivated?.call();
          notifyListeners();
        }
        break;
      case 'onAppResumed':
        if (_isKioskActive) await _reaplicarUIFlags();
        break;
    }
  }

  Future<void> cargarEstadoPersistido() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool(_prefKey) ?? false) && !_isKioskActive) {
      await _activarInterno(silencioso: true);
    }
  }

  Future<void> _persistir(bool activo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, activo);
  }

  // ── Activar ─────────────────────────────────────────────────────────────
  Future<void> activate() async => _activarInterno();

  Future<void> _activarInterno({bool silencioso = false}) async {
    // 1. Intentar App Pinning nativo (puede fallar en algunos dispositivos)
    try {
      await _channel.invokeMethod('startKiosk');
      _lockTaskMode = await _channel.invokeMethod<int>('getLockTaskMode') ?? 0;
    } catch (e) {
      debugPrint('⚠️ kiosk nativo: $e');
      _lockTaskMode = 0;
    }

    // 2. Siempre aplicar UI flags (esto sí funciona en todos los dispositivos)
    await _reaplicarUIFlags();

    // 3. Orientación fija
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _isKioskActive = true;
    await _persistir(true);
    _resetTimer();
    _iniciarWatchdog();

    if (!silencioso) notifyListeners();
  }

  /// Aplica el modo UI correcto del kiosco:
  ///   • Barra SUPERIOR (status bar) → VISIBLE  [hora, batería, señal, red]
  ///   • Barra INFERIOR (nav bar)    → OCULTA   [sin atrás/inicio/recientes]
  ///
  /// USA SystemUiMode.manual con [SystemUiOverlay.top].
  /// NO usar immersiveSticky: oculta ambas barras y genera el mensaje
  /// "app desfijada" al deslizar desde los bordes.
  Future<void> _reaplicarUIFlags() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  // ── Desactivar ──────────────────────────────────────────────────────────
  Future<bool> deactivate(String pin) async {
    if (pin != _pin) return false;
    await _desactivarInterno();
    return true;
  }

  Future<void> forceDeactivate() async => _desactivarInterno();

  Future<void> _desactivarInterno() async {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    try {
      await _channel.invokeMethod('stopKiosk');
    } catch (e) {
      debugPrint('⚠️ kiosk stop: $e');
    }

    _lockTaskMode = 0;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    _isKioskActive = false;
    await _persistir(false);
    notifyListeners();
  }

  // ── Watchdog: detecta si el sistema sacó la app del pinning ─────────────
  void _iniciarWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdog, (_) async {
      if (!_isKioskActive) return;
      try {
        final modo = await _channel.invokeMethod<int>('getLockTaskMode') ?? 0;
        if (modo == 0 && _lockTaskMode != 0) {
          // Detectado: salieron del pinning → reactivar
          _lockTaskMode = 0;
          await _activarInterno(silencioso: true);
          onKioskReactivated?.call();
          notifyListeners();
        } else {
          _lockTaskMode = modo;
        }
      } catch (_) {
        // Al menos mantener los UI flags correctos
        await _reaplicarUIFlags();
      }
    });
  }

  // ── Lifecycle: llamar desde el widget raíz ───────────────────────────────
  Future<void> onAppLifecycleResumed() async {
    if (!_isKioskActive) return;
    await _reaplicarUIFlags();
    try {
      final modo = await _channel.invokeMethod<int>('getLockTaskMode') ?? 0;
      if (modo == 0) {
        await _channel.invokeMethod('startKiosk');
        _lockTaskMode = await _channel.invokeMethod<int>('getLockTaskMode') ?? 0;
      } else {
        _lockTaskMode = modo;
      }
    } catch (e) {
      debugPrint('⚠️ reactivación: $e');
    }
  }

  // Registrar actividad del usuario para reiniciar el timer de inactividad
  void registerActivity() {
    if (_isKioskActive) _resetTimer();
  }

  void _resetTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, () => onTimeout?.call());
  }

  Future<Map<String, dynamic>> diagnostico() async {
    try {
      final modo = await _channel.invokeMethod<int>('getLockTaskMode') ?? -1;
      return {
        'lockTaskMode'  : modo,
        'isDeviceOwner' : false,
        'kioskActivo'   : _isKioskActive,
        'nivelSeguridad': nivelSeguridad,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }
}