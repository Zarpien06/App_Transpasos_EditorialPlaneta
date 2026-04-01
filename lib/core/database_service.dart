// lib/core/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'feria_traspasos.db');
    return await openDatabase(
      path,
      version: 2,           // ← subimos versión para onUpgrade
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE config (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

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

    await db.execute('''
      CREATE TABLE lineas_local (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        traspaso_uuid TEXT    NOT NULL,
        codigo        TEXT    NOT NULL,
        descripcion   TEXT,
        cantidad      INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        traspaso_uuid TEXT    NOT NULL UNIQUE,
        intentos      INTEGER DEFAULT 0,
        ultimo_error  TEXT,
        creado        TEXT
      )
    ''');

    // ✅ NUEVAS TABLAS
    await _crearTablaAdmin(db);
    await _crearTablaProductos(db);
  }

  // onUpgrade para dispositivos que ya tienen v1 instalada
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _crearTablaAdmin(db);
      await _crearTablaProductos(db);
    }
  }

  Future<void> _crearTablaAdmin(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS admin_local (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario  TEXT    NOT NULL UNIQUE,
        password TEXT    NOT NULL
      )
    ''');
  }

  Future<void> _crearTablaProductos(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productos_local (
        id               INTEGER PRIMARY KEY,
        ISBN             TEXT,
        EAN              TEXT,
        Referencia       TEXT,
        Desc_Referencia  TEXT,
        Precio           REAL,
        Cantidad         INTEGER,
        Autor            TEXT,
        Sello_Editorial  TEXT,
        Familia          INTEGER
      )
    ''');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CONFIG
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> setConfig(String clave, String valor) async {
    final db = await database;
    await db.insert('config', {'clave': clave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getConfig(String clave) async {
    final db = await database;
    final rows = await db.query('config', where: 'clave = ?', whereArgs: [clave]);
    if (rows.isEmpty) return null;
    return rows.first['valor'] as String?;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ADMIN LOCAL — guardar y validar sin internet
  // ════════════════════════════════════════════════════════════════════════════

  /// Guarda/actualiza las credenciales del admin descargadas del servidor
  Future<void> guardarAdminLocal(String usuario, String password) async {
    final db = await database;
    await db.insert(
      'admin_local',
      {'usuario': usuario, 'password': password},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Valida credenciales contra la BD local (sin internet)
  Future<bool> validarAdminLocal(String usuario, String password) async {
    final db = await database;
    final rows = await db.query(
      'admin_local',
      where: 'usuario = ? AND password = ?',
      whereArgs: [usuario, password],
    );
    return rows.isNotEmpty;
  }

  /// Devuelve los datos del admin local (para el dashboard)
  Future<Map<String, dynamic>?> getAdminLocal(String usuario) async {
    final db = await database;
    final rows = await db.query(
      'admin_local',
      where: 'usuario = ?',
      whereArgs: [usuario],
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRODUCTOS LOCAL
  // ════════════════════════════════════════════════════════════════════════════

  /// Reemplaza todos los productos con los descargados del servidor
  Future<void> guardarProductos(List<Map<String, dynamic>> productos) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('productos_local'); // limpiar antes de insertar
    for (final p in productos) {
      batch.insert('productos_local', {
        'id':              p['id'],
        'ISBN':            p['ISBN'],
        'EAN':             p['EAN'],
        'Referencia':      p['Referencia'],
        'Desc_Referencia': p['Desc_Referencia'],
        'Precio':          p['Precio'],
        'Cantidad':        p['Cantidad'],
        'Autor':           p['Autor'],
        'Sello_Editorial': p['Sello_Editorial'],
        'Familia':         p['Familia'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProductos() async {
    final db = await database;
    return await db.query('productos_local');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TRASPASOS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> insertarTraspaso(Map<String, dynamic> datos) async {
    final db = await database;
    await db.insert('traspasos_local', datos,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> actualizarTraspaso(String uuid, Map<String, dynamic> cambios) async {
    final db = await database;
    await db.update('traspasos_local', cambios,
        where: 'local_uuid = ?', whereArgs: [uuid]);
  }

  Future<Map<String, dynamic>?> getTraspasoEnProceso() async {
    final db = await database;
    final rows = await db.query('traspasos_local',
        where: "estado = 'en_proceso'",
        orderBy: 'fecha_creacion DESC',
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getTraspasosPendientes() async {
    final db = await database;
    return await db.query('traspasos_local',
        where: "estado = 'pendiente'", orderBy: 'fecha_creacion ASC');
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
    await db.update('lineas_local', {'cantidad': cantidad},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> eliminarLinea(int id) async {
    final db = await database;
    await db.delete('lineas_local', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getLineasDeTraspaso(String traspasoUuid) async {
    final db = await database;
    return await db.query('lineas_local',
        where: 'traspaso_uuid = ?', whereArgs: [traspasoUuid]);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SYNC QUEUE
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> encolarSync(String uuid) async {
    final db = await database;
    await db.insert('sync_queue',
        {'traspaso_uuid': uuid, 'intentos': 0, 'creado': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> incrementarIntento(String uuid, String error) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE sync_queue SET intentos = intentos + 1, ultimo_error = ? WHERE traspaso_uuid = ?',
        [error, uuid]);
  }

  Future<void> eliminarDeQueue(String uuid) async {
    final db = await database;
    await db.delete('sync_queue', where: 'traspaso_uuid = ?', whereArgs: [uuid]);
  }

  Future<List<Map<String, dynamic>>> getQueue() async {
    final db = await database;
    return await db.query('sync_queue', orderBy: 'creado ASC');
  }
}