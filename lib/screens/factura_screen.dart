import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../providers/traspaso_provider.dart';
import 'dashboard_screen.dart';

const int kNumDispositivo = 1;

// Anchos de columna PDF (rollo 80mm, márgenes 4mm c/lado → útil ~72mm)
const double colRef  = 30 * PdfPageFormat.mm;
const double colCant = 10 * PdfPageFormat.mm;

class FacturaScreen extends StatelessWidget {
  const FacturaScreen({super.key});

  Future<void> _imprimir(
      BuildContext context, TraspasoProvider prov, String fecha, String hora) async {
    final pdf       = pw.Document();
    final logoImage = await imageFromAssetBundle(
        'assets/img/icon-planeta-removebg-preview.png');

    // Fuente con soporte Unicode completo (tildes, ñ, etc.)
    // Evita el warning "Helvetica has no Unicode support"
    final ttf = await PdfGoogleFonts.notoSansRegular();
    final ttfBold = await PdfGoogleFonts.notoSansBold();

    // ── Alto con factor x3 para garantizar que los totales siempre aparezcan ──
    // headerMm : cabecera fija
    // itemMm   : por ítem (22mm → cubre descripciones largas de 2-3 líneas)
    // footerMm : totales + espacio al final
    // Factor x3 : margen enorme, el papel sobrante no importa en rollo térmico
    const double headerMm = 130.0;
    const double itemMm   =  22.0;
    const double footerMm =  80.0;
    final double totalMm  = (headerMm + (prov.items.length * itemMm) + footerMm) * 3.0;
    final double pageHeight = totalMm * PdfPageFormat.mm;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          pageHeight,
          marginLeft:   4  * PdfPageFormat.mm,
          marginRight:  4  * PdfPageFormat.mm,
          marginTop:    12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            // ── Logo + empresa ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(logoImage, width: 32, height: 32),
                pw.SizedBox(width: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('EDITORIAL PLANETA',
                        style: pw.TextStyle(font: ttfBold, fontSize: 14)),
                    pw.Text('COLOMBIANA S.A.',
                        style: pw.TextStyle(font: ttfBold, fontSize: 14)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5),

            // ── Dispositivo + mov ──
            pw.Center(
              child: pw.Text(
                'Dispositivo $kNumDispositivo  |  Mov. #${prov.numeroMovimiento ?? '-'}',
                style: pw.TextStyle(font: ttfBold, fontSize: 13),
              ),
            ),
            pw.SizedBox(height: 4),

            // ── Fecha y hora ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Fecha: $fecha', style: pw.TextStyle(font: ttf, fontSize: 12)),
                pw.Text('Hora: $hora',   style: pw.TextStyle(font: ttf, fontSize: 12)),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.5),

            // ── Título ──
            pw.Center(
              child: pw.Text('TRASPASOS',
                  style: pw.TextStyle(font: ttfBold, fontSize: 16)),
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.5),

            // ── Desde / Hasta ──
            pw.Text(
              'Desde: ${prov.origen?['almacen'] ?? '-'}  Stand: ${prov.origen?['stand'] ?? '-'}',
              style: pw.TextStyle(font: ttfBold, fontSize: 12),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Hasta: ${prov.destino?['almacen'] ?? '-'}  Stand: ${prov.destino?['stand'] ?? '-'}',
              style: pw.TextStyle(font: ttfBold, fontSize: 12),
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 1),

            // ── Tabla header ──
            pw.Row(
              children: [
                pw.SizedBox(
                  width: colRef,
                  child: pw.Text('Referencia',
                      style: pw.TextStyle(font: ttfBold, fontSize: 11)),
                ),
                pw.Expanded(
                  child: pw.Text('Descripcion',
                      style: pw.TextStyle(font: ttfBold, fontSize: 11)),
                ),
                pw.SizedBox(
                  width: colCant,
                  child: pw.Text('Cant',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: ttfBold, fontSize: 11)),
                ),
              ],
            ),
            pw.Divider(thickness: 1),

