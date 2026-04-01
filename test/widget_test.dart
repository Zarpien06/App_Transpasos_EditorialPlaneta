import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:traspasos_planeta/main.dart';

void main() {
  testWidgets('App carga correctamente', (WidgetTester tester) async {
    // 🔥 Pasar el parámetro requerido
    await tester.pumpWidget(const MyApp(inicializado: true));

    // Verifica que la app renderiza algo
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}