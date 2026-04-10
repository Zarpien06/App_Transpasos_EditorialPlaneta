// lib/screens/lineas_screen.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/traspaso_provider.dart';
import '../services/api_service.dart';
import '../widgets/campo_codigo.dart';
import '../widgets/alerts.dart';
import 'factura_screen.dart';
import '../core/constants.dart';
import '../core/device_service.dart';
import '../main.dart';

class LineasScreen extends ConsumerStatefulWidget {
  const LineasScreen({super.key});

  @override
  ConsumerState<LineasScreen> createState() => _LineasScreenState();
}

class _LineasScreenState extends ConsumerState<LineasScreen> {
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

  String _limpiarCodigo(String code) {
    return code
        .replaceAll(']C1', '')
        .replaceAll(']E0', '')
        .replaceAll(']Q',  '')
        .trim();
  }

  void _registrarActividad() {
    if (mounted) ref.read(kioskProvider).registerActivity();
  }

  TraspasoNotifier get _notifier => ref.read(traspasoProvider.notifier);

  // ─────────────────────────────────────────────────────────────────────────
  // ESCANEAR
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _escanear(String raw) async {
    final codigo = _limpiarCodigo(raw);
    if (codigo.isEmpty) return;

    _codigo.clear();
    _registrarActividad();

    if (_notifier.disponibles <= 0) {
      alertaError(
        context,
        'No puedes agregar más libros. '
        'Se alcanzó el límite de $kMaxTotal unidades.',
      );
      _foco.requestFocus();
      return;
    }

    setState(() {
      _loading = true;
      _ultimoAgregado = null;
    });

    try {
      final res = await ApiService.buscarLibro(codigo);
      if (!mounted) return;

      if (res['status'] == 'ok') {
        final producto = res['producto'];
        if (producto == null) {
          _mostrarDialogoNoEncontrado(codigo);
          return;
        }

        final libro       = Map<String, dynamic>.from(producto as Map);
        final codigoLibro = libro['codigo']?.toString() ?? codigo;

        if (_notifier.existe(codigoLibro)) {
          _mostrarDialogoYaExiste(libro);
        } else {
          _mostrarDialogoCantidad(libro, esNuevo: false);
        }
      } else {
        _mostrarDialogoNoEncontrado(codigo);
      }
    } catch (e) {
      if (!mounted) return;
      alertaError(context, 'Error de conexión');
      debugPrint('Error escanear: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DIÁLOGO: libro ya está en la lista
  // ─────────────────────────────────────────────────────────────────────────
  void _mostrarDialogoYaExiste(Map<String, dynamic> libro) {
    final notifier   = _notifier;
    final idx        = notifier.indexOf(libro['codigo']?.toString() ?? '');
    final cantActual = idx != -1
        ? (notifier.items[idx]['cantidad'] as int? ?? 0)
        : 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: Color(0xFFFFA726), size: 22),
            SizedBox(width: 8),
            Text('Libro ya agregado', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              libro['descripcion']?.toString() ?? libro['codigo']?.toString() ?? '-',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'Cantidad actual: $cantActual  ·  Disponibles: ${notifier.disponibles}',
              style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              '¿Deseas agregar más unidades?',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _foco.requestFocus();
            },
            child: const Text('No, cancelar',
                style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Sí, agregar más'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _mostrarDialogoCantidad(libro, esNuevo: false);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DIÁLOGO: ingresar cantidad
  // ─────────────────────────────────────────────────────────────────────────
  void _mostrarDialogoCantidad(Map<String, dynamic> libro,
      {required bool esNuevo}) {
    final disponibles = _notifier.disponibles;

    final cantCtrl = TextEditingController(text: '1')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    int valorCantidad = 1;

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
              Icon(
                esNuevo
                    ? Icons.add_circle_outline_rounded
                    : Icons.book_rounded,
                color: const Color(0xFF29B6F6),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                esNuevo ? 'Nuevo libro' : 'Libro encontrado',
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                libro['descripcion']?.toString() ?? libro['codigo']?.toString() ?? '-',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                libro['codigo']?.toString() ?? '',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
              const SizedBox(height: 16),
              Text(
                'Cantidad (máx. disponible: $disponibles)',
                style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cantCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onTap: () => cantCtrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: cantCtrl.text.length,
                ),
                onChanged: (v) {
                  valorCantidad =
                      (int.tryParse(v) ?? 1).clamp(1, disponibles).toInt();
                },
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _MaxValueFormatter(disponibles),
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
                onSubmitted: (_) =>
                    _confirmarCantidad(ctx, libro, valorCantidad),
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
              onPressed: () => _confirmarCantidad(ctx, libro, valorCantidad),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarCantidad(
      BuildContext ctx, Map<String, dynamic> libro, int cantidad) {
    final resultado = _notifier.agregarProducto(libro, cantidad);
    Navigator.pop(ctx);

    if (resultado == AgregarResultado.excedeLimite) {
      alertaError(
        context,
        'No se puede agregar. Se excede el límite de $kMaxTotal unidades.\n'
        'Disponibles: ${_notifier.disponibles}',
      );
    } else {
      HapticFeedback.lightImpact();
      setState(() => _ultimoAgregado =
          '${libro['descripcion'] ?? libro['codigo']} x$cantidad');
    }

    _foco.requestFocus();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DIÁLOGO: libro no encontrado → ingresar manualmente
  // ─────────────────────────────────────────────────────────────────────────
  void _mostrarDialogoNoEncontrado(String codigo) {
    if (_notifier.existe(codigo)) {
      _mostrarDialogoYaExiste({'codigo': codigo});
      return;
    }

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
          title: const Row(
            children: [
              Icon(Icons.help_outline_rounded,
                  color: Color(0xFFFFA726), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text('No encontrado', style: TextStyle(fontSize: 15)),
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
                child: Text(
                  'Código: $codigo',
                  style: const TextStyle(
                      color: Color(0xFF90CAF9), fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ingresa el nombre del libro\npara guardarlo en la base de datos:',
                style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
              ),
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
                    ctx, codigo, v.trim(),
                    setStateDialog,
                    () => guardando,
                    (val) => guardando = val,
                  );
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
                      width: 14, height: 14,
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
                        ctx, codigo, desc,
                        setStateDialog,
                        () => guardando,
                        (val) => guardando = val,
                      );
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
      // Si la API falla, el libro igual se agrega localmente
    } finally {
      setStateDialog(() => setGuardando(false));
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    _mostrarDialogoCantidad(
      {
        'codigo':      codigo,
        'descripcion': descripcion,
        'manual':      true,
      },
      esNuevo: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIRMAR TRASPASO  ← ÚNICO CAMBIO: obtiene deviceId antes de navegar
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _confirmarTraspaso() async {
    final notifier = _notifier;

    if (notifier.items.isEmpty) {
      alertaError(context, 'Agrega al menos un libro');
      return;
    }

    _registrarActividad();

    alertaConfirmar(context, '¿Confirmar el traspaso?', () async {
      try {
        final res = await ApiService.registrarTraspaso({
          'origen':  notifier.origen,
          'destino': notifier.destino,
          'items':   notifier.items,
        });
        if (!mounted) return;

        if (res['status'] == 'ok') {
          if (res['numero_movimiento'] != null) {
            notifier.setNumeroMovimiento(
                res['numero_movimiento'].toString());
          }

          // ✅ CORREGIDO: obtenemos el deviceId aquí, cuando la red ya funcionó,
          // y lo pasamos a FacturaScreen para que no haga ninguna llamada de red.
          final deviceId = await DeviceService().getDeviceId();
          if (!mounted) return;

          alertaExito(
            context,
            '¡Traspaso hecho!',
            onOk: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FacturaScreen(deviceId: deviceId),
              ),
            ),
          );
        } else {
          alertaError(context, res['message'] ?? res['mensaje'] ?? 'Error al registrar');
        }
      } catch (_) {
        if (!mounted) return;
        alertaError(context, 'Error de conexión');
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EDITAR CANTIDAD
  // ─────────────────────────────────────────────────────────────────────────
  void _editarCantidad(
      BuildContext context, int i, Map<String, dynamic> item) {
    final cantidadActual = (item['cantidad'] as int?) ?? 1;
    final maxPermitido   = cantidadActual + _notifier.disponibles;

    final cantCtrl = TextEditingController(text: '$cantidadActual')
      ..selection = TextSelection(
          baseOffset: 0, extentOffset: '$cantidadActual'.length);
    int valorCantidad = cantidadActual;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Editar cantidad',
              style: TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item['descripcion']?.toString() ?? item['codigo']?.toString() ?? '-',
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Máximo permitido: $maxPermitido',
                style: const TextStyle(
                    color: Color(0xFFBBBBBB), fontSize: 11),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: cantCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onTap: () => cantCtrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: cantCtrl.text.length,
                ),
                onChanged: (v) {
                  valorCantidad =
                      (int.tryParse(v) ?? 1).clamp(1, maxPermitido).toInt();
                },
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _MaxValueFormatter(maxPermitido),
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
                onSubmitted: (_) =>
                    _aplicarCantidad(ctx, i, valorCantidad),
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
              onPressed: () => _aplicarCantidad(ctx, i, valorCantidad),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _aplicarCantidad(BuildContext ctx, int i, int cantidad) {
    final ok = _notifier.actualizarCantidad(i, cantidad);
    Navigator.pop(ctx);
    if (!ok) {
      alertaError(
        context,
        'No se puede guardar. Se excede el límite de $kMaxTotal unidades.',
      );
    }
    _foco.requestFocus();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(traspasoProvider);

    final origenAlmacen  = state.origen?['Codigo_Almacen']  ?? state.origen?['almacen']  ?? '-';
    final origenStand    = state.origen?['Stand']            ?? state.origen?['stand']    ?? '-';
    final destinoAlmacen = state.destino?['Codigo_Almacen'] ?? state.destino?['almacen'] ?? '-';
    final destinoStand   = state.destino?['Stand']           ?? state.destino?['stand']   ?? '-';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Líneas de Traspaso')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [

            // ── CHIPS ORIGEN / DESTINO ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _chip(
                    'Origen',
                    '$origenAlmacen · Stand $origenStand',
                    Icons.logout_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _chip(
                    'Destino',
                    '$destinoAlmacen · Stand $destinoStand',
                    Icons.login_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── CAMPO ESCANEO ──────────────────────────────────────────
            CampoCodigo(
              controller: _codigo,
              focusNode:  _foco,
              label: 'Escanea o escribe EAN / Referencia...',
              ocultable: false,
              onSubmitted: _escanear,
            ),
            const SizedBox(height: 10),

            // ── FEEDBACK ÚLTIMO AGREGADO ───────────────────────────────
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
                              .withValues(alpha: 0.5),
                        ),
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

            // ── TOTALES ────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                ),
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
                        'Refs: ${state.items.length}',
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
                      Text(
                        '${state.total}',
                        style: const TextStyle(
                            color: Color(0xFF29B6F6),
                            fontWeight: FontWeight.w800,
                            fontSize: 22),
                      ),
                      Text(
                        ' / $kMaxTotal',
                        style: const TextStyle(
                            color: Color(0xFF555555), fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── LISTA DE ITEMS ─────────────────────────────────────────
            Expanded(
              child: state.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 56,
                            color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Escanea un libro para comenzar',
                            style: TextStyle(
                                color: Color(0xFF555555), fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: state.items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Color(0xFF242424), height: 1),
                      itemBuilder: (context, i) {
                        final item     = state.items[i];
                        final esManual = item['manual'] == true;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: esManual
                                  ? const Color(0xFF4A1080).withValues(alpha: 0.25)
                                  : const Color(0xFF0D47A1).withValues(alpha: 0.25),
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
                            item['descripcion']?.toString() ?? item['codigo']?.toString() ?? '-',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                item['codigo']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Color(0xFF888888), fontSize: 11),
                              ),
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
                                  child: const Text(
                                    'nuevo',
                                    style: TextStyle(
                                        color: Color(0xFFCE93D8),
                                        fontSize: 10),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    _editarCantidad(context, i, item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D47A1)
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF1565C0)
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'x${item['cantidad']}',
                                        style: const TextStyle(
                                            color: Color(0xFF29B6F6),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13),
                                      ),
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
                                  () => _notifier.eliminarProducto(i),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // ── BOTÓN CONFIRMAR TRASPASO ───────────────────────────────
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text(
                  'CONFIRMAR TRASPASO',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 8,
                ),
                onPressed: _confirmarTraspaso,
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
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 10)),
                Text(
                  value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  const _MaxValueFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final val = int.tryParse(newValue.text) ?? 0;
    if (val > max) return oldValue;
    return newValue;
  }
}