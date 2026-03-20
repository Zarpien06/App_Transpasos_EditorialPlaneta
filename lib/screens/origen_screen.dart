import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/traspaso_provider.dart';
import '../services/api_service.dart';
import '../widgets/campo_codigo.dart';
import '../widgets/alerts.dart';
import 'destino_screen.dart';

class OrigenScreen extends StatefulWidget {
  const OrigenScreen({super.key});

  @override
  State<OrigenScreen> createState() => _OrigenScreenState();
}

class _OrigenScreenState extends State<OrigenScreen> {
  final _clave = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  String _limpiarCodigo(String code) => code.replaceAll(']C1', '').trim();

  Future<void> _validar() async {
    final claveLimpia = _limpiarCodigo(_clave.text);

    if (claveLimpia.isEmpty) {
      alertaError(context, 'Ingresa la clave secreta');
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await ApiService.validarUsuario(claveLimpia);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        context.read<TraspasoProvider>().setOrigen(res['data']);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DestinoScreen()),
        );
      } else {
        alertaError(context, res['mensaje'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión con el servidor');
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
            Center(
              child: Image.asset('assets/img/planeta-icon-v2.png', width: 120),
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
                      label: const Text('ENVIAR', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF42A5F5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _validar,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}