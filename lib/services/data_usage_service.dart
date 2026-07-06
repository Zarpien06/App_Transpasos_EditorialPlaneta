// lib/services/data_usage_service.dart
// ─────────────────────────────────────────────────────────────
// Monitoreo de consumo de datos móviles / WiFi de la aplicación.
//
// ARQUITECTURA:
//   DataUsageService  → singleton, persiste en SQLite, expone Stream
//   DataUsageEntry    → un registro por petición HTTP
//   DataUsageResumen  → agregado diario/semanal/mensual por proceso
//
// USO:
//   // En ApiService._dio:
//   _dio.interceptors.add(DataUsageInterceptor());
//
//   // Consultar estadísticas:
//   final svc     = DataUsageService();
//   final resumen = await svc.getResumen(periodo: UsagePeriodo.semana);
//
// TABLA: data_usage_logs
//   id          INTEGER PK
//   proceso     TEXT    — 'login' | 'sync_descarga' | 'sync_subida' |
//                         'buscar_libro' | 'ping' | 'producto' | 'otro'
//   url         TEXT    — endpoint completo
//   metodo      TEXT    — GET | POST | HEAD
//   bytes_sent  INTEGER — cuerpo de la petición en bytes
//   bytes_recv  INTEGER — cuerpo de la respuesta en bytes
//   duracion_ms INTEGER — tiempo de respuesta en ms
//   status_code INTEGER — código HTTP (0 si error de red)
//   tipo_red    TEXT    — 'wifi' | 'mobile' | 'ethernet' | 'desconocido'
//   fecha       TEXT    — ISO 8601 (fecha+hora)
//   dia         TEXT    — 'yyyy-MM-dd' (para filtros eficientes)
//   ok          INTEGER — 1 si HTTP 2xx, 0 si error
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/database_service.dart';

// ════════════════════════════════════════════════════════════
// ENUMS Y MODELOS
// ════════════════════════════════════════════════════════════

enum UsagePeriodo { hoy, semana, mes, total }

enum UsageProceso {
  login,
  syncDescarga,
  syncSubida,
  buscarLibro,
  ping,
  producto,
  otro,
}

extension UsageProcesoExt on UsageProceso {
  String get nombre {
    switch (this) {
      case UsageProceso.login:        return 'login';
      case UsageProceso.syncDescarga: return 'sync_descarga';
      case UsageProceso.syncSubida:   return 'sync_subida';
      case UsageProceso.buscarLibro:  return 'buscar_libro';
      case UsageProceso.ping:         return 'ping';
      case UsageProceso.producto:     return 'producto';
      case UsageProceso.otro:         return 'otro';
    }
  }

  String get etiqueta {
    switch (this) {
      case UsageProceso.login:        return '🔐 Inicio de sesión';
      case UsageProceso.syncDescarga: return '↓ Descarga de datos';
      case UsageProceso.syncSubida:   return '↑ Subida de traspasos';
      case UsageProceso.buscarLibro:  return '🔍 Búsqueda de libros';
      case UsageProceso.ping:         return '📡 Verificación conexión';
      case UsageProceso.producto:     return '📦 Agregar producto';
      case UsageProceso.otro:         return '⚙ Otros';
    }
  }
}

// ── Registro individual ───────────────────────────────────────

class DataUsageEntry {
  final int?         id;
  final UsageProceso proceso;
  final String       url;
  final String       metodo;
  final int          bytesSent;
  final int          bytesRecv;
  final int          duracionMs;
  final int          statusCode;
  final String       tipoRed;
  final DateTime     fecha;
  final bool         ok;

  const DataUsageEntry({
    this.id,
    required this.proceso,
    required this.url,
    required this.metodo,
    required this.bytesSent,
    required this.bytesRecv,
    required this.duracionMs,
    required this.statusCode,
    required this.tipoRed,
    required this.fecha,
    required this.ok,
  });

  int get bytesTotal => bytesSent + bytesRecv;

  Map<String, dynamic> toMap() => {
        'proceso'    : proceso.nombre,
        'url'        : url,
        'metodo'     : metodo,
        'bytes_sent' : bytesSent,
        'bytes_recv' : bytesRecv,
        'duracion_ms': duracionMs,
        'status_code': statusCode,
        'tipo_red'   : tipoRed,
        'fecha'      : fecha.toIso8601String(),
        'dia'        : '${fecha.year}-'
                       '${fecha.month.toString().padLeft(2, '0')}-'
                       '${fecha.day.toString().padLeft(2, '0')}',
        'ok'         : ok ? 1 : 0,
      };

