// lib/widgets/kiosk_wrapper.dart
// ─────────────────────────────────────────────────────────────────────────────
// Widget raíz que envuelve la app en modo kiosco híbrido.
//
// ✅ FIX ARRANQUE: KioskStatusBar ahora se muestra SIEMPRE, sin importar si
//    isKioskActive es true o false. Esto resuelve el problema de reinicio/
//    apagado donde la barra no aparecía hasta activar/desactivar el kiosco
//    manualmente, porque SharedPreferences tarda en cargar y durante ese
//    tiempo isKioskActive = false ocultaba la barra.
//
// COMPORTAMIENTO:
//   • KioskStatusBar → SIEMPRE visible (batería, señal, dispositivo)
//   • Barra de navegación INFERIOR → OCULTA mientras kiosco activo
//   • Botón atrás → bloqueado con PopScope mientras kiosco activo
//   • Watchdog de ciclo de vida → reaplica UI flags al recuperar foco
//   • Overlay de alertas horarias incluido
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import 'kiosk_status_bar.dart';
import 'kiosk_alert_overlay.dart';

class KioskWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const KioskWrapper({super.key, required this.child});

  @override
  ConsumerState<KioskWrapper> createState() => _KioskWrapperState();
}

class _KioskWrapperState extends ConsumerState<KioskWrapper>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Aplicar modo UI al construir, cubre arranque desde boot donde
    // didChangeAppLifecycleState no se dispara al no haber perdido foco.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aplicarModoUI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al recuperar foco reaplica el modo UI con 3 delays para cubrir
  /// fabricantes (MIUI, OneUI, H10 POS) que revierten la UI tarde (~600ms).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _aplicarModoUI();
      Future.delayed(const Duration(milliseconds: 300), _aplicarModoUI);
      Future.delayed(const Duration(milliseconds: 800), _aplicarModoUI);
    }
  }

  /// Muestra barra superior, oculta barra inferior.
  /// SystemUiMode.manual evita el mensaje "app desfijada" de immersiveSticky.
  void _aplicarModoUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskProvider);

    final content = Column(
      children: [
        // ── Barra de estado: SIEMPRE visible ────────────────────────────
        const KioskStatusBar(),

        // ── Contenido principal de la app ────────────────────────────────
        Expanded(child: widget.child),
      ],
    );

    // Si el kiosco no está activo, mostrar sin bloqueos
    if (!kiosk.isKioskActive) {
      return GestureDetector(
        behavior:    HitTestBehavior.translucent,
        onTap:       () => kiosk.registerActivity(),
        onPanUpdate: (_) => kiosk.registerActivity(),
        child: Stack(
          children: [
            content,
            const KioskAlertOverlay(),
          ],
        ),
      );
    }

    // Kiosco activo: agregar PopScope
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
      child: GestureDetector(
        behavior:    HitTestBehavior.translucent,
        onTap:       () => kiosk.registerActivity(),
        onPanUpdate: (_) => kiosk.registerActivity(),
        child: Stack(
          children: [
            content,
            // ── Overlay de alertas horarias ──────────────────────────────
            const KioskAlertOverlay(),
          ],
        ),
      ),
    );
  }
}