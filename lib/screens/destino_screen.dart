// lib/screens/destino_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/traspaso_provider.dart';
import '../services/api_service.dart';
import '../widgets/campo_codigo.dart';
import '../widgets/alerts.dart';
import 'lineas_screen.dart';
import '../main.dart';

class DestinoScreen extends ConsumerStatefulWidget {
  const DestinoScreen({super.key});

  @override
  ConsumerState<DestinoScreen> createState() => _DestinoScreenState();
}

class _DestinoScreenState extends ConsumerState<DestinoScreen> {
  final _clave = TextEditingController();
  bool _loading = false;

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

  Widget _infoCard(String titulo, Map<String, dynamic> data) {
    // ✅ CORREGIDO: las claves tienen mayúscula — Codigo_Almacen y Stand
    final almacen = data['Codigo_Almacen'] ?? data['almacen'] ?? '-';
    final stand   = data['Stand']          ?? data['stand']   ?? '-';
    final nombre  = data['Nombre_UsuarioT']                   ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1565C0).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Color(0xFF42A5F5),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (nombre.isNotEmpty)
            Text(
              '👤 $nombre',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            '🏪 Almacén: $almacen',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '📍 Stand: $stand',
            style: const TextStyle(color: Color(0xFFB0BEC5)),
          ),
        ],
      ),
    );
  }

  Future<void> _validar() async {
    final claveLimpia = _limpiarCodigo(_clave.text);

    if (claveLimpia.isEmpty) {
      alertaError(context, 'Escanea la clave del usuario destino');
      return;
    }

    ref.read(kioskProvider).registerActivity();
    setState(() => _loading = true);

    try {
      final res = await ApiService.validarUsuario(claveLimpia);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        final data   = res['data'] as Map<String, dynamic>;
        final origen = ref.read(traspasoProvider).origen;

        // ✅ CORREGIDO: comparar con 'Stand' (mayúscula)
        if (origen != null &&
            data['Stand']?.toString() == origen['Stand']?.toString()) {
          alertaError(
            context,
            'El destino debe ser un stand diferente al origen',
          );
          _clave.clear();
          return;
        }

        ref.read(traspasoProvider.notifier).setDestino(data);
      } else {
        // ✅ CORREGIDO: era res['mensaje'], debe ser res['message']
        alertaError(context, res['message'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión');
      debugPrint('Error validación destino: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _cancelar() {
    alertaConfirmar(
      context,
      '¿Seguro que deseas cancelar?',
      () {
        ref.read(traspasoProvider.notifier).limpiar();
        Navigator.popUntil(context, (r) => r.isFirst);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov        = ref.watch(traspasoProvider);
    final destinoListo = prov.destino != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuario Destino')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (prov.origen != null) _infoCard('Origen', prov.origen!),
            const SizedBox(height: 24),

            if (!destinoListo) ...[
              const Icon(Icons.person_search_rounded,
                  size: 48, color: Color(0xFF42A5F5)),
              const SizedBox(height: 8),
              const Text(
                'Escanea el usuario destino',
                style: TextStyle(color: Color(0xFF90CAF9)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              CampoCodigo(
                controller: _clave,
                label: 'Clave Secreta (código de barras)',
                ocultable: true,
                onSubmitted: (_) => _validar(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 55,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('ENVIAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF42A5F5),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _validar,
                      ),
              ),
            ],

            if (destinoListo) ...[
              _infoCard('Destino', prov.destino!),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined,
                          color: Colors.redAccent),
                      label: const Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onPressed: _cancelar,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Continuar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LineasScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}