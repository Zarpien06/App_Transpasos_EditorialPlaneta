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
// ✅ FIX: Ya NO depende de isKioskActive para renderizarse.
//    La barra se muestra siempre. Esto resuelve el problema de arranque
//    desde reinicio/apagado donde isKioskActive llega false mientras
//    SharedPreferences aún no terminó de cargar.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/battery_service.dart';
import '../core/connectivity_service.dart';
import '../core/device_service.dart';

class KioskStatusBar extends ConsumerStatefulWidget {
  const KioskStatusBar({super.key});

  @override
  ConsumerState<KioskStatusBar> createState() => _KioskStatusBarState();
}

class _KioskStatusBarState extends ConsumerState<KioskStatusBar> {

  // ─── Estado batería ────────────────────────────────────────────────────────
  int  _batteryLevel = BatteryService().level;
  bool _isCharging   = BatteryService().isCharging;

  // ─── Estado conexión ───────────────────────────────────────────────────────
  bool _hasInterface = false;
  bool _hasInternet  = ConnectivityService().isOnline;

  // ─── Estado dispositivo ────────────────────────────────────────────────────
  String _deviceId = '';

  // ─── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription? _levelSub;
  StreamSubscription? _chargingSub;
  StreamSubscription? _onlineSub;
  StreamSubscription? _connectivitySub;

  final Connectivity _connectivity = Connectivity();

  @override
  void initState() {
    super.initState();

    _levelSub = BatteryService().levelStream.listen((level) {
      if (mounted) setState(() => _batteryLevel = level);
    });

    _chargingSub = BatteryService().isChargingStream.listen((charging) {
      if (mounted) setState(() => _isCharging = charging);
    });

    _onlineSub = ConnectivityService().onlineStream.listen((online) {
      if (mounted) setState(() => _hasInternet = online);
    });

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasIf = results.contains(ConnectivityResult.wifi)   ||
                    results.contains(ConnectivityResult.mobile) ||
                    results.contains(ConnectivityResult.ethernet);
      if (mounted) setState(() => _hasInterface = hasIf);
    });

    _initInterface();
    _loadDeviceId();
  }

  Future<void> _initInterface() async {
    final results = await _connectivity.checkConnectivity();
    final hasIf = results.contains(ConnectivityResult.wifi)   ||
                  results.contains(ConnectivityResult.mobile) ||
                  results.contains(ConnectivityResult.ethernet);
    if (mounted) setState(() => _hasInterface = hasIf);
  }

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

  _ConnectionState get _connectionState {
    if (!_hasInterface) return _ConnectionState.noNetwork;
    if (!_hasInternet)  return _ConnectionState.wifiNoInternet;
    return _ConnectionState.online;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Sin condición isKioskActive — la barra se muestra siempre
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
          // ── Icono kiosco ─────────────────────────────────────────────────
          const Icon(Icons.lock_outline_rounded,
              color: Color(0xFF4F8CFF), size: 14),
          const SizedBox(width: 6),

          // ── Separador ────────────────────────────────────────────────────
          const _Divider(),

          // ── Nombre del dispositivo ───────────────────────────────────────
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

          // ── Indicador de conexión ────────────────────────────────────────
          _ConnectionIndicator(state: _connectionState),

          const Spacer(),

          // ── Batería ──────────────────────────────────────────────────────
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

  Color get _color {
    if (isCharging)  return const Color(0xFF22C55E);
    if (level <= 15) return const Color(0xFFEF4444);
    if (level <= 30) return const Color(0xFFF59E0B);
    return const Color(0xFF22C55E);
  }

  IconData get _icon {
    if (isCharging)  return Icons.battery_charging_full_rounded;
    if (level <= 10) return Icons.battery_0_bar_rounded;
    if (level <= 25) return Icons.battery_1_bar_rounded;
    if (level <= 40) return Icons.battery_2_bar_rounded;
    if (level <= 55) return Icons.battery_3_bar_rounded;
    if (level <= 70) return Icons.battery_4_bar_rounded;
    if (level <= 85) return Icons.battery_5_bar_rounded;
    return Icons.battery_full_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isLow = level <= 15 && !isCharging;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          const Text('⚡', style: TextStyle(fontSize: 10)),
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