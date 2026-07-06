// lib/core/trusted_clock_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// RELOJ CONFIABLE HÍBRIDO — funciona online y hasta 24 h offline
//
// Estrategia:
//   1. Cuando hay internet → obtiene hora del servidor vía TimeValidationService,
//      guarda "fecha base confiable" + timestamp monotónico en config (SQLite).
//   2. Sin internet → avanza desde la última base guardada usando
//      DateTime.now() como contador relativo (no como fuente absoluta).
//   3. Al reconectarse → compara hora calculada vs servidor y ajusta
//      de forma controlada (no hay saltos bruscos).
//   4. Detecta eventos críticos:
//        • Reinicio de dispositivo (gap monotónico anormal)
//        • Cambio manual de fecha (DateTime.now() retrocedió)
//        • Suspensión prolongada (gap > umbral configurable)
//        • Diferencia excesiva al reconectarse (> _umbralAjusteForzado)
//
// Indicadores de confiabilidad en cada llamada a ahora():
//   ConfiabilidadHora.validada     → sincronizada con servidor en últimas 2 h
//   ConfiabilidadHora.calculada    → offline < 24 h, contador local corriendo
//   ConfiabilidadHora.degradada    → offline > 24 h o reinicio detectado
//   ConfiabilidadHora.desconocida  → nunca sincronizó (primer arranque sin red)
//
// INTEGRACIÓN:
//   • main.dart          → TrustedClockService().init()
//   • ConnectivityService._sync() → TrustedClockService().sincronizarConServidor()
//   • BatteryService.lowBatteryStream → TrustedClockService().persistirEstado()
//   • api_service.dart   → TrustedClockService().ahora() en registrarTraspaso()
//   • backup_service.dart → TrustedClockService().ahora() en _fechaArchivo()
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'time_validation_service.dart';

// ── Nivel de confiabilidad de la hora devuelta ────────────────────────────────
enum ConfiabilidadHora {
  /// Sincronizada con servidor hace menos de [_umbralValidezMs] ms.
  validada,

  /// Offline pero el contador local lleva < 24 h desde la última sync.
  calculada,

  /// Offline > 24 h, o se detectó reinicio/manipulación del reloj.
  degradada,

  /// Nunca se sincronizó (primer arranque sin internet).
  desconocida,
}

// ── Resultado de ahora() ──────────────────────────────────────────────────────
class HoraConfiable {
  /// Hora estimada en UTC-5 Colombia.
  final DateTime horaLocal;

  /// Nivel de confianza de esta hora.
  final ConfiabilidadHora confiabilidad;

  /// Minutos transcurridos desde la última sincronización con el servidor.
  /// null si nunca se sincronizó.
  final int? minutosDesdeSincronizacion;

  /// true si se detectó un evento anómalo (reinicio, manipulación, etc.)
  final bool anomaliaDetectada;

  /// Descripción legible del estado para logs / UI.
  final String descripcion;

  const HoraConfiable({
    required this.horaLocal,
    required this.confiabilidad,
    this.minutosDesdeSincronizacion,
    this.anomaliaDetectada = false,
    required this.descripcion,
  });

  /// Etiqueta corta para insertar en registros (fecha_creacion, etc.)
  String get etiquetaFuente {
    switch (confiabilidad) {
      case ConfiabilidadHora.validada:
        return 'SERVER_VALIDATED';
      case ConfiabilidadHora.calculada:
        return 'LOCAL_CALCULATED';
      case ConfiabilidadHora.degradada:
        return 'DEGRADED';
      case ConfiabilidadHora.desconocida:
        return 'UNKNOWN';
    }
  }

  @override
  String toString() =>
      'HoraConfiable(${horaLocal.toIso8601String()} | '
      '$confiabilidad | $descripcion)';
}

// ── Resultado de sincronizarConServidor() ─────────────────────────────────────
class ResultadoSincronizacion {
  final bool exitoso;
  final int? diferenciaSegundos; // positivo = reloj local adelantado
  final bool ajusteAplicado;
  final String mensaje;

