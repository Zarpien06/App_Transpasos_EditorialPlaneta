// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'core/kiosk_service.dart';
import 'core/pdf_fonts.dart';
import 'core/connectivity_service.dart';
import 'core/battery_service.dart';
import 'core/device_service.dart';
import 'core/scheduled_alert_service.dart';
import 'core/time_validation_service.dart';
import 'widgets/time_validation_dialog.dart';
import 'services/sync_service.dart';
import 'services/sync_log_service.dart';
import 'services/data_usage_service.dart';
import 'screens/login_screen.dart';
import 'screens/init_screen.dart';
import 'widgets/kiosk_wrapper.dart';

final navigatorKey = GlobalKey<NavigatorState>();

final horaValidacionProvider =
    StateProvider<ResultadoValidacionHora?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Detecta si el sistema acaba de encender (arranque frío)
//
// FIX: /proc/uptime está bloqueado por SELinux en ciertos dispositivos (ej. H10)
// → La nueva estrategia usa SharedPreferences para comparar el timestamp del
//   último arranque de la app. Si la app no había corrido en más de 2 minutos
//   se considera arranque frío (dispositivo recién encendido/reiniciado).
//
// Limitación conocida: si el usuario fuerza-cierra la app y la reabre dentro
// de 2 min, se detectará erróneamente como arranque frío y habrá un delay de 4s.
// Ese caso es raro y el delay no causa ningún daño funcional.
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> _sistemaRecienEncendido() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    final ultimoArranque = prefs.getInt('ultimo_arranque_app') ?? 0;

    await prefs.setInt('ultimo_arranque_app', ahora);

    final diferenciaSeg = (ahora - ultimoArranque) ~/ 1000;
    debugPrint('⏱ Tiempo desde último arranque de app: ${diferenciaSeg}s');

    if (ultimoArranque == 0) {
      debugPrint('ℹ Primera ejecución — sin delay');
      return false;
    }

    return diferenciaSeg > 120;
  } catch (e) {
    debugPrint('⚠ No se pudo verificar arranque: $e');
    return false;
  }
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // ─────────────────────────────────────────────────────────────────────────
  // OPT: Delay reducido de 8s → 4s.
  // El H10 levanta WiFi y servicios Android en ~3s reales; 4s da margen
  // suficiente sin castigar al operario con espera innecesaria.
  // ─────────────────────────────────────────────────────────────────────────
  final esArranqueFrio = await _sistemaRecienEncendido();
  if (esArranqueFrio) {
    debugPrint('🔄 Arranque frío detectado — esperando 4s a que Android levante servicios...');
    await Future.delayed(const Duration(seconds: 4)); // era 8s
  } else {
    debugPrint('✅ Arranque normal — sin delay');
  }

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // OPT: Solo servicios CRÍTICOS en el Future.wait bloqueante.
  //
  // Antes: PdfFonts + SyncLog + Connectivity + Battery + DataUsage (todo bloqueante)
  // Ahora: solo ConnectivityService y SyncLogService — los únicos que se
  //        necesitan ANTES de mostrar el primer frame.
  //
  // PdfFonts    → solo necesario al generar un PDF, se difiere a background
  // BatteryService  → polling cada 60s, no urgente en el arranque
  // DataUsageService → estadísticas, no urgente en el arranque
  // ─────────────────────────────────────────────────────────────────────────
  try {
    await Future.wait([
      SyncLogService().init(),
      ConnectivityService().init(),
    ]);
  } catch (e) {
    debugPrint('⚠ Error en init de servicios críticos: $e — continuando de todas formas');
  }

  final inicializado = await DeviceService().estaInicializado();
  runApp(ProviderScope(child: MyApp(inicializado: inicializado)));
}

final kioskProvider =
    ChangeNotifierProvider<KioskService>((ref) => KioskService());

class MyApp extends ConsumerStatefulWidget {
  final bool inicializado;
  const MyApp({super.key, required this.inicializado});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _syncInicialHecho = false;

