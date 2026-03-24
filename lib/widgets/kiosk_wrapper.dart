import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/kiosk_service.dart';
import '../main.dart';

class KioskWrapper extends StatefulWidget {
  final Widget child;
  const KioskWrapper({super.key, required this.child});

  @override
  State<KioskWrapper> createState() => _KioskWrapperState();
}

class _KioskWrapperState extends State<KioskWrapper> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KioskService>().onSecretTapsDetected = _showPinDialog;
    });
  }

  void _showPinDialog() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const _PinDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = context.watch<KioskService>();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => kiosk.registerActivity(),
      child: PopScope(
        canPop: false,
        child: Stack(
          textDirection: TextDirection.ltr,
          children: [
            widget.child,
            if (kiosk.isKioskActive)
              Positioned(
                top: 50,
                left: MediaQuery.of(context).size.width / 2 - 40,
                width: 80,
                height: 80,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => kiosk.registerSecretTap(),
                  child: Container(color: Colors.transparent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  bool _error = false;
  int _attempts = 0;
  static const int _maxAttempts = 3;

  void _submit() async {
    final kiosk = context.read<KioskService>();
    final bool success = await kiosk.deactivate(_controller.text.trim());
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      _attempts++;
      setState(() { _error = true; _controller.clear(); });
      if (_attempts >= _maxAttempts) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Acceso administrador'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'PIN',
              errorText: _error
                  ? 'PIN incorrecto. Intentos restantes: ${_maxAttempts - _attempts}'
                  : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}