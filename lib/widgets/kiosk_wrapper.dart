// lib/widgets/kiosk_wrapper.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Si minimiza y vuelve → re-aplicar immersive
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final kiosk = ref.read(kioskProvider);
    if (kiosk.isKioskActive && state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskProvider);

    if (!kiosk.isKioskActive) return widget.child;

    // ✅ Solo bloquea el botón atrás del sistema (físico/gesto)
    // No bloquea la navegación interna de Flutter (Navigator.pop)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Bloquea silenciosamente el gesto/botón atrás del sistema
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap:       () => kiosk.registerActivity(),
        onPanUpdate: (_) => kiosk.registerActivity(),
        child: widget.child,
      ),
    );
  }
}