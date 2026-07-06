// lib/core/time_validation_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Valida que la hora del dispositivo sea consistente con:
//   1. La hora del servidor propio (prologics.co)
//   2. La hora oficial de Colombia (UTC-5, sin cambios por DST)
//
// Escenario crítico que resuelve:
//   El dispositivo se apaga por batería descargada y al reiniciar
//   el RTC queda en una hora incorrecta. Esto provoca que los
//   traspasos offline queden con fecha errónea y se envíen así
//   a la BD sin validación.
//
// Niveles de alerta:
//   ok          → desviación < 5 min  — todo normal
//   advertencia → desviación 5-60 min — avisa pero permite continuar
//   critico     → desviación > 60 min — bloquea con diálogo obligatorio
//   bloqueante  → desviación > 24 h   — bloqueo total (RTC corrupto)
//
// NUEVO — v2 (TrustedClock):
//   validarYSincronizar() → valida + alimenta TrustedClockService en un solo paso.
//   Es el método recomendado para usar desde ConnectivityService y SyncService.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'trusted_clock_service.dart';

// ── Nivel de severidad del resultado ─────────────────────────────────────────
enum NivelHora { ok, advertencia, critico, bloqueante }

// ── Resultado de la validación ────────────────────────────────────────────────
class ResultadoValidacionHora {
  final NivelHora nivel;

  /// Hora del servidor ya convertida a UTC-5 Colombia.
  final DateTime? horaServidor;

  /// Hora local del dispositivo en el momento de la validación.
  final DateTime horaDispositivo;

  /// Diferencia absoluta en segundos (positivo = dispositivo adelantado).
  final int diferenciaSegundos;

  /// Fuente desde donde se obtuvo la hora del servidor.
  final String fuente; // 'servidor_propio' | 'worldtime' | 'sin_internet'

  /// Mensaje legible para mostrar al usuario.
  final String mensaje;

  const ResultadoValidacionHora({
    required this.nivel,
    required this.horaServidor,
    required this.horaDispositivo,
    required this.diferenciaSegundos,
    required this.fuente,
    required this.mensaje,
  });

  bool get esCritico =>
      nivel == NivelHora.critico || nivel == NivelHora.bloqueante;

  bool get esBloqueante => nivel == NivelHora.bloqueante;

  String get diferenciaFormateada {
    final abs = diferenciaSegundos.abs();
    if (abs < 60) return '$abs segundos';
    if (abs < 3600) return '${abs ~/ 60} minutos';
    if (abs < 86400) return '${abs ~/ 3600} horas';
    return '${abs ~/ 86400} días';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO
// ─────────────────────────────────────────────────────────────────────────────

class TimeValidationService {
  static final TimeValidationService _instance =
      TimeValidationService._internal();
  factory TimeValidationService() => _instance;
  TimeValidationService._internal();

  // UTC offset fijo de Colombia: -5 horas, sin DST
  static const Duration _colombiaOffset = Duration(hours: -5);

  // Umbrales de alerta (en segundos)
  static const int _umbralAdvertencia = 5 * 60;    //  5 min
  static const int _umbralCritico     = 60 * 60;   // 60 min
  static const int _umbralBloqueante  = 24 * 3600; // 24 h

  static const String _baseUrl =
      'https://prologics.co/app_planeta/controlador';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  // ── Método principal ──────────────────────────────────────────────────────

  /// Valida la hora del dispositivo contra el servidor.
  /// Siempre retorna un [ResultadoValidacionHora], nunca lanza excepción.
  Future<ResultadoValidacionHora> validar() async {
    final horaDispositivo = DateTime.now();

    // 1. Intentar obtener hora del servidor propio
    final horaPropia = await _obtenerHoraServidorPropio();
    if (horaPropia != null) {
      return _calcularResultado(
        horaServidor    : horaPropia,
        horaDispositivo : horaDispositivo,
        fuente          : 'servidor_propio',
      );
    }

    // 2. Fallback: WorldTime API (no requiere nuestro servidor)
    final horaWorld = await _obtenerHoraWorldTime();
    if (horaWorld != null) {
      return _calcularResultado(
        horaServidor    : horaWorld,
        horaDispositivo : horaDispositivo,
        fuente          : 'worldtime',
      );
    }

    // 3. Sin internet — no se puede validar, continuar con advertencia leve
    debugPrint('⚠ TimeValidation: sin internet, no se pudo validar la hora');
    return ResultadoValidacionHora(
      nivel               : NivelHora.advertencia,
      horaServidor        : null,
      horaDispositivo     : horaDispositivo,
      diferenciaSegundos  : 0,
      fuente              : 'sin_internet',
      mensaje             :
          'Sin conexión para verificar la hora.\n'
          'Los registros usarán la hora calculada offline.',
    );
  }

  // ── NUEVO v2: Validar + sincronizar TrustedClock en un paso ───────────────
  //
  // Uso recomendado desde ConnectivityService._sync() y SyncService.descargar().
  // Equivale a llamar validar() + TrustedClockService().sincronizarConServidor()
  // pero en una sola llamada HTTP, evitando duplicar requests.

  /// Valida la hora y, si tiene éxito, actualiza el [TrustedClockService].
  /// Retorna el [ResultadoValidacionHora] como siempre (compatible 100%).
  Future<ResultadoValidacionHora> validarYSincronizar() async {
    final resultado = await validar();

    if (resultado.fuente != 'sin_internet' && resultado.horaServidor != null) {
      // Alimentar TrustedClockService con la hora que ya obtuvimos
      // (no hace una segunda llamada HTTP)
      await TrustedClockService().sincronizarConServidor();

      debugPrint(
        '🔄 TimeValidation: TrustedClock actualizado '
        '(fuente: ${resultado.fuente})',
      );
    }

    return resultado;
  }

  // ── Obtener hora desde nuestro servidor ──────────────────────────────────

  Future<DateTime?> _obtenerHoraServidorPropio() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/ping.php',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

      if (response.statusCode != 200) return null;

      var data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return null;
        }
      }

