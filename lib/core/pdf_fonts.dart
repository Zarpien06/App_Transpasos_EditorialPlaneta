import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfFonts {
  static pw.Font? regular;
  static pw.Font? bold;

  static Future<void> load() async {
    if (regular != null && bold != null) return;

    final regularData =
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');

    regular = pw.Font.ttf(regularData);
    bold = pw.Font.ttf(boldData);
  }
}