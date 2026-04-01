// lib/screens/factura_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../core/pdf_fonts.dart';
import '../core/device_service.dart';
import '../providers/traspaso_provider.dart';
import 'dashboard_screen.dart';
import '../main.dart'; 

const double _colRef  = 30 * PdfPageFormat.mm;
const double _colCant = 10 * PdfPageFormat.mm;

class FacturaScreen extends ConsumerStatefulWidget {
  const FacturaScreen({super.key});

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
    _fecha = DateFormat('yyyy/MM/dd').format(now);
    _hora  = DateFormat('HH:mm:ss').format(now);

    _precargar();
  }

  Future<void> _precargar() async {
    await PdfFonts.load();

    final deviceId = await DeviceService().getDeviceId();

    final ByteData bytes = await rootBundle
        .load('assets/img/icon-planeta-removebg-preview.png');

    if (mounted) {
      setState(() {
        _logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
        _numDispositivo = deviceId.replaceAll('DV', '');
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

  Future<void> _imprimir() async {
    if (_logoImage == null) return;

    ref.read(kioskProvider).registerActivity();

    final traspasoState = ref.read(traspasoProvider);

    final font     = PdfFonts.regular!;
    final fontBold = PdfFonts.bold!;
    final pdf      = pw.Document();

    const double headerMm = 110.0;
    const double itemMm   = 20.0;
    const double footerMm = 28.0;

    final totalMm =
        headerMm + (traspasoState.items.length * itemMm) + footerMm;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          totalMm * PdfPageFormat.mm,
          marginLeft: 4 * PdfPageFormat.mm,
          marginRight: 4 * PdfPageFormat.mm,
          marginTop: 12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            pw.Row(
              children: [
                pw.Image(_logoImage!, width: 32, height: 32),
                pw.SizedBox(width: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('EDITORIAL PLANETA',
                        style: pw.TextStyle(font: fontBold, fontSize: 14)),
                    pw.Text('COLOMBIANA S.A.',
                        style: pw.TextStyle(font: fontBold, fontSize: 14)),
                  ],
                ),
              ],
            ),

            pw.Divider(),

            pw.Center(
              child: pw.Text(
                'Dispositivo $_numDispositivo | Mov. #${traspasoState.numeroMovimiento ?? '-'}',
                style: pw.TextStyle(font: fontBold),
              ),
            ),

            pw.Center(
              child: pw.Text(
                'Fecha: $_fecha  Hora: $_hora',
                style: pw.TextStyle(font: font),
              ),
            ),

            pw.Divider(),

            ...traspasoState.items.map(
              (item) => pw.Row(
                children: [
                  pw.SizedBox(
                    width: _colRef,
                    child: pw.Text(item['codigo'] ?? ''),
                  ),
                  pw.Expanded(
                    child: pw.Text(item['descripcion'] ?? ''),
                  ),
                  pw.SizedBox(
                    width: _colCant,
                    child: pw.Text('${item['cantidad']}',
                        textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ),

            pw.Divider(),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Refs: ${traspasoState.items.length}',
                    style: pw.TextStyle(font: fontBold)),
                pw.Text('Total: ${traspasoState.total}',
                    style: pw.TextStyle(font: fontBold)),
              ],
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());

    if (mounted) _mostrarAlertaExito();
  }

  void _mostrarAlertaExito() {
    final traspasoState = ref.read(traspasoProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, color: Colors.green, size: 50),
            const SizedBox(height: 10),
            Text('Mov. #${traspasoState.numeroMovimiento ?? '-'} OK'),

            ElevatedButton(
              onPressed: () => _irAlDashboard(ctx),
              child: const Text('Nuevo'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final traspasoState = ref.watch(traspasoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Factura')),
      body: _loadingAssets
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                Expanded(
                  child: ListView(
                    children: [
                      ...traspasoState.items.map(
                        (e) => ListTile(
                          title: Text(e['descripcion']),
                          trailing: Text('${e['cantidad']}'),
                        ),
                      ),
                    ],
                  ),
                ),

                ElevatedButton(
                  onPressed: _imprimir,
                  child: const Text('IMPRIMIR'),
                ),
              ],
            ),
    );
  }
}