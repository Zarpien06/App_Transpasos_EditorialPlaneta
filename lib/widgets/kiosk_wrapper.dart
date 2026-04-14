// lib/widgets/kiosk_wrapper.dart

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Bloquea silenciosamente el gesto/botón atrás del sistema
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap:       () => kiosk.registerActivity(),
        onPanUpdate: (_) => kiosk.registerActivity(),
        child: Stack(
          children: [
            Column(
              children: [
                const KioskStatusBar(),
                Expanded(child: widget.child),
              ],
            ),
            const KioskAlertOverlay(),
          ],
        ),
      ),
    );
  }
}