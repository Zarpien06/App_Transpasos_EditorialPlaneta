// lib/main.dart
//
// Cambios respecto a la versión anterior:
// 1. Se inicializa SyncLogService en el arranque (antes del sync inicial).
// 2. SincronizarCompleto() ya no necesita botón — ConnectivityService
//    lo llama al detectar internet y en el polling de 30 s.

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
import 'services/sync_log_service.dart';   // ← NUEVO
import 'screens/login_screen.dart';
import 'screens/init_screen.dart';
import 'widgets/kiosk_wrapper.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // ── Inicializar servicios en paralelo ────────────────────────────────────
  await Future.wait([
    PdfFonts.load(),
    SyncLogService().init(),          // ← NUEVO: crea tabla y carga historial
    ConnectivityService().init(),     // ya dispara sincronizarCompleto si hay red
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
  // ConnectivityService ya llamó sincronizarCompleto() al init() si había red.
  // Aquí hacemos un intento adicional post-frame por si el init fue muy rápido
  // y la interfaz aún no estaba lista.
  bool _syncInicialHecho = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final kiosk = ref.read(kioskProvider);

      kiosk.onTimeout = () {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      };

      try {
        await kiosk.cargarEstadoPersistido();

        // Solo ejecuta si ConnectivityService no lo hizo ya
        if (!_syncInicialHecho) {
          _syncInicialHecho = true;
          // Fire-and-forget: no bloquea el splash
          SyncService.sincronizarCompleto().ignore();
        }
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
      title                   : 'Traspasos Planeta',
      debugShowCheckedModeBanner: false,
      navigatorKey            : navigatorKey,
      theme                   : appTheme,
      builder                 : (context, child) => KioskWrapper(child: child!),
      home                    : widget.inicializado
          ? const LoginScreen()
          : const InitScreen(),
    );
  }
}