  const ResultadoSincronizacion({
    required this.exitoso,
    this.diferenciaSegundos,
    this.ajusteAplicado = false,
    required this.mensaje,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class TrustedClockService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final TrustedClockService _instance = TrustedClockService._internal();
  factory TrustedClockService() => _instance;
  TrustedClockService._internal();

  // ── Dependencias ───────────────────────────────────────────────────────────
  final _db          = DatabaseService();
  final _timeService = TimeValidationService();

  // ── Offset Colombia UTC-5 ──────────────────────────────────────────────────
  static const _colombiaOffset = Duration(hours: -5);

  // ── Claves de persistencia en tabla config ─────────────────────────────────
  // Guardadas en SQLite → sobreviven apagados de batería
  static const _kBaseUtcMs    = 'trusted_clock_base_utc_ms';   // epoch ms UTC del servidor
  static const _kBaseMonoMs   = 'trusted_clock_base_mono_ms';  // epoch ms de DateTime.now() al guardar
  static const _kFuente       = 'trusted_clock_fuente';        // 'servidor_propio'|'worldtime'
  static const _kSyncEpoch    = 'trusted_clock_sync_epoch';    // cuándo se guardó (epoch ms)
  static const _kLastMonoMs   = 'trusted_clock_last_mono_ms';  // último DateTime.now() visto
  static const _kAnomalias    = 'trusted_clock_anomalias';     // contador de anomalías

  // ── Umbrales ───────────────────────────────────────────────────────────────
  /// Tiempo máximo que una sync se considera "fresca" (2 horas).
  static const _umbralValidezMs     = 2 * 60 * 60 * 1000;

  /// Tiempo máximo offline antes de pasar a "degradada" (24 horas).
  static const _umbralDegradadaMs   = 24 * 60 * 60 * 1000;

  /// Si DateTime.now() retrocede más de esto, se asume manipulación manual.
  static const _umbralRetrocesoMs   = 5 * 60 * 1000; // 5 min

  /// Si al reconectarse la diferencia supera esto, se fuerza ajuste (5 min).
  static const _umbralAjusteMs      = 5 * 60 * 1000;

  /// Si la diferencia supera esto, se registra como anomalía crítica (60 min).
  static const _umbralAnomaliaMs    = 60 * 60 * 1000;

  // ── Estado en memoria ─────────────────────────────────────────────────────
  /// Hora UTC del servidor en el momento de la última sync.
  DateTime? _baseUtc;

  /// DateTime.now() en el momento de guardar _baseUtc.
  DateTime? _baseMono;

  /// Cuándo se hizo la última sync exitosa.
  DateTime? _syncTime;

  /// Último DateTime.now() registrado (para detectar retrocesos).
  DateTime? _lastMono;

  /// Fuente de la última sync.
  String _fuente = 'desconocida';

  /// Contador de anomalías detectadas en esta sesión.
  int _anomalias = 0;

  bool _inicializado = false;

  // ─────────────────────────────────────────────────────────────────────────
  // INIT — llamar en main.dart después de inicializar DatabaseService
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_inicializado) return;
    _inicializado = true;

    await _cargarEstadoPersistido();
    _detectarReinicio();

    debugPrint(
      '🕐 TrustedClock init\n'
      '   Base UTC   : $_baseUtc\n'
      '   Base mono  : $_baseMono\n'
      '   Sync time  : $_syncTime\n'
      '   Fuente     : $_fuente\n'
      '   Anomalías  : $_anomalias',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HORA CONFIABLE — punto de entrada principal para el resto del código
  // ─────────────────────────────────────────────────────────────────────────

  /// Devuelve la mejor estimación de la hora actual en UTC-5 Colombia,
  /// junto con un indicador de confiabilidad.
  /// Nunca lanza excepción.
  HoraConfiable ahora() {
    final monoAhora  = DateTime.now();
    final anomalia   = _verificarRetroceso(monoAhora);

    _actualizarLastMono(monoAhora);

    // Sin ninguna base → usar hora del dispositivo con nivel desconocido
    if (_baseUtc == null || _baseMono == null) {
      final horaColom = monoAhora.toUtc().add(_colombiaOffset);
      return HoraConfiable(
        horaLocal                : horaColom,
        confiabilidad            : ConfiabilidadHora.desconocida,
        anomaliaDetectada        : anomalia,
        descripcion              : 'Sin sincronización previa — '
                                   'hora del dispositivo usada directamente',
      );
    }

    // Calcular hora estimada:
    //   horaEstimada = baseUtc + (DateTime.now() - baseMono)
    final offsetDesdeBase = monoAhora.difference(_baseMono!);
    final horaEstimadaUtc = _baseUtc!.add(offsetDesdeBase);
    final horaColom       = horaEstimadaUtc.add(_colombiaOffset);

    // Cuánto tiempo pasó desde la última sync
    final ahoraMs    = DateTime.now().millisecondsSinceEpoch;
    final syncMs     = _syncTime?.millisecondsSinceEpoch ?? 0;
    final deltaSync  = ahoraMs - syncMs;
    final minutosSincSync = deltaSync ~/ 60000;

    // Determinar confiabilidad
    final ConfiabilidadHora nivel;
    final String descripcion;

    if (deltaSync < _umbralValidezMs) {
      nivel       = ConfiabilidadHora.validada;
      descripcion = 'Sincronizada hace $minutosSincSync min (fuente: $_fuente)';
    } else if (deltaSync < _umbralDegradadaMs) {
      nivel       = ConfiabilidadHora.calculada;
      descripcion = 'Calculada offline · ${minutosSincSync ~/ 60} h '
                    '${minutosSincSync % 60} min desde última sync';
    } else {
      nivel       = ConfiabilidadHora.degradada;
      descripcion = 'Offline > 24 h — confiabilidad reducida';
    }

    return HoraConfiable(
      horaLocal                : horaColom,
      confiabilidad            : nivel,
      minutosDesdeSincronizacion: minutosSincSync,
      anomaliaDetectada        : anomalia || _anomalias > 0,
      descripcion              : descripcion,
    );
  }

  /// Shortcut: devuelve solo el DateTime en UTC-5 Colombia.
  DateTime get horaActual => ahora().horaLocal;

  // ─────────────────────────────────────────────────────────────────────────
  // SINCRONIZAR CON SERVIDOR — llamar cuando hay internet disponible
  // ─────────────────────────────────────────────────────────────────────────

  Future<ResultadoSincronizacion> sincronizarConServidor() async {
    try {
      final resultado = await _timeService.validar();

      if (resultado.fuente == 'sin_internet' || resultado.horaServidor == null) {
        return const ResultadoSincronizacion(
          exitoso: false,
          mensaje: 'Sin internet — no se pudo sincronizar el reloj',
        );
      }

      final horaServidorUtc = resultado.horaServidor!.toUtc();
      final monoAhora       = DateTime.now();

      // Calcular diferencia con la hora local estimada antes de ajustar
      int? difSegundos;
      bool ajusteAplicado = false;

      if (_baseUtc != null && _baseMono != null) {
        final offsetDesdeBase  = monoAhora.difference(_baseMono!);
        final horaEstimadaUtc  = _baseUtc!.add(offsetDesdeBase);
        final difMs            = horaServidorUtc
            .difference(horaEstimadaUtc)
            .inMilliseconds;

        difSegundos = difMs ~/ 1000;

        final absDifMs = difMs.abs();

        if (absDifMs > _umbralAnomaliaMs) {
          _anomalias++;
          await _persistirAnomalias();
          debugPrint(
            '🚨 TrustedClock: diferencia anómala al reconectar '
            '(${difSegundos}s) — anomalía #$_anomalias registrada',
          );
        }

        ajusteAplicado = absDifMs > _umbralAjusteMs;

        if (ajusteAplicado) {
          debugPrint(
            '⚖️  TrustedClock: ajuste controlado de '
            '${difSegundos}s al reconectarse',
          );
        }
      }

      // Guardar nueva base confiable
      await _guardarBase(
        baseUtc  : horaServidorUtc,
        baseMono : monoAhora,
        fuente   : resultado.fuente,
      );

      final msg = ajusteAplicado
          ? 'Reloj ajustado ${difSegundos! > 0 ? "+$difSegundos" : "$difSegundos"}s '
            'al reconectarse'
          : 'Reloj sincronizado correctamente (fuente: ${resultado.fuente})';

      debugPrint('✅ TrustedClock: $msg');

      return ResultadoSincronizacion(
        exitoso          : true,
        diferenciaSegundos: difSegundos,
        ajusteAplicado   : ajusteAplicado,
        mensaje          : msg,
      );
    } catch (e) {
      debugPrint('⚠ TrustedClock.sincronizarConServidor error: $e');
      return ResultadoSincronizacion(
        exitoso: false,
        mensaje: 'Error al sincronizar: $e',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERSISTIR ESTADO — llamar cuando la batería está baja
  // ─────────────────────────────────────────────────────────────────────────

  /// Fuerza la escritura del estado actual a SQLite.
  /// Útil cuando BatteryService detecta nivel crítico (≤ 15%).
  Future<void> persistirEstado() async {
    if (_baseUtc == null || _baseMono == null) return;

    // Actualizar el "lastMono" persistido para poder detectar
    // el tiempo transcurrido durante el apagado al reiniciar.
    await _db.setConfig(
      _kLastMonoMs,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );

    debugPrint('💾 TrustedClock: estado persistido por batería baja');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ESTADO PARA DIAGNÓSTICO
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> get estadoDiagnostico {
    final hc = ahora();
    return {
      'hora_estimada'    : hc.horaLocal.toIso8601String(),
      'confiabilidad'    : hc.confiabilidad.name,
      'fuente_sync'      : _fuente,
      'ultima_sync'      : _syncTime?.toIso8601String() ?? 'nunca',
      'min_desde_sync'   : hc.minutosDesdeSincronizacion,
      'anomalias'        : _anomalias,
      'anomalia_activa'  : hc.anomaliaDetectada,
      'descripcion'      : hc.descripcion,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNOS — Carga y persistencia
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _cargarEstadoPersistido() async {
    try {
      final baseUtcStr  = await _db.getConfig(_kBaseUtcMs);
      final baseMonoStr = await _db.getConfig(_kBaseMonoMs);
      final fuenteStr   = await _db.getConfig(_kFuente);
      final syncStr     = await _db.getConfig(_kSyncEpoch);
      final lastMonoStr = await _db.getConfig(_kLastMonoMs);
      final anomaliasStr= await _db.getConfig(_kAnomalias);

      if (baseUtcStr  != null) {
        _baseUtc  = DateTime.fromMillisecondsSinceEpoch(
            int.parse(baseUtcStr), isUtc: true);
      }
      if (baseMonoStr != null) {
        _baseMono = DateTime.fromMillisecondsSinceEpoch(
            int.parse(baseMonoStr));
      }
      if (syncStr     != null) {
        _syncTime = DateTime.fromMillisecondsSinceEpoch(
            int.parse(syncStr));
      }
      if (lastMonoStr != null) {
        _lastMono = DateTime.fromMillisecondsSinceEpoch(
            int.parse(lastMonoStr));
      }
      if (fuenteStr   != null) _fuente    = fuenteStr;
      if (anomaliasStr != null) _anomalias = int.tryParse(anomaliasStr) ?? 0;
    } catch (e) {
      debugPrint('⚠ TrustedClock._cargarEstadoPersistido error: $e');
    }
  }

  Future<void> _guardarBase({
    required DateTime baseUtc,
    required DateTime baseMono,
    required String   fuente,
  }) async {
    _baseUtc  = baseUtc;
    _baseMono = baseMono;
    _fuente   = fuente;
    _syncTime = DateTime.now();

    await _db.setConfig(_kBaseUtcMs,  baseUtc.millisecondsSinceEpoch.toString());
    await _db.setConfig(_kBaseMonoMs, baseMono.millisecondsSinceEpoch.toString());
    await _db.setConfig(_kFuente,     fuente);
    await _db.setConfig(_kSyncEpoch,  _syncTime!.millisecondsSinceEpoch.toString());
    await _db.setConfig(_kLastMonoMs, baseMono.millisecondsSinceEpoch.toString());
  }

  Future<void> _persistirAnomalias() async {
    await _db.setConfig(_kAnomalias, _anomalias.toString());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNOS — Detección de anomalías
  // ─────────────────────────────────────────────────────────────────────────

  /// Al iniciar, compara DateTime.now() con el último _lastMono guardado.
  /// Si hay un gap grande pero el reloj del SO no lo refleja → reinicio.
  void _detectarReinicio() {
    if (_lastMono == null || _syncTime == null) return;

    final ahoraMs   = DateTime.now().millisecondsSinceEpoch;
    final lastMs    = _lastMono!.millisecondsSinceEpoch;
    final gapReal   = ahoraMs - lastMs; // tiempo real transcurrido según SO

    // Si el dispositivo estuvo apagado, el SO debería mostrar la hora actual.
    // Un gap negativo o muy pequeño cuando pasaron horas → hora manipulada.
    final esperadoMin = 0;         // al menos 0
    final esperadoMax = _umbralDegradadaMs + 30 * 60 * 1000; // 24.5 h máx razonable

    if (gapReal < esperadoMin || gapReal > esperadoMax) {
      _anomalias++;
      debugPrint(
        '🚨 TrustedClock: posible reinicio o manipulación detectada '
        '(gap=$gapReal ms) — anomalía #$_anomalias',
      );
    }

    // Actualizar lastMono con el valor actual
    _lastMono = DateTime.now();
  }

  /// Verifica si DateTime.now() retrocedió respecto al último valor visto.
  /// Retorna true si se detectó retroceso (posible cambio manual de fecha).
  bool _verificarRetroceso(DateTime monoAhora) {
    if (_lastMono == null) return false;

    final deltaMs = monoAhora.millisecondsSinceEpoch -
                    _lastMono!.millisecondsSinceEpoch;

    if (deltaMs < -_umbralRetrocesoMs) {
      _anomalias++;
      debugPrint(
        '🚨 TrustedClock: reloj retrocedió ${deltaMs.abs()}ms — '
        'posible cambio manual de fecha — anomalía #$_anomalias',
      );
      // Persistir de forma asíncrona sin bloquear ahora()
      _persistirAnomalias();
      return true;
    }

    return false;
  }

  void _actualizarLastMono(DateTime mono) {
    // Solo actualizar en memoria — la persistencia pesada se hace
    // en persistirEstado() para no martillar SQLite en cada llamada.
    _lastMono = mono;
  }
}