import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/traspaso_provider.dart';
import '../services/api_service.dart';
import '../widgets/campo_codigo.dart';
import '../widgets/alerts.dart';
import 'factura_screen.dart';

class LineasScreen extends StatefulWidget {
  const LineasScreen({super.key});
  @override
  State<LineasScreen> createState() => _LineasScreenState();
}

class _LineasScreenState extends State<LineasScreen> {
  final _codigo = TextEditingController();
  final _foco   = FocusNode();
  bool _loading = false;
  String? _ultimoAgregado; // feedback visual del último libro

  @override
  void initState() {
    super.initState();
    // Foco automático al entrar a la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) => _foco.requestFocus());
  }

  @override
  void dispose() {
    _codigo.dispose();
    _foco.dispose();
    super.dispose();
  }

  // ── Escanear: agregar inmediato ────────────────────────────────
  Future<void> _escanear(String raw) async {
    final codigo = raw.replaceAll(']C1', '').trim();
    if (codigo.isEmpty) return;

    _codigo.clear();
    setState(() { _loading = true; _ultimoAgregado = null; });

    try {
      final res = await ApiService.buscarLibro(codigo);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        final libro = Map<String, dynamic>.from(res['data']);
        context.read<TraspasoProvider>().agregarProducto({...libro, 'cantidad': 1});
        HapticFeedback.lightImpact();
        setState(() => _ultimoAgregado = libro['descripcion'] ?? codigo);
      } else {
        // No existe — preguntar si agrega manual
        _mostrarDialogoNoEncontrado(codigo);
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _foco.requestFocus(); // vuelve el foco para el siguiente escaneo
      }
    }
  }

  // ── No encontrado: pide nombre y agrega ────────────────────────
  void _mostrarDialogoNoEncontrado(String codigo) {
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: Color(0xFFFFA726), size: 22),
            const SizedBox(width: 8),
            const Text('No encontrado', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Código: $codigo',
                style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 12)),
            const SizedBox(height: 16),
            const Text('¿Cómo se llama este libro?',
                style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Descripción del libro...',
                hintStyle: const TextStyle(color: Color(0xFF555555)),
                filled: true,
                fillColor: const Color(0xFF242424),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  _agregarManual(codigo, v.trim());
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _foco.requestFocus();
            },
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final desc = descCtrl.text.trim();
              if (desc.isEmpty) return;
              _agregarManual(codigo, desc);
              Navigator.pop(ctx);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _agregarManual(String codigo, String descripcion) {
    context.read<TraspasoProvider>().agregarProducto({
      'codigo':      codigo.isEmpty ? 'MANUAL' : codigo,
      'descripcion': descripcion,
      'cantidad':    1,
      'manual':      true,
    });
    HapticFeedback.lightImpact();
    setState(() => _ultimoAgregado = descripcion);
    _foco.requestFocus();
  }

  // ── Manual desde cero (FAB) ────────────────────────────────────
  void _mostrarDialogoManual() {
    final descCtrl = TextEditingController();
    final codCtrl  = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Agregar manual',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Sin código de barras',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: codCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('Código (opcional)', Icons.qr_code_rounded),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('Descripción *', Icons.book_rounded),
              onSubmitted: (_) => _guardarManual(ctx, codCtrl, descCtrl),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('AGREGAR',
                    style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _guardarManual(ctx, codCtrl, descCtrl),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _guardarManual(BuildContext ctx, TextEditingController cod, TextEditingController desc) {
    if (desc.text.trim().isEmpty) {
      alertaError(ctx, 'Ingresa una descripción');
      return;
    }
    _agregarManual(cod.text.trim(), desc.text.trim());
    Navigator.pop(ctx);
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF888888)),
    prefixIcon: Icon(icon, color: const Color(0xFF29B6F6), size: 18),
    filled: true,
    fillColor: const Color(0xFF1A1A1A),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF242424)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF242424)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF29B6F6), width: 1.5),
    ),
  );

  Future<void> _confirmarTraspaso() async {
    final prov = context.read<TraspasoProvider>();
    if (prov.items.isEmpty) {
      alertaError(context, 'Agrega al menos un libro');
      return;
    }
    alertaConfirmar(context, '¿Confirmar el traspaso?', () async {
      try {
        final res = await ApiService.registrarTraspaso({
          'origen':  prov.origen,
          'destino': prov.destino,
          'items':   prov.items,
        });
        if (!mounted) return;
        if (res['status'] == 'ok') {
          if (res['numero_movimiento'] != null) {
            prov.setNumeroMovimiento(res['numero_movimiento'].toString());
          }
          alertaExito(context, '¡Traspaso hecho!',
              onOk: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FacturaScreen())));
        } else {
          alertaError(context, res['mensaje'] ?? 'Error al registrar');
        }
      } catch (e) {
        if (!mounted) return;
        alertaError(context, 'Error de conexión');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TraspasoProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Líneas de Traspaso')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoManual,
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Manual', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [

            // ── Chips origen / destino ──────────────────────────
            Row(
              children: [
                Expanded(child: _chip('Origen',  prov.origen?['usuario']  ?? '-', Icons.logout_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _chip('Destino', prov.destino?['usuario'] ?? '-', Icons.login_rounded)),
              ],
            ),
            const SizedBox(height: 14),

            // ── Campo escaneo (invisible, solo captura) ─────────
            CampoCodigo(
              controller: _codigo,
              focusNode:  _foco,
              label: 'Escanea el código de barras...',
              ocultable: false,
              onSubmitted: _escanear,
            ),
            const SizedBox(height: 10),

            // ── Feedback último libro agregado ──────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _ultimoAgregado != null
                  ? Container(
                      key: ValueKey(_ultimoAgregado),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D2E0D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF43A047), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _ultimoAgregado!,
                              style: const TextStyle(color: Color(0xFF81C784), fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(key: ValueKey('empty'), height: 0),
            ),

            const SizedBox(height: 10),

            // ── Total ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (_loading)
                        const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.library_books_rounded,
                            color: Color(0xFF29B6F6), size: 18),
                      const SizedBox(width: 8),
                      const Text('Total libros',
                          style: TextStyle(color: Color(0xFF90CAF9), fontSize: 13)),
                    ],
                  ),
                  Text('${prov.total}',
                      style: const TextStyle(
                          color: Color(0xFF29B6F6),
                          fontWeight: FontWeight.w800,
                          fontSize: 22)),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Lista ───────────────────────────────────────────
            Expanded(
              child: prov.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded,
                              size: 56,
                              color: const Color(0xFF1565C0).withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text('Escanea un libro para comenzar',
                              style: TextStyle(color: Color(0xFF555555), fontSize: 14)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: prov.items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Color(0xFF242424), height: 1),
                      itemBuilder: (context, i) {
                        final item     = prov.items[i];
                        final esManual = item['manual'] == true;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: esManual
                                  ? const Color(0xFF4A1080).withValues(alpha: 0.25)
                                  : const Color(0xFF0D47A1).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              esManual ? Icons.edit_rounded : Icons.book_rounded,
                              color: esManual
                                  ? const Color(0xFFCE93D8)
                                  : const Color(0xFF29B6F6),
                              size: 18,
                            ),
                          ),
                          title: Text(
                            item['descripcion'] ?? item['codigo'] ?? '-',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              Text(item['codigo'] ?? '',
                                  style: const TextStyle(
                                      color: Color(0xFF888888), fontSize: 11)),
                              if (esManual) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4A1080).withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('manual',
                                      style: TextStyle(
                                          color: Color(0xFFCE93D8), fontSize: 10)),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D47A1).withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('x${item['cantidad']}',
                                    style: const TextStyle(
                                        color: Color(0xFF29B6F6),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFCF6679), size: 20),
                                onPressed: () => alertaConfirmar(
                                    context,
                                    '¿Eliminar este libro?',
                                    () => prov.eliminarProducto(i)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // ── Confirmar ───────────────────────────────────────
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('CONFIRMAR TRASPASO',
                    style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
                onPressed: _confirmarTraspaso,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF29B6F6), size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 10)),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}