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
  String? _ultimoAgregado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _foco.requestFocus());
  }

  @override
  void dispose() {
    _codigo.dispose();
    _foco.dispose();
    super.dispose();
  }

  // ── Escanear / Enter ───────────────────────────────────────────
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
        _mostrarDialogoCantidad(libro);
      } else {
        _mostrarDialogoNoEncontrado(codigo);
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Diálogo cantidad ───────────────────────────────────────────
  void _mostrarDialogoCantidad(Map<String, dynamic> libro) {
    final cantCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.book_rounded, color: Color(0xFF29B6F6), size: 20),
            const SizedBox(width: 8),
            const Text('Libro encontrado', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              libro['descripcion'] ?? libro['codigo'] ?? '-',
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              libro['codigo'] ?? '',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
            const SizedBox(height: 16),
            const Text('Cantidad (máx. 99)',
                style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: cantCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _MaxValueFormatter(99),
              ],
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF242424),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              onSubmitted: (_) => _confirmarCantidad(ctx, libro, cantCtrl),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _foco.requestFocus();
            },
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Agregar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _confirmarCantidad(ctx, libro, cantCtrl),
          ),
        ],
      ),
    );
  }

  void _confirmarCantidad(
      BuildContext ctx, Map<String, dynamic> libro, TextEditingController cantCtrl) {
    final cant = int.tryParse(cantCtrl.text) ?? 1;
    final cantFinal = cant.clamp(1, 99);

    context.read<TraspasoProvider>().agregarProducto({
      ...libro,
      'cantidad': cantFinal,
    });
    HapticFeedback.lightImpact();
    setState(() => _ultimoAgregado =
        '${libro['descripcion'] ?? libro['codigo']} x$cantFinal');
    Navigator.pop(ctx);
    _foco.requestFocus();
  }

  // ── No encontrado: pide descripción y guarda en BD ─────────────
  void _mostrarDialogoNoEncontrado(String codigo) {
    final descCtrl = TextEditingController();
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  color: Color(0xFFFFA726), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('No encontrado',
                    style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Código: $codigo',
                    style: const TextStyle(
                        color: Color(0xFF90CAF9), fontSize: 12)),
              ),
              const SizedBox(height: 14),
              const Text('Ingresa el nombre del libro\npara guardarlo en la base de datos:',
                  style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12)),
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onSubmitted: (v) async {
                  if (v.trim().isEmpty) return;
                  await _guardarYContinuar(
                      ctx, codigo, v.trim(), setStateDialog,
                      () => guardando, (val) => guardando = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: guardando
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _foco.requestFocus();
                    },
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF888888))),
            ),
            ElevatedButton.icon(
              icon: guardando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(guardando ? 'Guardando...' : 'Guardar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: guardando
                  ? null
                  : () async {
                      final desc = descCtrl.text.trim();
                      if (desc.isEmpty) return;
                      await _guardarYContinuar(
                          ctx, codigo, desc, setStateDialog,
                          () => guardando, (val) => guardando = val);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardarYContinuar(
    BuildContext ctx,
    String codigo,
    String descripcion,
    StateSetter setStateDialog,
    bool Function() getGuardando,
    void Function(bool) setGuardando,
  ) async {
    setStateDialog(() => setGuardando(true));
    try {
      await ApiService.guardarLibro(
        ean: codigo.length > 7 ? codigo : '',
        ref: codigo.length <= 7 ? codigo : '',
        descripcion: descripcion,
      );
    } catch (_) {
      // Si falla igual continúa localmente
    }
    if (!mounted) return;
  
    // Cierra el diálogo usando el navigator del contexto del widget, no del dialog
    Navigator.of(context).pop();
  
    _mostrarDialogoCantidad({
      'codigo':      codigo,
      'descripcion': descripcion,
      'manual':      true,
    });
  }

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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [

            // ── Chips origen / destino ──────────────────────────
            Row(
              children: [
                Expanded(child: _chip('Origen',
                    '${prov.origen?['almacen'] ?? '-'} · Stand ${prov.origen?['stand'] ?? '-'}',
                    Icons.logout_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _chip('Destino',
                    '${prov.destino?['almacen'] ?? '-'} · Stand ${prov.destino?['stand'] ?? '-'}',
                    Icons.login_rounded)),
              ],
            ),
            const SizedBox(height: 14),

            // ── Campo escaneo ───────────────────────────────────
            CampoCodigo(
              controller: _codigo,
              focusNode:  _foco,
              label: 'Escanea o escribe EAN / Referencia...',
              ocultable: false,
              onSubmitted: _escanear,
            ),
            const SizedBox(height: 10),

            // ── Feedback último agregado ────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _ultimoAgregado != null
                  ? Container(
                      key: ValueKey(_ultimoAgregado),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D2E0D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF43A047)
                                .withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF43A047), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _ultimoAgregado!,
                              style: const TextStyle(
                                  color: Color(0xFF81C784), fontSize: 13),
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

            // ── Totales ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.4)),
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
                      Text(
                        'Refs: ${prov.items.length}',
                        style: const TextStyle(
                            color: Color(0xFF90CAF9), fontSize: 13),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Total: ',
                          style: TextStyle(
                              color: Color(0xFF90CAF9), fontSize: 13)),
                      Text('${prov.total}',
                          style: const TextStyle(
                              color: Color(0xFF29B6F6),
                              fontWeight: FontWeight.w800,
                              fontSize: 22)),
                    ],
                  ),
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
                              color: const Color(0xFF1565C0)
                                  .withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text('Escanea un libro para comenzar',
                              style: TextStyle(
                                  color: Color(0xFF555555), fontSize: 14)),
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
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: esManual
                                  ? const Color(0xFF4A1080)
                                      .withValues(alpha: 0.25)
                                  : const Color(0xFF0D47A1)
                                      .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              esManual
                                  ? Icons.edit_rounded
                                  : Icons.book_rounded,
                              color: esManual
                                  ? const Color(0xFFCE93D8)
                                  : const Color(0xFF29B6F6),
                              size: 18,
                            ),
                          ),
                          title: Text(
                            item['descripcion'] ?? item['codigo'] ?? '-',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              Text(item['codigo'] ?? '',
                                  style: const TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 11)),
                              if (esManual) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4A1080)
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('nuevo',
                                      style: TextStyle(
                                          color: Color(0xFFCE93D8),
                                          fontSize: 10)),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Cantidad editable con tap
                              GestureDetector(
                                onTap: () =>
                                    _editarCantidad(context, prov, i, item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D47A1)
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF1565C0)
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('x${item['cantidad']}',
                                          style: const TextStyle(
                                              color: Color(0xFF29B6F6),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit_rounded,
                                          size: 11,
                                          color: Color(0xFF1565C0)),
                                    ],
                                  ),
                                ),
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
                    style: TextStyle(
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
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

  // ── Editar cantidad de un item ya agregado ─────────────────────
  void _editarCantidad(
      BuildContext context, TraspasoProvider prov, int i, Map item) {
    final cantCtrl =
        TextEditingController(text: '${item['cantidad']}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Editar cantidad',
            style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item['descripcion'] ?? item['codigo'] ?? '-',
              style: const TextStyle(
                  color: Color(0xFF888888), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: cantCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _MaxValueFormatter(99),
              ],
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF242424),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              onSubmitted: (_) {
                _aplicarCantidad(ctx, prov, i, cantCtrl);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _aplicarCantidad(ctx, prov, i, cantCtrl),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _aplicarCantidad(BuildContext ctx, TraspasoProvider prov, int i,
      TextEditingController cantCtrl) {
    final cant = (int.tryParse(cantCtrl.text) ?? 1).clamp(1, 99);
    prov.actualizarCantidad(i, cant);
    Navigator.pop(ctx);
    _foco.requestFocus();
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
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 10)),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formatter: limita valor máximo a 99 ───────────────────────────
class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  _MaxValueFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final val = int.tryParse(newValue.text) ?? 0;
    if (val > max) {
      return oldValue;
    }
    return newValue;
  }
}