  @override
  void initState() {
    super.initState();

    ScheduledAlertService()
      ..setNavigatorKey(navigatorKey)
      ..start();

    WidgetsBinding.instance.addPostFrameCallback((_) async {

      // ───────────────────────────────────────────────────────────────────
      // OPT: Servicios diferidos — arrancan en background DESPUÉS del
      // primer frame, sin bloquear la UI ni el splash.
      //
      // unawaited() es intencional: estos servicios no necesitan estar
      // listos para mostrar la pantalla de login.
      // ───────────────────────────────────────────────────────────────────
      unawaited(PdfFonts.load().catchError(
        (e) => debugPrint('⚠ PdfFonts.load() falló: $e'),
      ));
      unawaited(BatteryService().init().catchError(
        (e) => debugPrint('⚠ BatteryService.init() falló: $e'),
      ));
      unawaited(DataUsageService().init().catchError(
        (e) => debugPrint('⚠ DataUsageService.init() falló: $e'),
      ));

      final kiosk = ref.read(kioskProvider);

      kiosk.onTimeout = () {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      };

      try {
        await kiosk.cargarEstadoPersistido();

        if (!_syncInicialHecho) {
          _syncInicialHecho = true;
          // FIX: Se eliminó SyncService.sincronizarCompleto().ignore() que
          // causaba una descarga doble al arranque. iniciarAutoSync() ya hace
          // la descarga completa + sube pendientes internamente al arrancar,
          // por lo que sincronizarCompleto() era redundante y generaba dos
          // llamadas simultáneas a descarga_datos_nube_movil2.php.
          SyncService.iniciarAutoSync();
        }

        if (widget.inicializado && mounted) {
          await _validarHora();
        }

      } catch (e) {
        debugPrint('Error inicialización: $e');
      } finally {
        FlutterNativeSplash.remove();
      }
    });
  }

  Future<void> _validarHora() async {
    while (true) {
      final resultado = await TimeValidationService().validar();

      if (mounted) {
        ref.read(horaValidacionProvider.notifier).state = resultado;
      }

      if (!mounted) return;

      if (resultado.fuente == 'sin_internet') {
        debugPrint('⚠ Hora no validada (sin internet) — continuando offline');
        return;
      }

      if (resultado.nivel == NivelHora.ok) {
        debugPrint('✅ Hora validada correctamente (${resultado.fuente})');
        return;
      }

      final decision = await TimeValidationDialog.mostrar(
        navigatorKey.currentContext!,
        resultado,
      );

      if (decision == true) {
        debugPrint('⚠ Usuario aceptó continuar con hora desviada');
        return;
      }

      if (decision == false && resultado.esBloqueante) {
        await _mostrarPantallaEsperaHora();
        continue;
      }

      if (decision == false && !resultado.esBloqueante) {
        await _mostrarPantallaEsperaHora();
        continue;
      }

      return;
    }
  }

  Future<void> _mostrarPantallaEsperaHora() async {
    await showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (ctx) => const _EsperandoCorreccionHoraDialog(),
    );
  }

  @override
  void dispose() {
    ScheduledAlertService().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                     'Traspasos Planeta',
      debugShowCheckedModeBanner: false,
      navigatorKey:              navigatorKey,
      theme:                     appTheme,
      builder: (context, child) => KioskWrapper(child: child!),
      home: widget.inicializado
          ? const LoginScreen()
          : const InitScreen(),
    );
  }
}

class _EsperandoCorreccionHoraDialog extends StatelessWidget {
  const _EsperandoCorreccionHoraDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings_rounded,
                  color: Color(0xFF29B6F6), size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'Corrige la hora del dispositivo',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Ve a Ajustes → Gestión general → Fecha y hora\n'
              'y activa "Fecha y hora automáticas".\n\n'
              'Luego regresa aquí y presiona "Ya corregí la hora".',
              style: TextStyle(
                  color: Color(0xFFBBBBBB), fontSize: 13, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Ya corregí la hora — Verificar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}