import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';

void alertaError(BuildContext ctx, String msg) {
  AwesomeDialog(context: ctx, dialogType: DialogType.error,
      title: "Error", desc: msg, btnOkOnPress: () {}).show();
}

void alertaExito(BuildContext ctx, String msg, {VoidCallback? onOk}) {
  AwesomeDialog(context: ctx, dialogType: DialogType.success,
      title: "Éxito", desc: msg, btnOkOnPress: onOk ?? () {}).show();
}

void alertaConfirmar(BuildContext ctx, String msg, VoidCallback onSi) {
  AwesomeDialog(
    context: ctx,
    dialogType: DialogType.warning,
    title: "Confirmar",
    desc: msg,
    btnCancelOnPress: () {},
    btnOkOnPress: onSi,
    btnOkText: "Sí",
    btnCancelText: "No",
  ).show();
}