            // ── Items ──
            ...prov.items.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: colRef,
                    child: pw.Text(
                      item['codigo'] ?? '',
                      style: pw.TextStyle(font: ttf, fontSize: 11),
                      softWrap: true,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      item['descripcion'] ?? '',
                      style: pw.TextStyle(font: ttf, fontSize: 10),
                      softWrap: true,
                    ),
                  ),
                  pw.SizedBox(
                    width: colCant,
                    child: pw.Text(
                      '${item['cantidad']}',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: ttf, fontSize: 11),
                    ),
                  ),
                ],
              ),
            )),

            // ── Totales ──
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Referencias: ${prov.items.length}',
                  style: pw.TextStyle(font: ttfBold, fontSize: 13),
                ),
                pw.Text(
                  'Total: ${prov.total}',
                  style: pw.TextStyle(font: ttfBold, fontSize: 13),
                ),
              ],
            ),
            pw.SizedBox(height: 40),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());

    if (context.mounted) {
      _mostrarAlertaExito(context, prov);
    }
  }

  void _mostrarAlertaExito(BuildContext context, TraspasoProvider prov) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF43A047).withValues(alpha: 0.15),
                border: Border.all(
                    color: const Color(0xFF43A047).withValues(alpha: 0.5),
                    width: 2),
              ),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFF43A047), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              '¡Impresión enviada!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Mov. #${prov.numeroMovimiento ?? '-'} registrado correctamente.',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('NUEVO TRASPASO',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  prov.limpiar();
                  Navigator.of(ctx).pop();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DashboardScreen()),
                    (_) => false,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                prov.limpiar();
                Navigator.of(ctx).pop();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DashboardScreen()),
                  (_) => false,
                );
              },
              child: const Text('Volver al inicio',
                  style: TextStyle(color: Color(0xFF555555), fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov  = context.read<TraspasoProvider>();
    final now   = DateTime.now();
    final fecha = DateFormat('yyyy/MM/dd').format(now);
    final hora  = DateFormat('HH:mm:ss').format(now);

    return Scaffold(
      appBar: AppBar(title: const Text('Factura de Traspaso')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset(
                              'assets/img/icon-planeta-removebg-preview.png',
                              width: 38, height: 38),
                          const SizedBox(width: 8),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('EDITORIAL PLANETA',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black)),
                              Text('COLOMBIANA S.A.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Colors.black26),

                      Center(
                        child: Text(
                          'Dispositivo $kNumDispositivo  |  Mov. #${prov.numeroMovimiento ?? '-'}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Fecha: $fecha',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black87)),
                          Text('Hora: $hora',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black87)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Divider(color: Colors.black26),

                      const Center(
                        child: Text('TRASPASOS',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black)),
                      ),
                      const SizedBox(height: 6),
                      const Divider(color: Colors.black26),

                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                          children: [
                            const TextSpan(
                                text: 'Desde: ',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(
                                text: '${prov.origen?['almacen'] ?? '-'}  Stand: ${prov.origen?['stand'] ?? '-'}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                          children: [
                            const TextSpan(
                                text: 'Hasta: ',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(
                                text: '${prov.destino?['almacen'] ?? '-'}  Stand: ${prov.destino?['stand'] ?? '-'}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Divider(color: Colors.black87, thickness: 1),

                      const Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text('Referencia',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    color: Colors.black)),
                          ),
                          Expanded(
                            child: Text('Descripción',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    color: Colors.black)),
                          ),
                          Text('Cant',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  color: Colors.black)),
                        ],
                      ),
                      const Divider(color: Colors.black87, thickness: 1),

                      ...prov.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                item['codigo'] ?? '',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black87),
                                softWrap: true,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item['descripcion'] ?? '',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black87),
                                softWrap: true,
                              ),
                            ),
                            Text('${item['cantidad']}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black87)),
                          ],
                        ),
                      )),

                      const SizedBox(height: 6),
                      const Divider(color: Colors.black87, thickness: 1),
                      const SizedBox(height: 4),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Referencias: ${prov.items.length}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.black)),
                          Text('Total: ${prov.total}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.black)),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('IMPRIMIR',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF42A5F5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _imprimir(context, prov, fecha, hora),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.home_rounded,
                        color: Color(0xFF42A5F5)),
                    label: const Text('INICIO',
                        style: TextStyle(
                            color: Color(0xFF42A5F5),
                            fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1565C0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      prov.limpiar();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DashboardScreen()),
                        (_) => false,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}