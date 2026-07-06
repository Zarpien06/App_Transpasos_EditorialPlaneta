// lib/core/scheduled_alert_service.dart
//
// 🕐 Servicio de alertas horarias obligatorias
//
// Dispara un overlay de pantalla completa a las 9:00, 10:00, 19:00 y 20:00
// hora Colombia (UTC-5, sin horario de verano).
//
// DISEÑO:
//   • Timer periódico cada 30 s — no pierde el minuto exacto
//   • Usa el navigatorKey global de main.dart (ya existente)
//   • Una sola alerta por hora por día — no re-dispara si ya se mostró
//   • Se integra con ConnectivityService existente (checkOnline real)
//
// USO:
//   • Llamar ScheduledAlertService().start() en _MyAppState.initState()
//   • Llamar ScheduledAlertService().stop() en dispose() si es necesario

import 'dart:async';
import 'package:flutter/material.dart';

import 'connectivity_service.dart';

// Horas en las que se dispara la alerta (hora Colombia)
const List<int> _kAlertHours = [9, 10, 19, 20];

class ScheduledAlertService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final ScheduledAlertService _instance =
      ScheduledAlertService._internal();
  factory ScheduledAlertService() => _instance;
  ScheduledAlertService._internal();

  Timer? _timer;

  // Claves "yyyy-M-d-H" de alertas ya mostradas hoy
  final Set<String> _shown = {};

  // ── Arranque / parada ─────────────────────────────────────────────────────

  void start() {
    _timer?.cancel();
    // Cada 30 segundos revisamos la hora
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    _check(); // revisión inmediata al iniciar
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Lógica central ────────────────────────────────────────────────────────

  void _check() {
    // Colombia = UTC − 5 (sin cambio por horario de verano)
    final colombia = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final key = '${colombia.year}-${colombia.month}-${colombia.day}-${colombia.hour}';

    if (!_kAlertHours.contains(colombia.hour)) return;
    if (_shown.contains(key)) return;

    _shown.add(key);
    _limpiarClavesViejas(colombia);
    _show(colombia);
  }

  void _limpiarClavesViejas(DateTime hoy) {
    final prefixHoy = '${hoy.year}-${hoy.month}-${hoy.day}-';
    _shown.removeWhere((k) => !k.startsWith(prefixHoy));
  }

  void _show(DateTime colombia) {
    // Importamos el navigatorKey global que ya existe en main.dart
    // para no crear una dependencia circular lo recibimos por setter (ver abajo)
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;

    nav.push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) =>
            HourlyMandatoryAlert(triggerTime: colombia),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  // ── Inyección del navigatorKey (evita importar main.dart aquí) ─────────────

  GlobalKey<NavigatorState>? _navigatorKey;

  // Llama esto ANTES de start(), justo después de crear el servicio:
  //   ScheduledAlertService().setNavigatorKey(navigatorKey);
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  // ── Disparo manual (botón de prueba en dashboard admin) ───────────────────

  void triggerTest() {
    final colombia =
        DateTime.now().toUtc().subtract(const Duration(hours: 5));
    _show(colombia);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HourlyMandatoryAlert — overlay de pantalla completa
// ══════════════════════════════════════════════════════════════════════════════

class HourlyMandatoryAlert extends StatefulWidget {
  final DateTime triggerTime;
  const HourlyMandatoryAlert({super.key, required this.triggerTime});

  @override
  State<HourlyMandatoryAlert> createState() => _HourlyMandatoryAlertState();
}

class _HourlyMandatoryAlertState extends State<HourlyMandatoryAlert>
    with SingleTickerProviderStateMixin {

  // ── Animación de pulso del ícono ─────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Estado de conectividad ────────────────────────────────────────────────
  bool _checking  = true;
  bool _isOnline  = false;
  Timer? _recheckTimer;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _verifyConnection();
    // Re-verificar cada 5 s mientras la alerta está visible
    _recheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _verifyConnection(),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _recheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _verifyConnection() async {
    // Reutilizamos checkOnline() que ya hace ping real al servidor
    final online = await ConnectivityService().checkOnline();
    if (mounted) setState(() { _isOnline = online; _checking = false; });
  }

  String get _hourLabel {
    const labels = {9: '9:00 a.m.', 10: '10:00 a.m.', 19: '7:00 p.m.', 20: '8:00 p.m.'};
    return labels[widget.triggerTime.hour]
        ?? '${widget.triggerTime.hour}:00';
  }

  String get _formattedTime {
    final h = widget.triggerTime.hour.toString().padLeft(2, '0');
    final m = widget.triggerTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Bloquea el botón Back de Android — imposible de evadir
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF120800),
        body: SafeArea(
          child: Column(
            children: [
              // ── Banda superior de advertencia ──────────────────────────────
              Container(
                width: double.infinity,
                color: const Color(0xFFCC3300),
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
                child: const Text(
                  '⚠   VERIFICACIÓN OBLIGATORIA   ⚠',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),

              // ── Contenido central ──────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Ícono WiFi pulsante (mismo estilo que _PulsingBatteryIcon)
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFCC3300).withValues(alpha: 0.12),
                            border: Border.all(
                              color: const Color(0xFFCC3300).withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.wifi_find_rounded,
                            size: 50,
                            color: Color(0xFFFF6633),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Hora disparadora
                      Text(
                        'Son las $_hourLabel',
                        style: const TextStyle(
                          color: Color(0xFFFF9966),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Título principal
                      const Text(
                        'Verifica tu conexión\na internet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'Este es un momento clave de sincronización.\n'
                        'Los movimientos pendientes deben enviarse\n'
                        'al servidor antes de continuar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFBBAA9F),
                          fontSize: 14,
                          height: 1.65,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Estado de conexión en tiempo real
                      _buildConnectionStatus(),

                      const SizedBox(height: 36),

                      // ── Botón OK — único modo de cerrar ───────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isOnline
                                ? const Color(0xFF1D9E75)  // verde de ConnectivityService
                                : const Color(0xFFCC3300), // rojo si sin conexión
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _isOnline
                                ? 'Entendido — estoy conectado'
                                : 'Entendido — voy a verificar',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'Esta pantalla solo se cierra con el botón.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Pie: hora Colombia ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Hora Colombia: $_formattedTime',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (_checking) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 15, height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFFFF9966),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Verificando conexión...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55), fontSize: 13,
            ),
          ),
        ],
      );
    }

    final color = _isOnline
        ? const Color(0xFF5DCAA5)
        : const Color(0xFFFF6633);
    final bgColor = _isOnline
        ? const Color(0xFF1D9E75)
        : const Color(0xFFCC3300);
    final icon = _isOnline
        ? Icons.wifi_rounded
        : Icons.wifi_off_rounded;
    final label = _isOnline
        ? 'Conectado — sincronización activa'
        : 'Sin conexión real — revisa la red';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bgColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}