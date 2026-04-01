// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/kiosk_service.dart';
import 'core/pdf_fonts.dart';
import 'core/connectivity_service.dart';
import 'core/device_service.dart';
import 'services/sync_service.dart';
import 'screens/login_screen.dart';
import 'screens/init_screen.dart';
import 'widgets/kiosk_wrapper.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Future.wait([
    PdfFonts.load(),
    ConnectivityService().init(),
  ]);

  final inicializado = await DeviceService().estaInicializado();

  runApp(ProviderScope(child: MyApp(inicializado: inicializado)));
}

final kioskProvider = ChangeNotifierProvider<KioskService>((ref) {
  return KioskService();
});

class MyApp extends ConsumerStatefulWidget {
  final bool inicializado;
  const MyApp({super.key, required this.inicializado});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final kiosk = ref.read(kioskProvider);

      // ✅ PRIMERO asignar onTimeout, LUEGO restaurar estado
      // Así si el kiosko estaba activo, el timer ya tiene su callback
      kiosk.onTimeout = () {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      };

      try {
        await kiosk.cargarEstadoPersistido(); // ← ahora onTimeout ya existe
        await SyncService.sincronizarCompleto();
      } catch (e) {
        debugPrint('Error inicialización: $e');
      } finally {
        FlutterNativeSplash.remove();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Traspasos Planeta',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: appTheme,
      builder: (context, child) => KioskWrapper(child: child!),
      home: widget.inicializado ? const LoginScreen() : const InitScreen(),
    );
  }
}