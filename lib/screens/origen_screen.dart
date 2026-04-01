// lib/screens/origen_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart'; // 👈 Para acceder a kioskProvider
import '../providers/traspaso_provider.dart';
import '../services/api_service.dart';
import '../widgets/campo_codigo.dart';
import '../widgets/alerts.dart';
import 'destino_screen.dart';

class OrigenScreen extends ConsumerStatefulWidget {
  const OrigenScreen({super.key});

  @override
  ConsumerState<OrigenScreen> createState() => _OrigenScreenState();
}

class _OrigenScreenState extends ConsumerState<OrigenScreen> {
  final _clave = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  // 🔹 LIMPIEZA DE CÓDIGO
  String _limpiarCodigo(String code) {
    return code
        .replaceAll(']C1', '')
        .replaceAll(']E0', '')
        .replaceAll(']Q', '')
        .trim();
  }

  // 🔹 VALIDACIÓN
  Future<void> _validar() async {
    final claveLimpia = _limpiarCodigo(_clave.text);

    if (claveLimpia.isEmpty) {
      alertaError(context, 'Ingresa la clave secreta');
      return;
    }

    // 🔥 Registrar actividad en Kiosk
    ref.read(kioskProvider).registerActivity();

    setState(() => _loading = true);

    try {
      final res = await ApiService.validarUsuario(claveLimpia);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        // ✅ CORREGIDO: Acceder al notifier para usar setOrigen
        ref.read(traspasoProvider.notifier).setOrigen(res['data']);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DestinoScreen()),
          );
        }
      } else {
        alertaError(context, res['mensaje'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión con el servidor');
      debugPrint('Error validación: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuario Origen'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // 🔥 LOGO OPTIMIZADO
            Center(
              child: Image.asset(
                'assets/img/planeta-icon-v2.png',
                width: 120,
                filterQuality: FilterQuality.low,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Ingrese la clave del usuario origen',
              style: TextStyle(color: Color(0xFF90CAF9), fontSize: 16),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            // 🧾 CAMPO
            CampoCodigo(
              controller: _clave,
              label: 'Clave Secreta (código de barras)',
              ocultable: true,
            ),

            const SizedBox(height: 30),

            // 🚀 BOTÓN
            SizedBox(
              height: 55,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded),
                      label: const Text(
                        'ENVIAR',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF42A5F5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 8,
                      ),
                      onPressed: _validar,
                    ),
            ),

            const SizedBox(height: 16),

            // ❌ CANCELAR
            TextButton.icon(
              icon: const Icon(Icons.cancel_outlined, color: Colors.white38),
              label: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white38),
              ),
              onPressed: () {
                // ✅ CORREGIDO: Acceder al notifier
                ref.read(traspasoProvider.notifier).limpiar();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}