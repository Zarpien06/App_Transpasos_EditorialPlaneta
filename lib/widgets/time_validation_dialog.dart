// lib/widgets/time_validation_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────
// Diálogo que se muestra cuando la hora del dispositivo no es confiable.
//
// Niveles:
//   advertencia → botón "Entendido" — deja continuar
//   critico     → botones "Corregir hora" + "Continuar de todas formas"
//   bloqueante  → solo "Corregir hora" — no permite continuar sin corregir
//
// Uso:
//   final resultado = await TimeValidationService().validar();
//   if (resultado.esCritico) {
//     await TimeValidationDialog.mostrar(context, resultado);
//   }
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/time_validation_service.dart';

class TimeValidationDialog {
  TimeValidationDialog._();

  /// Muestra el diálogo apropiado según el nivel.
  /// Retorna `true` si el usuario decidió continuar, `false` si bloqueó.
  static Future<bool> mostrar(
    BuildContext context,
    ResultadoValidacionHora resultado,
  ) async {
    if (resultado.nivel == NivelHora.ok) return true;

    final permitirContinuar = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // nunca se cierra con tap fuera
      builder: (ctx) => _TimeAlertDialog(resultado: resultado),
    );

    return permitirContinuar ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIÁLOGO INTERNO
// ─────────────────────────────────────────────────────────────────────────────

class _TimeAlertDialog extends StatelessWidget {
  final ResultadoValidacionHora resultado;

  const _TimeAlertDialog({required this.resultado});

  // Paleta según nivel
  Color get _colorIcono {
    switch (resultado.nivel) {
      case NivelHora.advertencia: return const Color(0xFFF9A825);
      case NivelHora.critico:     return const Color(0xFFE65100);
      case NivelHora.bloqueante:  return const Color(0xFFB71C1C);
      case NivelHora.ok:          return Colors.green;
    }
  }

  IconData get _icono {
    switch (resultado.nivel) {
      case NivelHora.advertencia: return Icons.access_time_rounded;
      case NivelHora.critico:     return Icons.timer_off_rounded;
      case NivelHora.bloqueante:  return Icons.warning_amber_rounded;
      case NivelHora.ok:          return Icons.check_circle_rounded;
    }
  }

  String get _titulo {
    switch (resultado.nivel) {
      case NivelHora.advertencia: return 'Hora con desviación leve';
      case NivelHora.critico:     return 'Hora del dispositivo incorrecta';
      case NivelHora.bloqueante:  return '⚠ Hora del dispositivo inválida';
      case NivelHora.ok:          return 'Hora correcta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final horaServidor   = resultado.horaServidor != null
        ? fmt.format(resultado.horaServidor!)
        : '—';
    final horaDispositivo = fmt.format(resultado.horaDispositivo);
  
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Ícono ──────────────────────────────────────────────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _colorIcono.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_icono, color: _colorIcono, size: 36),
            ),
            const SizedBox(height: 16),

            // ── Título ─────────────────────────────────────────────────
            Text(
              _titulo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // ── Comparativa de horas ───────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Column(
                children: [
                  _filaHora(
                    'Hora del servidor',
                    horaServidor,
                    Icons.cloud_done_rounded,
                    const Color(0xFF29B6F6),
                  ),
                  const Divider(color: Color(0xFF2A2A2A), height: 16),
                  _filaHora(
                    'Hora del dispositivo',
                    horaDispositivo,
                    Icons.phone_android_rounded,
                    _colorIcono,
                  ),
                  const Divider(color: Color(0xFF2A2A2A), height: 16),
                  _filaHora(
                    'Diferencia',
                    resultado.diferenciaFormateada,
                    Icons.swap_vert_rounded,
                    const Color(0xFFFFCC02),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Mensaje explicativo ────────────────────────────────────
            Text(
              resultado.mensaje,
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // ── Botones ────────────────────────────────────────────────
            if (resultado.nivel == NivelHora.advertencia) ...[
              // Solo info — el usuario puede continuar
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Entendido, continuar',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ] else if (resultado.nivel == NivelHora.critico) ...[
              // Advertencia fuerte — puede continuar pero con confirmación
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('Corregir hora ahora',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF888888),
                    side: const BorderSide(color: Color(0xFF444444)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Continuar de todas formas',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ] else ...[
              // BLOQUEANTE — solo puede corregir, no hay opción de saltar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B1111).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFB71C1C).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        color: Color(0xFFEF9A9A), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se puede continuar hasta corregir la hora',
                        style: TextStyle(
                            color: Color(0xFFEF9A9A), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings_rounded, size: 20),
                  label: const Text('Corregir hora del dispositivo',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB71C1C),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  // En modo bloqueante: no hacemos pop(true), devolvemos false
                  // para que la pantalla que lo llamó sepa que NO puede avanzar.
                  // La app se queda esperando que el usuario corrija y relance.
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              // Botón de reintento: vuelve a validar sin salir de la pantalla
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text(
                  'Ya corregí la hora — Reintentar',
                  style: TextStyle(
                      color: Color(0xFF29B6F6),
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF29B6F6)),
                ),
              ),
            ],

            // ── Nota de fuente ─────────────────────────────────────────
            if (resultado.fuente != 'sin_internet') ...[
              const SizedBox(height: 8),
              Text(
                'Fuente: ${resultado.fuente == 'servidor_propio' ? 'servidor de Planeta' : 'WorldTime API (Colombia/Bogota)'}',
                style: const TextStyle(
                    color: Color(0xFF555555), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaHora(String label, String valor, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF888888), fontSize: 11)),
        ),
        Text(
          valor,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace'),
        ),
      ],
    );
  }
}