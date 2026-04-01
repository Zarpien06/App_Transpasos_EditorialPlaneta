// lib/screens/init_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA DE CONFIGURACIÓN INICIAL — aparece UNA SOLA VEZ
//
// Responsabilidades:
//   1. Pedir el número de dispositivo (01–99)
//   2. Generar el ID (ej: DV01) y guardarlo en SQLite via DeviceService
//   3. Mostrar confirmación con el ID generado
//   4. Navegar a LoginScreen — nunca volverá a aparecer
//
// Flujo de arranque (main.dart):
//   DeviceService.estaInicializado()
//     → false → InitScreen   ← estamos aquí
//     → true  → LoginScreen
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/device_service.dart';
import 'login_screen.dart';

class InitScreen extends StatefulWidget {
  const InitScreen({super.key});

  @override
  State<InitScreen> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen>
    with SingleTickerProviderStateMixin {
  final _controller   = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  // Misma instancia que usa main.dart — DeviceService debería ser singleton
  final _deviceService = DeviceService();

  bool _guardando = false;
  String? _errorMensaje;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ── GUARDAR E INICIALIZAR ─────────────────────────────────────────────────
  Future<void> _inicializar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando    = true;
      _errorMensaje = null;
    });

    try {
      await _deviceService.inicializar(_controller.text.trim());
      if (!mounted) return;

      final deviceId = await _deviceService.getDeviceId();
      _mostrarConfirmacion(deviceId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMensaje = 'Error al guardar el dispositivo. Intenta de nuevo.';
        _guardando    = false;
      });
    }
  }

  // ── DIÁLOGO DE CONFIRMACIÓN ───────────────────────────────────────────────
  // Muestra el ID generado y navega al LoginScreen al confirmar.
  void _mostrarConfirmacion(String deviceId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2332),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.check_circle_rounded,
            color: Color(0xFF5DCAA5), size: 52),
        title: Text(
          'Dispositivo registrado',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ID asignado:',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF5DCAA5).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF5DCAA5).withValues(alpha: 0.4)),
              ),
              child: Text(
                deviceId,
                style: const TextStyle(
                  color: Color(0xFF5DCAA5),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Este número identifica el dispositivo en todos los traspasos. '
              'No se puede cambiar sin soporte técnico.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DCAA5),
                  foregroundColor: const Color(0xFF0B1520),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  // Cerrar diálogo y navegar al login
                  // pushAndRemoveUntil elimina InitScreen del stack
                  // para que el botón back no pueda volver aquí
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Comenzar',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1520),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      // ── ÍCONO ──────────────────────────────────────────
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DCAA5)
                              .withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF5DCAA5)
                                .withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.devices_rounded,
                          color: Color(0xFF5DCAA5),
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── TÍTULO ─────────────────────────────────────────
                      const Text(
                        'Configuración inicial',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Este paso se realiza una sola vez.\nIdentifica el dispositivo en el sistema.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // ── CARD FORMULARIO ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131E2D),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            const Text(
                              'Número de dispositivo',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // ── CAMPO NUMÉRICO ─────────────────────────
                            TextFormField(
                              controller: _controller,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              maxLength: 2,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                color: Color(0xFF5DCAA5),
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 8,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: '01',
                                hintStyle: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.15),
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 8,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF0B1520),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: Colors.white
                                          .withValues(alpha: 0.1)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: Colors.white
                                          .withValues(alpha: 0.1)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF5DCAA5), width: 1.5),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE05252), width: 1.5),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE05252), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 20),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Ingresa el número del dispositivo';
                                }
                                final n = int.tryParse(val.trim());
                                if (n == null || n < 1 || n > 99) {
                                  return 'Debe ser un número entre 01 y 99';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),

                            // ── PREVIEW DEL ID ─────────────────────────
                            // ✅ Fix: segundo parámetro __ para Dart 3
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _controller,
                              builder: (_, value, __) {
                                final texto   = value.text.trim();
                                final preview = texto.isNotEmpty
                                    ? 'DV${texto.padLeft(2, '0')}'
                                    : '—';
                                return Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 13,
                                        color: Colors.white
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ID del dispositivo: ',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.3),
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      preview,
                                      style: TextStyle(
                                        color: texto.isNotEmpty
                                            ? const Color(0xFF5DCAA5)
                                                .withValues(alpha: 0.8)
                                            : Colors.white
                                                .withValues(alpha: 0.2),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            // ── ERROR GLOBAL ───────────────────────────
                            if (_errorMensaje != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE05252)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFE05252)
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFE05252),
                                        size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMensaje!,
                                        style: const TextStyle(
                                          color: Color(0xFFE05252),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),

                            // ── BOTÓN INICIALIZAR ──────────────────────
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _guardando ? null : _inicializar,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF5DCAA5),
                                  disabledBackgroundColor:
                                      const Color(0xFF5DCAA5)
                                          .withValues(alpha: 0.4),
                                  foregroundColor:
                                      const Color(0xFF0B1520),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: _guardando
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Color(0xFF0B1520),
                                        ),
                                      )
                                    : const Text(
                                        'Inicializar dispositivo',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── AVISO DE UN SOLO USO ───────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.25)),
                          const SizedBox(width: 6),
                          Text(
                            'Esta pantalla no volverá a aparecer',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}