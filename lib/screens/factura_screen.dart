import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../providers/traspaso_provider.dart';
import 'dashboard_screen.dart';

const int kNumDispositivo = 1;

class FacturaScreen extends StatelessWidget {
  const FacturaScreen({super.key});

  Future<void> _imprimir(TraspasoProvider prov, String fecha, String hora) async {
    final pdf      = pw.Document();
    final logoImage = await imageFromAssetBundle('assets/img/icon-planeta-removebg-preview.png');

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          60 * PdfPageFormat.mm,
          double.infinity,
          marginLeft:   3 * PdfPageFormat.mm,
          marginRight:  3 * PdfPageFormat.mm,
          marginTop:    8 * PdfPageFormat.mm,
          marginBottom: 8 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            // ── Logo + empresa ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(logoImage, width: 30, height: 30),
                pw.SizedBox(width: 6),
                pw.Text(
                  'EDITORIAL PLANETA COLOMBIANA S.A.',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.5),

            // ── Dispositivo centrado + fecha ──
            pw.Center(
              child: pw.Text(
                'Dispositivo $kNumDispositivo  |  Mov. #${prov.numeroMovimiento ?? '-'}',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Fecha: $fecha', style: pw.TextStyle(fontSize: 8)),
                pw.Text('Hora: $hora',   style: pw.TextStyle(fontSize: 8)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),

            // ── Título ──
            pw.Center(
              child: pw.Text(
                'TRASPASOS',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.5),

            // ── Traslado ──
            pw.Text('Traslado de mercancía entre stands',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),

            pw.Text('Desde: ${prov.origen?['almacen'] ?? '-'}',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text('  Stand: ${prov.origen?['stand'] ?? '-'}',
                style: pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 3),
            pw.Text('Hasta: ${prov.destino?['almacen'] ?? '-'}',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text('  Stand: ${prov.destino?['stand'] ?? '-'}',
                style: pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.5),

            // ── Tabla header ──
            pw.Row(
              children: [
                pw.SizedBox(
                  width: 26 * PdfPageFormat.mm,
                  child: pw.Text('Ref',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Expanded(
                  child: pw.Text('Descripción',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Text('Cant',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Divider(thickness: 0.5),

            // ── Items ──
            ...prov.items.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 26 * PdfPageFormat.mm,
                    child: pw.Text(
                      item['codigo'] ?? '',
                      style: pw.TextStyle(fontSize: 8),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      item['descripcion'] ?? '',
                      style: pw.TextStyle(fontSize: 8),
                      maxLines: 3,
                    ),
                  ),
                  pw.Text(
                    '${item['cantidad']}',
                    style: pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            )),

            pw.Divider(thickness: 0.5),

            // ── Totales ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total referencias: ${prov.items.length}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text('Total libros: ${prov.total}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
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

            // ── Preview ──
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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

                      // Logo + empresa
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset('assets/img/icon-planeta-removebg-preview.png',
                              width: 36, height: 36),
                          const SizedBox(width: 8),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('EDITORIAL PLANETA',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                              Text('COLOMBIANA S.A.',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Colors.black26),

                      // Dispositivo centrado
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

                      // Fecha
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Fecha: $fecha',
                              style: const TextStyle(fontSize: 10, color: Colors.black87)),
                          Text('Hora: $hora',
                              style: const TextStyle(fontSize: 10, color: Colors.black87)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Divider(color: Colors.black26),

                      // Título
                      const Center(
                        child: Text('TRASPASOS',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black)),
                      ),
                      const SizedBox(height: 6),
                      const Divider(color: Colors.black26),

                      // Traslado
                      const Text('Traslado de mercancía entre stands',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              color: Colors.black)),
                      const SizedBox(height: 6),

                      // Desde / Hasta
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                          children: [
                            const TextSpan(text: 'Desde: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: '${prov.origen?['almacen'] ?? '-'}\n'),
                            TextSpan(text: '  ${prov.origen?['usuario'] ?? '-'} | Stand: ${prov.origen?['stand'] ?? '-'}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                          children: [
                            const TextSpan(text: 'Hasta: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: '${prov.destino?['almacen'] ?? '-'}\n'),
                            TextSpan(text: '  ${prov.destino?['usuario'] ?? '-'} | Stand: ${prov.destino?['stand'] ?? '-'}'),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.black26),

                      // Tabla header
                      const Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text('Ref',
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
                      const Divider(color: Colors.black26),

                      // Items
                      ...prov.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text(item['codigo'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.black87)),
                            ),
                            Expanded(
                              child: Text(item['descripcion'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.black87)),
                            ),
                            Text('${item['cantidad']}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black87)),
                          ],
                        ),
                      )),

                      const Divider(color: Colors.black26),

                      // Totales
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Referencias: ${prov.items.length}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.black)),
                          Text('Total libros: ${prov.total}',
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

            // ── Botones ──
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('IMPRIMIR',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF42A5F5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _imprimir(prov, fecha, hora),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.home_rounded, color: Color(0xFF42A5F5)),
                    label: const Text('INICIO',
                        style: TextStyle(
                            color: Color(0xFF42A5F5), fontWeight: FontWeight.bold)),
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
                        MaterialPageRoute(builder: (_) => const DashboardScreen()),
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