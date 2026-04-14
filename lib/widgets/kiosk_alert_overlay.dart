// lib/widgets/kiosk_alert_overlay.dart
// ⚠️ Overlay de alerta de batería baja en modo kiosco
//
// Aparece automáticamente cuando la batería baja al 15% y el dispositivo
// NO está cargando. Se muestra como un banner en la parte inferior de la
// pantalla para no interrumpir el flujo del operador.
//
// Comportamiento:
//   • Se activa solo cuando KioskService.isKioskActive == true
//   • Desaparece automáticamente al conectar el cargador
//   • El operador puede descartar el banner por 10 minutos con "Entendido"
//   • Vuelve a aparecer si la batería sigue baja tras el snooze
//
// USO en KioskWrapper:
//   Stack(
//     children: [
//       child,
//       const KioskAlertOverlay(),
//     ],
//   )

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/battery_service.dart';
import '../main.dart'; // kioskProvider

class KioskAlertOverlay extends ConsumerStatefulWidget {
  const KioskAlertOverlay({super.key});

  @override
  ConsumerState<KioskAlertOverlay> createState() => _KioskAlertOverlayState();
}

class _KioskAlertOverlayState extends ConsumerState<KioskAlertOverlay>
    with SingleTickerProviderStateMixin {

  // ─── Estado ────────────────────────────────────────────────────────────────
  bool _isLow       = BatteryService().isLow;
  bool _snoozed     = false;
  int  _level       = BatteryService().level;
  bool _isCharging  = BatteryService().isCharging;

  // Duración del snooze — 10 minutos
  static const _snoozeDuration = Duration(minutes: 10);
  Timer? _snoozeTimer;

  // ─── Animación de entrada/salida ───────────────────────────────────────────
  late AnimationController _animCtrl;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _fadeAnim;

  bool _visible = false; // controla si el widget está en el árbol con animación

  // ─── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription? _lowBatSub;
  StreamSubscription? _levelSub;
  StreamSubscription? _chargingSub;

  @override
  void initState() {
    super.initState();

    // ── Animación ─────────────────────────────────────────────────────────────
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    // ── Subscriptions ─────────────────────────────────────────────────────────
    _lowBatSub = BatteryService().lowBatteryStream.listen((isLow) {
      if (mounted) {
        setState(() => _isLow = isLow);
        _evalAlert();
      }
    });

    _levelSub = BatteryService().levelStream.listen((level) {
      if (mounted) setState(() => _level = level);
    });

    _chargingSub = BatteryService().isChargingStream.listen((charging) {
      if (mounted) {
        setState(() => _isCharging = charging);
        // Si se conectó el cargador → forzar cierre de la alerta
        if (charging) _hideAlert();
      }
    });

    // Evaluar estado inicial
    WidgetsBinding.instance.addPostFrameCallback((_) => _evalAlert());
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _snoozeTimer?.cancel();
    _lowBatSub?.cancel();
    _levelSub?.cancel();
    _chargingSub?.cancel();
    super.dispose();
  }

  // ─── Lógica de visibilidad ─────────────────────────────────────────────────

  /// Determina si debe mostrarse la alerta:
  ///   - Kiosco activo
  ///   - Batería baja (≤ 15%) y NO cargando
  ///   - No está en snooze
  void _evalAlert() {
    final kiosk = ref.read(kioskProvider);
    final shouldShow = kiosk.isKioskActive && _isLow && !_snoozed;

    if (shouldShow && !_visible) {
      _showAlert();
    } else if (!shouldShow && _visible) {
      _hideAlert();
    }
  }

  Future<void> _showAlert() async {
    if (!mounted || _visible) return;
    setState(() => _visible = true);
    await _animCtrl.forward();
  }

  Future<void> _hideAlert() async {
    if (!mounted || !_visible) return;
    await _animCtrl.reverse();
    if (mounted) setState(() => _visible = false);
  }

  // ─── Snooze ────────────────────────────────────────────────────────────────
  void _snooze() {
    setState(() => _snoozed = true);
    _hideAlert();

    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(_snoozeDuration, () {
      if (mounted) {
        setState(() => _snoozed = false);
        _evalAlert(); // Reevaluar — si sigue baja, volver a mostrar
      }
    });
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Escuchar cambios del kiosco para reaccionar si se activa/desactiva
    ref.listen(kioskProvider, (_, __) => _evalAlert());

    if (!_visible) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _AlertBanner(
            level:      _level,
            isCharging: _isCharging,
            onSnooze:   _snooze,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _AlertBanner — UI del banner de alerta
// ══════════════════════════════════════════════════════════════════════════════
class _AlertBanner extends StatelessWidget {
  final int      level;
  final bool     isCharging;
  final VoidCallback onSnooze;

  const _AlertBanner({
    required this.level,
    required this.isCharging,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra de acento roja en la parte superior
            Container(
              height: 3,
              color: const Color(0xFFEF4444),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icono animado ──────────────────────────────────────────
                  _PulsingBatteryIcon(level: level),

                  const SizedBox(width: 14),

                  // ── Texto ──────────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Batería baja',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'El dispositivo tiene $level% de batería. '
                          'Conecta el cargador para evitar apagados inesperados.',
                          style: const TextStyle(
                            color: Color(0xFFE5C0C0),
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // ── Botón de snooze ────────────────────────────────────────
                  GestureDetector(
                    onTap: onSnooze,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'Entendido',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PulsingBatteryIcon — icono pulsante para el banner
// ══════════════════════════════════════════════════════════════════════════════
class _PulsingBatteryIcon extends StatefulWidget {
  final int level;
  const _PulsingBatteryIcon({required this.level});

  @override
  State<_PulsingBatteryIcon> createState() => _PulsingBatteryIconState();
}

class _PulsingBatteryIconState extends State<_PulsingBatteryIcon>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: const Icon(
          Icons.battery_alert_rounded,
          color: Color(0xFFEF4444),
          size: 22,
        ),
      ),
    );
  }
}