  factory DataUsageEntry.fromMap(Map<String, dynamic> m) {
    final procesoStr = m['proceso'] as String? ?? 'otro';
    final proceso = UsageProceso.values.firstWhere(
      (e) => e.nombre == procesoStr,
      orElse: () => UsageProceso.otro,
    );
    return DataUsageEntry(
      id         : m['id']          as int?,
      proceso    : proceso,
      url        : m['url']         as String? ?? '',
      metodo     : m['metodo']      as String? ?? '',
      bytesSent  : m['bytes_sent']  as int?    ?? 0,
      bytesRecv  : m['bytes_recv']  as int?    ?? 0,
      duracionMs : m['duracion_ms'] as int?    ?? 0,
      statusCode : m['status_code'] as int?    ?? 0,
      tipoRed    : m['tipo_red']    as String? ?? 'desconocido',
      fecha      : DateTime.tryParse(m['fecha'] as String? ?? '') ??
                   DateTime.now(),
      ok         : (m['ok'] as int? ?? 0) == 1,
    );
  }
}

// ── Agregado por proceso ──────────────────────────────────────

class DataUsageStats {
  final UsageProceso proceso;
  final int          solicitudes;
  final int          bytesSent;
  final int          bytesRecv;
  final double       duracionPromedioMs;
  final int          errores;

  const DataUsageStats({
    required this.proceso,
    required this.solicitudes,
    required this.bytesSent,
    required this.bytesRecv,
    required this.duracionPromedioMs,
    required this.errores,
  });

  int    get bytesTotal    => bytesSent + bytesRecv;
  double get kb            => bytesTotal / 1024;
  double get mb            => bytesTotal / (1024 * 1024);
  String get formatoLegible => _formatBytes(bytesTotal);

  static String _formatBytes(int bytes) {
    if (bytes < 1024)       return '$bytes B';
    if (bytes < 1048576)    return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
}

// ── Resumen general ───────────────────────────────────────────

class DataUsageResumen {
  final UsagePeriodo             periodo;
  final DateTime                 desde;
  final DateTime                 hasta;
  final int                      totalBytes;
  final int                      totalSolicitudes;
  final int                      totalErrores;
  final String                   tipoRedPredominante;
  final List<DataUsageStats>     porProceso;
  final Map<String, int>         porDia;   // 'yyyy-MM-dd' → bytes

  const DataUsageResumen({
    required this.periodo,
    required this.desde,
    required this.hasta,
    required this.totalBytes,
    required this.totalSolicitudes,
    required this.totalErrores,
    required this.tipoRedPredominante,
    required this.porProceso,
    required this.porDia,
  });

  double get kb => totalBytes / 1024;
  double get mb => totalBytes / (1024 * 1024);

  String get formatoLegible {
    if (totalBytes < 1024)       return '$totalBytes B';
    if (totalBytes < 1048576)    return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1073741824) return '${(totalBytes / 1048576).toStringAsFixed(2)} MB';
    return '${(totalBytes / 1073741824).toStringAsFixed(2)} GB';
  }

  // Estima el plan de datos mensual recomendado basado en el consumo
  String get planRecomendado {
    // Extrapola a un mes completo según el período
    double factorMensual;
    final dias = hasta.difference(desde).inDays + 1;
    factorMensual = 30 / (dias > 0 ? dias : 1);
    final bytesMes = (totalBytes * factorMensual).toInt();
    final mbMes    = bytesMes / (1024 * 1024);

    if (mbMes < 100)   return '100 MB / mes (plan básico)';
    if (mbMes < 500)   return '500 MB / mes';
    if (mbMes < 1024)  return '1 GB / mes';
    if (mbMes < 3072)  return '3 GB / mes';
    if (mbMes < 5120)  return '5 GB / mes';
    return '${(mbMes / 1024).toStringAsFixed(1)} GB / mes (plan personalizado)';
  }
}

// ════════════════════════════════════════════════════════════
// DATA USAGE SERVICE
// ════════════════════════════════════════════════════════════

class DataUsageService {
  // Singleton
  static final DataUsageService _instance = DataUsageService._internal();
  factory DataUsageService() => _instance;
  DataUsageService._internal();

  final _controller = StreamController<DataUsageResumen?>.broadcast();
  Stream<DataUsageResumen?> get stream => _controller.stream;

  // Cache del último resumen diario para el indicador en tiempo real
  DataUsageResumen? _cacheDiario;
  DataUsageResumen? get cacheDiario => _cacheDiario;

  // OPT: guard para ejecutar el DELETE de registros viejos máximo una vez
  // al día. Antes se corría en CADA petición HTTP (ping, hash-check,
  // descarga…), generando un write innecesario a SQLite por cada llamada.
  DateTime? _ultimaLimpieza;

  // ── Inicialización ────────────────────────────────────────────────────────

  Future<void> init() async {
    await _crearTabla();
    await _refrescarCacheDiario();
  }

