// lib/screens/origen_screen.dart
//
// CAMBIO: se agregó _validando como debounce en _validar(), mismo patrón
// que destino_screen.dart — previene doble disparo del scanner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
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
  bool _loading   = false;
  bool _validando = false; // 🛡️ debounce: bloquea doble scan

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  String _limpiarCodigo(String code) {
    return code
        .replaceAll(']C1', '')
        .replaceAll(']E0', '')
        .replaceAll(']Q', '')
        .trim();
  }

  Future<void> _validar() async {
    // 🛡️ Si ya hay una validación en curso, ignorar el segundo scan
    if (_validando) return;

    final claveLimpia = _limpiarCodigo(_clave.text);
    if (claveLimpia.isEmpty) {
      alertaError(context, 'Ingresa la clave secreta');
      return;
    }

    _validando = true; // bloquear
    ref.read(kioskProvider).registerActivity();
    setState(() => _loading = true);

    try {
      final res = await ApiService.validarUsuario(claveLimpia);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        ref.read(traspasoProvider.notifier).setOrigen(res['data']);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DestinoScreen()),
          );
        }
      } else {
        alertaError(context, res['message'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión con el servidor');
      debugPrint('Error validación: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      // Liberar el debounce después de 1 segundo
      await Future.delayed(const Duration(seconds: 1));
      _validando = false;
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
            CampoCodigo(
              controller: _clave,
              label: 'Clave Secreta (código de barras)',
              ocultable: true,
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 55,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('ENVIAR',
                          style: TextStyle(fontSize: 16)),
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
            TextButton.icon(
              icon: const Icon(Icons.cancel_outlined, color: Colors.white38),
              label: const Text('Cancelar',
                  style: TextStyle(color: Colors.white38)),
              onPressed: () {
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