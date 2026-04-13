// lib/services/sync_log_service.dart
//
// Gestiona el historial de sincronización (descarga y subida) persistido
// en SQLite. Cada evento tiene un estado real: ok | omitido | fallido.
// Los widgets escuchan cambios a través de un Stream broadcast.

import 'dart:async';
import '../core/database_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS
// ─────────────────────────────────────────────────────────────────────────────

enum SyncLogTipo { descarga, subida, sistema, producto }

enum SyncLogEstado { ok, omitido, fallido, enProceso }

class SyncLogEntry {
  final int? id;
  final SyncLogTipo tipo;
  final SyncLogEstado estado;
  final String mensaje;
  final String? detalle;      // JSON / motivo ampliado
  final String? uuid;         // traspaso relacionado (si aplica)
  final String? manuca;       // clave única del movimiento en hmoval
  final DateTime timestamp;

  const SyncLogEntry({
    this.id,
    required this.tipo,
    required this.estado,
    required this.mensaje,
    this.detalle,
    this.uuid,
    this.manuca,
    required this.timestamp,
  });

  // ── Persistencia ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'tipo'      : tipo.name,
        'estado'    : estado.name,
        'mensaje'   : mensaje,
        'detalle'   : detalle,
        'uuid'      : uuid,
        'manuca'    : manuca,
        'timestamp' : timestamp.toIso8601String(),
      };

  factory SyncLogEntry.fromMap(Map<String, dynamic> m) => SyncLogEntry(
        id        : m['id'] as int?,
        tipo      : SyncLogTipo.values.firstWhere(
                      (e) => e.name == m['tipo'],
                      orElse: () => SyncLogTipo.sistema),
        estado    : SyncLogEstado.values.firstWhere(
                      (e) => e.name == m['estado'],
                      orElse: () => SyncLogEstado.fallido),
        mensaje   : m['mensaje'] as String? ?? '',
        detalle   : m['detalle'] as String?,
        uuid      : m['uuid']    as String?,
        manuca    : m['manuca']  as String?,
        timestamp : DateTime.tryParse(m['timestamp'] as String? ?? '') ??
                    DateTime.now(),
      );

  // ── Helpers UI ────────────────────────────────────────────────────────────

  String get estadoLabel {
    switch (estado) {
      case SyncLogEstado.ok:        return 'OK';
      case SyncLogEstado.omitido:   return 'OMITIDO';
      case SyncLogEstado.fallido:   return 'ERROR';
      case SyncLogEstado.enProceso: return '…';
    }
  }

  String get tipoLabel {
    switch (tipo) {
      case SyncLogTipo.descarga: return '↓ Descarga';
      case SyncLogTipo.subida:   return '↑ Subida';
      case SyncLogTipo.sistema:  return '⚙ Sistema';
      case SyncLogTipo.producto: return '📦 Producto';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO
// ─────────────────────────────────────────────────────────────────────────────

class SyncLogService {
  // Singleton
  static final SyncLogService _instance = SyncLogService._internal();
  factory SyncLogService() => _instance;
  SyncLogService._internal();

  // Stream que notifica a los widgets suscritos
  final _controller = StreamController<List<SyncLogEntry>>.broadcast();
  Stream<List<SyncLogEntry>> get stream => _controller.stream;

  // Cache en memoria para acceso inmediato
  List<SyncLogEntry> _cache = [];
  List<SyncLogEntry> get entries => List.unmodifiable(_cache);

  // ── Inicialización ────────────────────────────────────────────────────────

  /// Crea la tabla si no existe y carga el historial reciente.
  Future<void> init() async {
    await _crearTabla();
    await _refrescar();
  }

  Future<void> _crearTabla() async {
    final db = await DatabaseService().database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_logs (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo      TEXT    NOT NULL,
        estado    TEXT    NOT NULL,
        mensaje   TEXT    NOT NULL,
        detalle   TEXT,
        uuid      TEXT,
        manuca    TEXT,
        timestamp TEXT    NOT NULL
      )
    ''');
  }

  // ── Escritura ─────────────────────────────────────────────────────────────

  Future<SyncLogEntry> agregar({
    required SyncLogTipo tipo,
    required SyncLogEstado estado,
    required String mensaje,
    String? detalle,
    String? uuid,
    String? manuca,
  }) async {
    final entry = SyncLogEntry(
      tipo      : tipo,
      estado    : estado,
      mensaje   : mensaje,
      detalle   : detalle,
      uuid      : uuid,
      manuca    : manuca,
      timestamp : DateTime.now(),
    );

    final db = await DatabaseService().database;
    await db.insert('sync_logs', entry.toMap());

    // Limitar a 500 registros para no inflar la BD
    await db.rawDelete('''
      DELETE FROM sync_logs
      WHERE id NOT IN (
        SELECT id FROM sync_logs ORDER BY id DESC LIMIT 500
      )
    ''');

    await _refrescar();
    return entry;
  }

  // Sobrescribe el estado de la última entrada "enProceso" del mismo tipo
  Future<void> actualizarUltimo({
    required SyncLogTipo tipo,
    required SyncLogEstado nuevoEstado,
    String? nuevoMensaje,
    String? detalle,
  }) async {
    final db = await DatabaseService().database;

    // Buscar el último registro en proceso de ese tipo
    final rows = await db.query(
      'sync_logs',
      where: "tipo = ? AND estado = 'enProceso'",
      whereArgs: [tipo.name],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (rows.isEmpty) return;

    final id = rows.first['id'] as int;
    await db.update(
      'sync_logs',
      {
        'estado' : nuevoEstado.name,
        if (nuevoMensaje != null) 'mensaje': nuevoMensaje,
        if (detalle != null)      'detalle': detalle,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    await _refrescar();
  }

  // ── Lectura ───────────────────────────────────────────────────────────────

  Future<List<SyncLogEntry>> getLogs({int limite = 100}) async {
    final db = await DatabaseService().database;
    final rows = await db.query(
      'sync_logs',
      orderBy: 'id DESC',
      limit: limite,
    );
    return rows.map(SyncLogEntry.fromMap).toList();
  }

  Future<void> limpiar() async {
    final db = await DatabaseService().database;
    await db.delete('sync_logs');
    await _refrescar();
  }

  // ── Privado ───────────────────────────────────────────────────────────────

  Future<void> _refrescar() async {
    _cache = await getLogs();
    if (!_controller.isClosed) {
      _controller.add(_cache);
    }
  }

  void dispose() {
    _controller.close();
  }
}