// lib/widgets/alerts.dart

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';

bool _dialogVisible = false;

void _mostrarDialog(AwesomeDialog dialog) {
  if (_dialogVisible) return;
  _dialogVisible = true;
  dialog.show();
  // Fallback: si onDismissCallback no se dispara por algún bug de la librería
  Future.delayed(const Duration(seconds: 6), () => _dialogVisible = false);
}

void _reset() => _dialogVisible = false;

// ─────────────────────────────────────────────────────────────────────────────

void alertaError(BuildContext ctx, String msg) {
  _mostrarDialog(
    AwesomeDialog(
      context: ctx,
      dialogType: DialogType.error,
      title: 'Error',
      desc: msg,
      onDismissCallback: (_) => _reset(),
      btnOkOnPress: () {},
    ),
  );
}

void alertaExito(BuildContext ctx, String msg, {VoidCallback? onOk}) {
  _mostrarDialog(
    AwesomeDialog(
      context: ctx,
      dialogType: DialogType.success,
      title: 'Éxito',
      desc: msg,
      onDismissCallback: (_) => _reset(),
      btnOkOnPress: onOk ?? () {},
    ),
  );
}

void alertaConfirmar(BuildContext ctx, String msg, VoidCallback onSi) {
  _mostrarDialog(
    AwesomeDialog(
      context: ctx,
      dialogType: DialogType.warning,
      title: 'Confirmar',
      desc: msg,
      onDismissCallback: (_) => _reset(),
      btnCancelOnPress: () {},
      btnOkOnPress: onSi,
      btnOkText: 'Sí',
      btnCancelText: 'No',
    ),
  );
}

void alertaErrorImpresion(
  BuildContext ctx, {
  required VoidCallback onReintentar,
}) {
  _mostrarDialog(
    AwesomeDialog(
      context: ctx,
      dialogType: DialogType.warning,
      title: 'Error al imprimir',
      desc: 'No se pudo completar la impresión.\n\n'
          '• Verifique que la impresora esté encendida\n'
          '• Verifique que haya papel\n'
          '• Verifique la conexión Bluetooth/USB',
      onDismissCallback: (_) => _reset(),
      btnCancelText: 'Cancelar',
      btnCancelOnPress: () {},
      btnOkText: 'Reimprimir',
      btnOkOnPress: onReintentar,
    ),
  );
}