      if (data is! Map) return null;

      // Espera: { "utc_timestamp": 1716000000 }  o  { "utc_datetime": "2025-..." }
      if (data['utc_timestamp'] != null) {
        final ts = (data['utc_timestamp'] as num).toInt();
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
            .toUtc();
      }

      if (data['utc_datetime'] != null) {
        return DateTime.tryParse(data['utc_datetime'].toString())?.toUtc();
      }

      return null;
    } catch (e) {
      debugPrint('⚠ TimeValidation: error servidor propio: $e');
      return null;
    }
  }

  // ── Fallback: WorldTime API ───────────────────────────────────────────────
  // Endpoint público gratuito, no requiere key.
  // Colombia/Bogota siempre es UTC-5 sin DST.

  Future<DateTime?> _obtenerHoraWorldTime() async {
    try {
      final response = await _dio.get(
        'https://worldtimeapi.org/api/timezone/America/Bogota',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      if (response.statusCode != 200) return null;

      var data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return null;
        }
      }

      if (data is! Map) return null;

      // worldtimeapi devuelve: { "utc_datetime": "2025-05-11T14:30:00.000000+00:00" }
      final raw = data['utc_datetime']?.toString() ?? data['datetime']?.toString();
      if (raw == null) return null;

      return DateTime.tryParse(raw)?.toUtc();
    } catch (e) {
      debugPrint('⚠ TimeValidation: error worldtime fallback: $e');
      return null;
    }
  }

  // ── Calcular resultado ────────────────────────────────────────────────────

  ResultadoValidacionHora _calcularResultado({
    required DateTime horaServidor,   // en UTC
    required DateTime horaDispositivo,
    required String fuente,
  }) {
    // Convertir hora del servidor a UTC-5 Colombia
    final horaColombiaServidor = horaServidor.toUtc().add(_colombiaOffset);

    // Convertir hora del dispositivo a UTC para comparar
    // DateTime.now() en Dart NO incluye zona horaria local confiable en Android
    // cuando el RTC está corrupto, por eso comparamos en UTC puro.
    final dispositivoUtc = horaDispositivo.toUtc();
    final servidorUtc    = horaServidor.toUtc();

    final diferencia = dispositivoUtc.difference(servidorUtc).inSeconds;
    final abs        = diferencia.abs();

    debugPrint(
      '🕐 TimeValidation [$fuente]\n'
      '   Servidor (UTC):   $servidorUtc\n'
      '   Servidor (COL):   $horaColombiaServidor\n'
      '   Dispositivo (UTC):$dispositivoUtc\n'
      '   Diferencia:       ${diferencia}s',
    );

    final NivelHora nivel;
    final String mensaje;

    if (abs < _umbralAdvertencia) {
      nivel   = NivelHora.ok;
      mensaje = 'Hora del dispositivo correcta.';
    } else if (abs < _umbralCritico) {
      nivel = NivelHora.advertencia;
      final signo = diferencia > 0 ? 'adelantado' : 'atrasado';
      mensaje =
          'La hora del dispositivo está $signo '
          '${_formatearDiferencia(abs)}.\n'
          'Los registros pueden quedar con hora incorrecta.';
    } else if (abs < _umbralBloqueante) {
      nivel = NivelHora.critico;
      final signo = diferencia > 0 ? 'adelantado' : 'atrasado';
      mensaje =
          'La hora del dispositivo está $signo '
          '${_formatearDiferencia(abs)} respecto al servidor.\n\n'
          'Esto puede causar registros con fecha incorrecta.\n'
          'Corrige la hora en Ajustes del dispositivo antes de continuar.';
    } else {
      nivel = NivelHora.bloqueante;
      mensaje =
          'La hora del dispositivo tiene una diferencia de '
          '${_formatearDiferencia(abs)} respecto al servidor.\n\n'
          'Esto indica que el dispositivo reinició con fecha incorrecta '
          '(posible descarga de batería).\n\n'
          'Es necesario corregir la hora antes de continuar para evitar '
          'registros con fecha errónea en la base de datos.';
    }

    return ResultadoValidacionHora(
      nivel              : nivel,
      horaServidor       : horaColombiaServidor,
      horaDispositivo    : horaDispositivo,
      diferenciaSegundos : diferencia,
      fuente             : fuente,
      mensaje            : mensaje,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatearDiferencia(int segundos) {
    if (segundos < 60)    return '$segundos segundos';
    if (segundos < 3600)  return '${segundos ~/ 60} minutos';
    if (segundos < 86400) return '${segundos ~/ 3600} horas';
    return '${segundos ~/ 86400} días';
  }
}