  Future<void> _crearTabla() async {
    final db = await DatabaseService().database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_usage_logs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        proceso     TEXT    NOT NULL,
        url         TEXT    NOT NULL,
        metodo      TEXT    NOT NULL DEFAULT 'GET',
        bytes_sent  INTEGER NOT NULL DEFAULT 0,
        bytes_recv  INTEGER NOT NULL DEFAULT 0,
        duracion_ms INTEGER NOT NULL DEFAULT 0,
        status_code INTEGER NOT NULL DEFAULT 0,
        tipo_red    TEXT    NOT NULL DEFAULT 'desconocido',
        fecha       TEXT    NOT NULL,
        dia         TEXT    NOT NULL,
        ok          INTEGER NOT NULL DEFAULT 1
      )
    ''');
    // Índices para consultas rápidas por fecha
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_usage_dia
      ON data_usage_logs (dia)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_usage_proceso
      ON data_usage_logs (proceso)
    ''');
  }

  // ── Escritura ─────────────────────────────────────────────────────────────

  /// Registra una petición HTTP completada (o fallida).
  Future<void> registrar({
    required UsageProceso proceso,
    required String       url,
    required String       metodo,
    required int          bytesSent,
    required int          bytesRecv,
    required int          duracionMs,
    required int          statusCode,
    String?               tipoRed,
  }) async {
    try {
      final red   = tipoRed ?? await _detectarTipoRed();
      final ahora = DateTime.now();
      final entry = DataUsageEntry(
        proceso    : proceso,
        url        : url,
        metodo     : metodo,
        bytesSent  : bytesSent,
        bytesRecv  : bytesRecv,
        duracionMs : duracionMs,
        statusCode : statusCode,
        tipoRed    : red,
        fecha      : ahora,
        ok         : statusCode >= 200 && statusCode < 300,
      );

      final db = await DatabaseService().database;
      await db.insert('data_usage_logs', entry.toMap());

      // OPT: el DELETE de registros viejos (> 90 días) es un write costoso
      // en SQLite. Antes se ejecutaba en CADA petición HTTP. Ahora solo corre
      // una vez al día: si _ultimaLimpieza es null o es de un día anterior,
      // se ejecuta y se actualiza la marca; de lo contrario se omite.
      final hoy = DateTime(ahora.year, ahora.month, ahora.day);
      final necesitaLimpiar = _ultimaLimpieza == null ||
          _ultimaLimpieza!.isBefore(hoy);

      if (necesitaLimpiar) {
        final limite    = ahora.subtract(const Duration(days: 90));
        final limiteStr = '${limite.year}-'
            '${limite.month.toString().padLeft(2, '0')}-'
            '${limite.day.toString().padLeft(2, '0')}';
        await db.delete(
          'data_usage_logs',
          where    : 'dia < ?',
          whereArgs: [limiteStr],
        );
        _ultimaLimpieza = hoy;
      }

      await _refrescarCacheDiario();
    } catch (e) {
      debugPrint('⚠ DataUsageService.registrar: $e');
    }
  }

  // ── Consultas ─────────────────────────────────────────────────────────────

  Future<DataUsageResumen> getResumen({
    UsagePeriodo periodo = UsagePeriodo.hoy,
  }) async {
    final ahora = DateTime.now();
    final DateTime desde;
    final DateTime hasta;

    switch (periodo) {
      case UsagePeriodo.hoy:
        desde = DateTime(ahora.year, ahora.month, ahora.day);
        hasta = ahora;
        break;
      case UsagePeriodo.semana:
        desde = ahora.subtract(const Duration(days: 6));
        hasta = ahora;
        break;
      case UsagePeriodo.mes:
        desde = DateTime(ahora.year, ahora.month, 1);
        hasta = ahora;
        break;
      case UsagePeriodo.total:
        desde = DateTime(2024, 1, 1);
        hasta = ahora;
        break;
    }

    final desdeStr = '${desde.year}-'
        '${desde.month.toString().padLeft(2, '0')}-'
        '${desde.day.toString().padLeft(2, '0')}';
    final hastaStr = '${hasta.year}-'
        '${hasta.month.toString().padLeft(2, '0')}-'
        '${hasta.day.toString().padLeft(2, '0')}';

    final db   = await DatabaseService().database;
    final rows = await db.query(
      'data_usage_logs',
      where    : 'dia >= ? AND dia <= ?',
      whereArgs: [desdeStr, hastaStr],
      orderBy  : 'id ASC',
    );

    final entries = rows.map(DataUsageEntry.fromMap).toList();
    return _calcularResumen(entries, periodo, desde, hasta);
  }

  /// Últimas N peticiones individuales (para log detallado)
  Future<List<DataUsageEntry>> getUltimasPeticiones({int limite = 50}) async {
    final db   = await DatabaseService().database;
    final rows = await db.query(
      'data_usage_logs',
      orderBy: 'id DESC',
      limit  : limite,
    );
    return rows.map(DataUsageEntry.fromMap).toList();
  }

  Future<void> limpiarHistorial() async {
    final db = await DatabaseService().database;
    await db.delete('data_usage_logs');
    _cacheDiario    = null;
    _ultimaLimpieza = null; // resetear para que el DELETE corra al reactivarse
    if (!_controller.isClosed) _controller.add(null);
  }

  // ── Interno ───────────────────────────────────────────────────────────────

  DataUsageResumen _calcularResumen(
    List<DataUsageEntry> entries,
    UsagePeriodo         periodo,
    DateTime             desde,
    DateTime             hasta,
  ) {
    int totalBytes       = 0;
    int totalSolicitudes = entries.length;
    int totalErrores     = 0;

    // Acumulado por proceso
    final acumProceso = <UsageProceso, Map<String, dynamic>>{};
    // Acumulado por día
    final acumDia     = <String, int>{};
    // Acumulado por tipo de red
    final acumRed     = <String, int>{};

    for (final e in entries) {
      final bytes = e.bytesTotal;
      totalBytes += bytes;
      if (!e.ok) totalErrores++;

      // Por proceso
      acumProceso[e.proceso] ??= {
        'solicitudes': 0,
        'bytesSent'  : 0,
        'bytesRecv'  : 0,
        'duracion'   : 0,
        'errores'    : 0,
      };
      final p = acumProceso[e.proceso]!;
      p['solicitudes'] = (p['solicitudes'] as int) + 1;
      p['bytesSent']   = (p['bytesSent']   as int) + e.bytesSent;
      p['bytesRecv']   = (p['bytesRecv']   as int) + e.bytesRecv;
      p['duracion']    = (p['duracion']    as int) + e.duracionMs;
      if (!e.ok) p['errores'] = (p['errores'] as int) + 1;

      // Por día
      final dia = '${e.fecha.year}-'
          '${e.fecha.month.toString().padLeft(2, '0')}-'
          '${e.fecha.day.toString().padLeft(2, '0')}';
      acumDia[dia] = (acumDia[dia] ?? 0) + bytes;

      // Por tipo de red
      acumRed[e.tipoRed] = (acumRed[e.tipoRed] ?? 0) + bytes;
    }

    // Construir lista de stats por proceso (ordenada de mayor a menor)
    final porProceso = acumProceso.entries.map((entry) {
      final p      = entry.value;
      final nReqs  = (p['solicitudes'] as int);
      return DataUsageStats(
        proceso            : entry.key,
        solicitudes        : nReqs,
        bytesSent          : p['bytesSent']  as int,
        bytesRecv          : p['bytesRecv']  as int,
        duracionPromedioMs : nReqs > 0
            ? (p['duracion'] as int) / nReqs
            : 0,
        errores            : p['errores']    as int,
      );
    }).toList()
      ..sort((a, b) => b.bytesTotal.compareTo(a.bytesTotal));

    // Red predominante
    String redPred = 'desconocido';
    int    maxRed  = 0;
    for (final entry in acumRed.entries) {
      if (entry.value > maxRed) {
        maxRed = entry.value;
        redPred = entry.key;
      }
    }

    return DataUsageResumen(
      periodo             : periodo,
      desde               : desde,
      hasta               : hasta,
      totalBytes          : totalBytes,
      totalSolicitudes    : totalSolicitudes,
      totalErrores        : totalErrores,
      tipoRedPredominante : redPred,
      porProceso          : porProceso,
      porDia              : acumDia,
    );
  }

  Future<void> _refrescarCacheDiario() async {
    try {
      _cacheDiario = await getResumen(periodo: UsagePeriodo.hoy);
      if (!_controller.isClosed) {
        _controller.add(_cacheDiario);
      }
    } catch (_) {}
  }

  // ── Detectar tipo de red actual ───────────────────────────────────────────

  static Future<String> _detectarTipoRed() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.wifi))     return 'wifi';
      if (results.contains(ConnectivityResult.mobile))   return 'mobile';
      if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
    } catch (_) {}
    return 'desconocido';
  }

  void dispose() {
    _controller.close();
  }
}

// ════════════════════════════════════════════════════════════
// HELPER — inferir proceso desde URL
// ════════════════════════════════════════════════════════════

UsageProceso inferirProceso(String url, String metodo) {
  final u = url.toLowerCase();
  if (u.contains('ping'))                      return UsageProceso.ping;
  if (u.contains('descarga'))                  return UsageProceso.syncDescarga;
  if (u.contains('subir') && metodo == 'POST') return UsageProceso.syncSubida;
  if (u.contains('producto'))                  return UsageProceso.producto;
  return UsageProceso.otro;
}