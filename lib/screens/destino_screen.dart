import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/traspaso_provider.dart';
import '../services/api_service.dart';
import '../widgets/campo_codigo.dart';
import '../widgets/alerts.dart';
import 'lineas_screen.dart';

class DestinoScreen extends StatefulWidget {
  const DestinoScreen({super.key});
  @override
  State<DestinoScreen> createState() => _DestinoScreenState();
}

class _DestinoScreenState extends State<DestinoScreen> {
  final _clave = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  String _limpiarCodigo(String code) => code.replaceAll(']C1', '').trim();

  Widget _infoCard(String titulo, Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF1565C0).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Color(0xFF42A5F5), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('🏪 Almacén: ${data['almacen'] ?? '-'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          Text('📍 Stand: ${data['stand'] ?? '-'}',
              style: const TextStyle(color: Color(0xFFB0BEC5))),
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

    setState(() => _loading = true);

    try {
      final res = await ApiService.validarUsuario(claveLimpia);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        final prov   = context.read<TraspasoProvider>();
        final data   = res['data'] as Map<String, dynamic>;
        final origen = prov.origen;

        // ── Mismo stand = no permitido ──────────────────────────
        if (origen != null && data['stand'] == origen['stand']) {
          alertaError(context,
              'El destino debe ser un stand diferente al origen');
          _clave.clear();
          setState(() => _loading = false);
          return;
        }

        prov.setDestino(data);
        setState(() {});
      } else {
        alertaError(context, res['mensaje'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov        = context.watch<TraspasoProvider>();
    final destinoListo = prov.destino != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Usuario Destino')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Card origen ─────────────────────────────────────
            if (prov.origen != null) _infoCard('Origen', prov.origen!),
            const SizedBox(height: 24),

            // ── Campo + botón — solo si destino no está listo ───
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
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('ENVIAR'),
                  onPressed: _validar,
                ),
            ],

            // ── Card destino — cuando ya está listo ─────────────
            if (destinoListo) ...[
              _infoCard('Destino', prov.destino!),
              const SizedBox(height: 24),

              // Botones cancelar / continuar
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel_outlined,
                          color: Colors.redAccent),
                      label: const Text('Cancelar',
                          style: TextStyle(color: Colors.redAccent)),
                      onPressed: () => alertaConfirmar(
                        context,
                        '¿Seguro que deseas cancelar?',
                        () {
                          prov.limpiar();
                          Navigator.popUntil(context, (r) => r.isFirst);
                        },
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Continuar'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LineasScreen()),
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