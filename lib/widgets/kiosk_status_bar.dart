// lib/widgets/kiosk_status_bar.dart
// 📊 Barra de estado del modo kiosco
//
// Muestra en tiempo real:
//   🔋 Nivel de batería + icono que cambia a rojo cuando ≤ 15%
//   📶 Estado de conexión con 3 casos diferenciados:
//       • Sin red (WiFi off)
//       • WiFi conectado SIN internet → aviso naranja "WiFi sin internet"
//       • WiFi conectado CON internet → verde "Online"
//   📛 Nombre del dispositivo (device_id) leído desde DeviceService
//
// Solo se renderiza cuando KioskService.isKioskActive == true.
// Se inserta en la parte superior del KioskWrapper.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/battery_service.dart';
import '../core/connectivity_service.dart';
import '../core/device_service.dart'; // 👈 NUEVO: para leer el device_id
import '../main.dart'; // kioskProvider

class KioskStatusBar extends ConsumerStatefulWidget {
  const KioskStatusBar({super.key});

  @override
  ConsumerState<KioskStatusBar> createState() => _KioskStatusBarState();
}

class _KioskStatusBarState extends ConsumerState<KioskStatusBar> {

  // ─── Estado batería ────────────────────────────────────────────────────────
  int  _batteryLevel  = BatteryService().level;
  bool _isCharging    = BatteryService().isCharging;

  // ─── Estado conexión ───────────────────────────────────────────────────────
  // Necesitamos 2 flags para diferenciar "WiFi sin internet":
  //   _hasInterface  → hay interfaz de red activa (WiFi/mobile/ethernet)
  //   _hasInternet   → hay salida real a internet (ConnectivityService.isOnline)
  bool _hasInterface  = false;
  bool _hasInternet   = ConnectivityService().isOnline;

  // ─── Estado dispositivo ────────────────────────────────────────────────────
  // Se carga una sola vez en initState desde DeviceService (singleton cacheado).
  // Muestra el device_id configurado al inicializar la app (ej: "DV05").
  String _deviceId = '';

  // ─── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription? _levelSub;
  StreamSubscription? _chargingSub;
  StreamSubscription? _onlineSub;
  StreamSubscription? _connectivitySub;

  // ─── Connectivity nativo para saber si hay interfaz aunque no haya internet ─
  final Connectivity _connectivity = Connectivity();

