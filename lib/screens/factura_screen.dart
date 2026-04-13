// lib/screens/factura_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../core/pdf_fonts.dart';
import '../providers/traspaso_provider.dart';
import 'dashboard_screen.dart';
import '../main.dart';

// ── Dimensiones del ticket 80mm ───────────────────────────────────────────────
const double _colRef  = 30 * PdfPageFormat.mm; // columna referencia
const double _colCant = 12 * PdfPageFormat.mm; // columna cantidad

class FacturaScreen extends ConsumerStatefulWidget {
  final String deviceId;
  const FacturaScreen({super.key, required this.deviceId});

  @override
  ConsumerState<FacturaScreen> createState() => _FacturaScreenState();
}

class _FacturaScreenState extends ConsumerState<FacturaScreen> {
  pw.MemoryImage? _logoImage;
  bool _loadingAssets = true;

  late final String _fecha;
  late final String _hora;
  late final String _numDispositivo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha          = DateFormat('yyyy/MM/dd').format(now);
    _hora           = DateFormat('HH:mm:ss').format(now);
    _numDispositivo = widget.deviceId.replaceAll('DV', '');
    _precargar();
  }

  Future<void> _precargar() async {
    await PdfFonts.load();
    final ByteData bytes =
        await rootBundle.load('assets/img/icon-planeta-removebg-preview.png');
    if (mounted) {
      setState(() {
        _logoImage     = pw.MemoryImage(bytes.buffer.asUint8List());
        _loadingAssets = false;
      });
    }
  }

  void _irAlDashboard(BuildContext ctx) {
    ref.read(traspasoProvider.notifier).limpiar();
    Navigator.of(ctx).pop();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (_) => false,
    );
  }

  // ── PDF ──────────────────────────────────────────────────────────────────────
  Future<void> _imprimir() async {
    if (_logoImage == null) return;
    ref.read(kioskProvider).registerActivity();

    final ts       = ref.read(traspasoProvider);
    final font     = PdfFonts.regular!;
    final fontBold = PdfFonts.bold!;
    final pdf      = pw.Document();

    // ── Altura generosa para que nunca se corten los totales ──────────────
    // cabecera fija 115mm + cada línea 22mm + pie 30mm + margen extra 10mm
    const double cabeceraMm = 200.0;
    const double lineaMm    = 100.0;
    const double pieMm      = 50.0;
    const double extraMm    = 50.0;
    final double totalMm =
        cabeceraMm + (ts.items.length * lineaMm) + pieMm + extraMm;

    final origenAlmacen  = ts.origen?['Codigo_Almacen']?.toString() ?? '—';
    final origenStand    = ts.origen?['Stand']?.toString()          ?? '—';
    final destinoAlmacen = ts.destino?['Codigo_Almacen']?.toString() ?? '—';
    final destinoStand   = ts.destino?['Stand']?.toString()          ?? '—';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          totalMm * PdfPageFormat.mm,
          marginLeft:   5 * PdfPageFormat.mm,
          marginRight:  5 * PdfPageFormat.mm,
          marginTop:    6 * PdfPageFormat.mm,
          marginBottom: 10 * PdfPageFormat.mm,  // margen inferior amplio
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            // ── LOGO + EMPRESA ──────────────────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(_logoImage!, width: 34, height: 34),
                pw.SizedBox(width: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('EDITORIAL PLANETA',
                        style: pw.TextStyle(font: fontBold, fontSize: 15)),
                    pw.Text('COLOMBIANA S.A.',
                        style: pw.TextStyle(font: fontBold, fontSize: 15)),
                  ],
                ),
              ],
            ),

            pw.Divider(thickness: 0.8),

            // ── DISPOSITIVO + MOVIMIENTO ────────────────────────────────────
            pw.Center(
              child: pw.Text(
                'Dispositivo $_numDispositivo  |  Mov. #${ts.numeroMovimiento ?? '-'}',
                style: pw.TextStyle(font: fontBold, fontSize: 13),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'Fecha: $_fecha     Hora: $_hora',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            ),

            pw.Divider(thickness: 0.8),

            // ── TÍTULO ──────────────────────────────────────────────────────
            pw.Center(
              child: pw.Text(
                'TRASPASOS',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ),

            pw.Divider(thickness: 0.8),

            // ── DESDE / HASTA ───────────────────────────────────────────────
            pw.Text('Desde: $origenAlmacen   Stand: $origenStand',
                style: pw.TextStyle(font: fontBold, fontSize: 11)),
            pw.SizedBox(height: 3),
            pw.Text('Hasta: $destinoAlmacen   Stand: $destinoStand',
                style: pw.TextStyle(font: fontBold, fontSize: 11)),

            pw.Divider(thickness: 0.8),

            // ── ENCABEZADO DE COLUMNAS ──────────────────────────────────────
            pw.Row(
              children: [
                pw.SizedBox(
                  width: _colRef,
                  child: pw.Text('Ref',
                      style: pw.TextStyle(font: fontBold, fontSize: 11)),
                ),
                pw.Expanded(
                  child: pw.Text('Descripción',
                      style: pw.TextStyle(font: fontBold, fontSize: 11)),
                ),
                pw.SizedBox(
                  width: _colCant,
                  child: pw.Text('Cant',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: fontBold, fontSize: 11)),
                ),
              ],
            ),

            pw.Divider(thickness: 0.8),

            // ── LÍNEAS DE PRODUCTO ──────────────────────────────────────────
            ...ts.items.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: _colRef,
                      child: pw.Text(
                        item['codigo']?.toString() ?? '',
                        style: pw.TextStyle(font: font, fontSize: 10),
                        softWrap: true,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        item['descripcion']?.toString() ?? '',
                        style: pw.TextStyle(font: font, fontSize: 10),
                        softWrap: true,
                      ),
                    ),
                    pw.SizedBox(
                      width: _colCant,
                      child: pw.Text(
                        '${item['cantidad']}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            pw.Divider(thickness: 0.8),

            // ── TOTALES ─────────────────────────────────────────────────────
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Referencias: ${ts.items.length}',
                    style: pw.TextStyle(font: fontBold, fontSize: 12)),
                pw.Text('Total: ${ts.total}',
                    style: pw.TextStyle(font: fontBold, fontSize: 12)),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Center(
              child: pw.Text(
                '.',
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            ),
            
            pw.SizedBox(height: 20),
        
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
    if (mounted) _mostrarAlertaExito();
  }

  void _mostrarAlertaExito() {
    final ts = ref.read(traspasoProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.green, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'Mov. #${ts.numeroMovimiento ?? '-'}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Traspaso registrado correctamente',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F8CFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: () => _irAlDashboard(ctx),
                child: const Text('Nuevo traspaso'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(traspasoProvider);

    final origenAlmacen  = ts.origen?['Codigo_Almacen']?.toString()  ?? '—';
    final origenStand    = ts.origen?['Stand']?.toString()           ?? '—';
    final destinoAlmacen = ts.destino?['Codigo_Almacen']?.toString() ?? '—';
    final destinoStand   = ts.destino?['Stand']?.toString()          ?? '—';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black54, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Vista previa del ticket',
          style: TextStyle(
              color: Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
      ),
      body: _loadingAssets
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Container(
                        width: 300,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [

                            // ── CABECERA ─────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/img/icon-planeta-removebg-preview.png',
                                    width: 36,
                                    height: 36,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.book, size: 36),
                                  ),
                                  const SizedBox(width: 10),
                                  const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('EDITORIAL PLANETA',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5)),
                                      Text('COLOMBIANA S.A.',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5)),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const _TicketDivider(),

                            // ── DISPOSITIVO + MOV ────────────────────────
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: [
                                  Text(
                                    'Dispositivo $_numDispositivo  |  Mov. #${ts.numeroMovimiento ?? '-'}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Fecha: $_fecha   Hora: $_hora',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),

                            const _TicketDivider(),

                            // ── TÍTULO TRASPASOS ─────────────────────────
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'TRASPASOS',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 3),
                                textAlign: TextAlign.center,
                              ),
                            ),

                            const _TicketDivider(),

                            // ── DESDE / HASTA ────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Desde: $origenAlmacen   Stand: $origenStand',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Hasta: $destinoAlmacen   Stand: $destinoStand',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),

                            const _TicketDivider(),

                            // ── ENCABEZADO TABLA ─────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 105,
                                    child: Text('Ref',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  const Expanded(
                                    child: Text('Descripción',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  const Text('Cant',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),

                            const _TicketDivider(),

                            // ── LÍNEAS ───────────────────────────────────
                            ...ts.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 105,
                                      child: Text(
                                        item['codigo']?.toString() ?? '',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        item['descripcion']?.toString() ?? '',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                    Text(
                                      '${item['cantidad']}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const _TicketDivider(),

                            // ── TOTALES ──────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Referencias: ${ts.items.length}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Total: ${ts.total}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── BOTÓN IMPRIMIR ──────────────────────────────────────────
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('IMPRIMIR TICKET',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A2035),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _imprimir,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Widget auxiliar: separador tipo ticket ────────────────────────────────────
class _TicketDivider extends StatelessWidget {
  const _TicketDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: List.generate(
            40,
            (i) => Expanded(
              child: Container(
                height: 1,
                color: i.isEven ? Colors.black26 : Colors.transparent,
              ),
            ),
          ),
        ),
      );
}