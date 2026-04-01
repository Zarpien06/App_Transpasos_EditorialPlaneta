// lib/core/database_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Base de datos SQLite local del dispositivo.
// NO es tu servidor — este archivo vive dentro del teléfono/tablet.
// Flutter lo crea automáticamente la primera vez que se abre la app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  // ── Abrir / crear la base de datos ─────────────────────────────────────────
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    // getDatabasesPath() devuelve la carpeta de datos del dispositivo
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'feria_traspasos.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  // ── Crear las tablas la primera vez ────────────────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    // ── 1. Configuración del dispositivo (device_id, inicializado) ───────────
    await db.execute('''
      CREATE TABLE config (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    // ── 2. Traspasos (en_proceso | pendiente | sincronizado | error) ─────────
    await db.execute('''
      CREATE TABLE traspasos_local (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        local_uuid       TEXT    NOT NULL UNIQUE,
        device_id        TEXT    NOT NULL,
        origen_json      TEXT,
        destino_json     TEXT,
        estado           TEXT    DEFAULT 'en_proceso',
        num_movimiento   INTEGER,
        fecha_creacion   TEXT,
        fecha_sync       TEXT,
        error_msg        TEXT
      )
    ''');

    // ── 3. Líneas / libros de cada traspaso ──────────────────────────────────
    await db.execute('''
      CREATE TABLE lineas_local (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        traspaso_uuid TEXT    NOT NULL,
        codigo        TEXT    NOT NULL,
        descripcion   TEXT,
        cantidad      INTEGER DEFAULT 1
      )
    ''');

    // ── 4. Cola de sincronización ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE sync_queue (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        traspaso_uuid TEXT    NOT NULL UNIQUE,
        intentos      INTEGER DEFAULT 0,
        ultimo_error  TEXT,
        creado        TEXT
      )
    ''');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CONFIG
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> setConfig(String clave, String valor) async {
    final db = await database;
    await db.insert(
      'config',
      {'clave': clave, 'valor': valor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getConfig(String clave) async {
    final db = await database;
    final rows = await db.query('config',
        where: 'clave = ?', whereArgs: [clave]);
    if (rows.isEmpty) return null;
    return rows.first['valor'] as String?;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TRASPASOS
  // ════════════════════════════════════════════════════════════════════════════

  /// Inserta un traspaso nuevo en estado 'en_proceso'.
  /// Se llama en el PRIMER paso del flujo, antes de cambiar de pantalla.
  Future<void> insertarTraspaso(Map<String, dynamic> datos) async {
    final db = await database;
    await db.insert('traspasos_local', datos,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Actualiza cualquier campo de un traspaso existente.
  Future<void> actualizarTraspaso(
      String uuid, Map<String, dynamic> cambios) async {
    final db = await database;
    await db.update(
      'traspasos_local',
      cambios,
      where: 'local_uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Devuelve el traspaso más reciente en estado 'en_proceso' (para recuperar
  /// sesión al reabrir la app o salir del modo kiosko).
  Future<Map<String, dynamic>?> getTraspasoEnProceso() async {
    final db = await database;
    final rows = await db.query(
      'traspasos_local',
      where: "estado = 'en_proceso'",
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Todos los traspasos pendientes de sincronizar.
  Future<List<Map<String, dynamic>>> getTraspasosPendientes() async {
    final db = await database;
    return await db.query(
      'traspasos_local',
      where: "estado = 'pendiente'",
      orderBy: 'fecha_creacion ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getTodosLosTraspasos() async {
    final db = await database;
    return await db.query('traspasos_local', orderBy: 'fecha_creacion DESC');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LÍNEAS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> insertarLinea(Map<String, dynamic> linea) async {
    final db = await database;
    await db.insert('lineas_local', linea);
  }

  Future<void> actualizarCantidadLinea(int id, int cantidad) async {
    final db = await database;
    await db.update(
      'lineas_local',
      {'cantidad': cantidad},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> eliminarLinea(int id) async {
    final db = await database;
    await db.delete('lineas_local', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getLineasDeTraspaso(
      String traspasoUuid) async {
    final db = await database;
    return await db.query(
      'lineas_local',
      where: 'traspaso_uuid = ?',
      whereArgs: [traspasoUuid],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SYNC QUEUE
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> encolarSync(String uuid) async {
    final db = await database;
    await db.insert(
      'sync_queue',
      {
        'traspaso_uuid': uuid,
        'intentos': 0,
        'creado': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> incrementarIntento(String uuid, String error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE sync_queue
      SET intentos = intentos + 1, ultimo_error = ?
      WHERE traspaso_uuid = ?
    ''', [error, uuid]);
  }

  Future<void> eliminarDeQueue(String uuid) async {
    final db = await database;
    await db.delete('sync_queue',
        where: 'traspaso_uuid = ?', whereArgs: [uuid]);
  }

  Future<List<Map<String, dynamic>>> getQueue() async {
    final db = await database;
    return await db.query('sync_queue', orderBy: 'creado ASC');
  }
}