  @override
  void initState() {
    super.initState();

    // Batería — nivel
    _levelSub = BatteryService().levelStream.listen((level) {
      if (mounted) setState(() => _batteryLevel = level);
    });

    // Batería — carga
    _chargingSub = BatteryService().isChargingStream.listen((charging) {
      if (mounted) setState(() => _isCharging = charging);
    });

    // Internet real (stream existente del ConnectivityService)
    _onlineSub = ConnectivityService().onlineStream.listen((online) {
      if (mounted) setState(() => _hasInternet = online);
    });

    // Interfaz de red (WiFi conectado o no, independiente de internet)
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasIf = results.contains(ConnectivityResult.wifi)     ||
                    results.contains(ConnectivityResult.mobile)   ||
                    results.contains(ConnectivityResult.ethernet);
      if (mounted) setState(() => _hasInterface = hasIf);
    });

    // Leer estado inicial de interfaz
    _initInterface();

    // 👈 NUEVO: Leer el device_id guardado en la base de datos
    _loadDeviceId();
  }

  Future<void> _initInterface() async {
    final results = await _connectivity.checkConnectivity();
    final hasIf = results.contains(ConnectivityResult.wifi)     ||
                  results.contains(ConnectivityResult.mobile)   ||
                  results.contains(ConnectivityResult.ethernet);
    if (mounted) setState(() => _hasInterface = hasIf);
  }

  // 👈 NUEVO: Carga el device_id desde DeviceService (singleton, valor cacheado)
  Future<void> _loadDeviceId() async {
    final id = await DeviceService().getDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    _chargingSub?.cancel();
    _onlineSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ─── Lógica de estado de conexión ──────────────────────────────────────────

  /// Caso 1: Sin red            → _hasInterface == false
  /// Caso 2: WiFi sin internet  → _hasInterface == true && _hasInternet == false
  /// Caso 3: Online             → _hasInterface == true && _hasInternet == true
  _ConnectionState get _connectionState {
    if (!_hasInterface) return _ConnectionState.noNetwork;
    if (!_hasInternet)  return _ConnectionState.wifiNoInternet;
    return _ConnectionState.online;
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskProvider);
    if (!kiosk.isKioskActive) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1221),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E2A45), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ── Icono kiosco ──────────────────────────────────────────────────
          const Icon(Icons.lock_outline_rounded, color: Color(0xFF4F8CFF), size: 14),
          const SizedBox(width: 6),
          const Text(
            '',
            style: TextStyle(
              color: Color(0xFF4F8CFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),

          // ── Separador ─────────────────────────────────────────────────────
          const _Divider(),

          // ── Nombre del dispositivo 👈 NUEVO ───────────────────────────────
          // Muestra el device_id (ej: "DV05") configurado al inicializar la app.
          // Solo se renderiza si ya fue cargado (no vacío).
          if (_deviceId.isNotEmpty) ...[
            Text(
              _deviceId,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const _Divider(),
          ],

          // ── Indicador de conexión ─────────────────────────────────────────
          _ConnectionIndicator(state: _connectionState),

          const Spacer(),

          // ── Batería ───────────────────────────────────────────────────────
          _BatteryIndicator(level: _batteryLevel, isCharging: _isCharging),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ConnectionIndicator — 3 estados visuales de conexión
// ══════════════════════════════════════════════════════════════════════════════
enum _ConnectionState { noNetwork, wifiNoInternet, online }

class _ConnectionIndicator extends StatelessWidget {
  final _ConnectionState state;
  const _ConnectionIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    switch (state) {

      // ── Sin red ────────────────────────────────────────────────────────────
      case _ConnectionState.noNetwork:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: Color(0xFFEF4444), size: 14),
            SizedBox(width: 5),
            Text(
              'Sin red',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      // ── WiFi sin internet ──────────────────────────────────────────────────
      case _ConnectionState.wifiNoInternet:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_rounded, color: Color(0xFFF59E0B), size: 13),
              SizedBox(width: 5),
              Text(
                'WiFi sin internet',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );

      // ── Online ─────────────────────────────────────────────────────────────
      case _ConnectionState.online:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_rounded, color: Color(0xFF22C55E), size: 14),
            SizedBox(width: 5),
            Text(
              'Online',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _BatteryIndicator — nivel + icono dinámico
// ══════════════════════════════════════════════════════════════════════════════
class _BatteryIndicator extends StatelessWidget {
  final int  level;
  final bool isCharging;

  const _BatteryIndicator({required this.level, required this.isCharging});

  // Color según nivel
  Color get _color {
    if (isCharging)  return const Color(0xFF22C55E);
    if (level <= 15) return const Color(0xFFEF4444);
    if (level <= 30) return const Color(0xFFF59E0B);
    return const Color(0xFF22C55E);
  }

  // Icono según nivel y estado de carga
  IconData get _icon {
    if (isCharging)   return Icons.battery_charging_full_rounded;
    if (level <= 10)  return Icons.battery_0_bar_rounded;
    if (level <= 25)  return Icons.battery_1_bar_rounded;
    if (level <= 40)  return Icons.battery_2_bar_rounded;
    if (level <= 55)  return Icons.battery_3_bar_rounded;
    if (level <= 70)  return Icons.battery_4_bar_rounded;
    if (level <= 85)  return Icons.battery_5_bar_rounded;
    return Icons.battery_full_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isLow = level <= 15 && !isCharging;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Parpadeo suave cuando está baja y no cargando
        if (isLow)
          _PulsingIcon(icon: _icon, color: _color)
        else
          Icon(_icon, color: _color, size: 16),
        const SizedBox(width: 4),
        Text(
          '$level%',
          style: TextStyle(
            color: _color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isCharging) ...[
          const SizedBox(width: 3),
          const Text(
            '⚡',
            style: TextStyle(fontSize: 10),
          ),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PulsingIcon — parpadeo suave para batería crítica
// ══════════════════════════════════════════════════════════════════════════════
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color    color;
  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _anim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Icon(widget.icon, color: widget.color, size: 16),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// _Divider — separador vertical
// ══════════════════════════════════════════════════════════════════════════════
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 10),
    width: 1,
    height: 16,
    color: const Color(0xFF1E2A45),
  );
}