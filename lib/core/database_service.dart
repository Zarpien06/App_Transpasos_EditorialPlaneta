// lib/core/database_service.dart

import 'dart:convert';
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
    final path   = join(dbPath, 'feria_traspasos.db');
    return await openDatabase(
      path,
      version: 5,          // ← bumped de 4 a 5
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
        num_movimiento   TEXT,
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

    await _crearTablaAdmin(db);
    await _crearTablaProductos(db);
    await _crearTablaUsuariosTranspasos(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _crearTablaAdmin(db);
      await _crearTablaProductos(db);
    }
    if (oldVersion < 3) {
      await _crearTablaUsuariosTranspasos(db);
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE traspasos_local RENAME TO traspasos_local_v3',
      );
      await db.execute('''
        CREATE TABLE traspasos_local (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          local_uuid       TEXT    NOT NULL UNIQUE,
          device_id        TEXT    NOT NULL,
          origen_json      TEXT,
          destino_json     TEXT,
          estado           TEXT    DEFAULT 'en_proceso',
          num_movimiento   TEXT,
          fecha_creacion   TEXT,
          fecha_sync       TEXT,
          error_msg        TEXT
        )
      ''');
      await db.execute('''
        INSERT INTO traspasos_local
          (id, local_uuid, device_id, origen_json, destino_json,
           estado, num_movimiento, fecha_creacion, fecha_sync, error_msg)
        SELECT
          id, local_uuid, device_id, origen_json, destino_json,
          estado, CAST(num_movimiento AS TEXT), fecha_creacion, fecha_sync, error_msg
        FROM traspasos_local_v3
      ''');
      await db.execute('DROP TABLE traspasos_local_v3');
    }
    if (oldVersion < 5) {
      // Agrega Porc_impuesto y pendiente_sync a la tabla de productos.
      // Se usa IF NOT EXISTS para que sea idempotente en caso de re-ejecución.
      try {
        await db.execute(
          'ALTER TABLE productos_local ADD COLUMN Porc_impuesto REAL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE productos_local ADD COLUMN pendiente_sync INTEGER DEFAULT 0',
        );
      } catch (_) {}
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
        Familia          INTEGER,
        Porc_impuesto    REAL    DEFAULT 0,
        pendiente_sync   INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _crearTablaUsuariosTranspasos(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuarios_transpasos_local (
        Cod_UsuarioT    INTEGER PRIMARY KEY,
        Nombre_UsuarioT TEXT,
        Clave_UsuarioT  TEXT    NOT NULL,
        Codigo_Almacen  TEXT,
        Stand           TEXT,
        Empresa         TEXT,
        Actividad       TEXT,
        Estado_UsuarioT INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_clave_usuariot
      ON usuarios_transpasos_local (Clave_UsuarioT)
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
    final db   = await database;
    final rows = await db.query('config',
        where: 'clave = ?', whereArgs: [clave]);
    if (rows.isEmpty) return null;
    return rows.first['valor'] as String?;
  }

  // ─── Consecutivo por dispositivo (manuma) ─────────────────────────────────

  Future<int> getNextManuma(String deviceId) async {
    final db    = await database;
    final clave = 'contador_$deviceId';

    return await db.transaction((txn) async {
      final rows = await txn.query(
        'config',
        where: 'clave = ?',
        whereArgs: [clave],
        limit: 1,
      );

      int actual = 0;
      if (rows.isNotEmpty) {
        actual = int.tryParse(rows.first['valor'].toString()) ?? 0;
      }

      final siguiente = actual + 1;
      await txn.insert(
        'config',
        {'clave': clave, 'valor': siguiente.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return siguiente;
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ADMIN LOCAL
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> guardarAdminLocal(String usuario, String password) async {
    final db = await database;
    await db.insert(
      'admin_local',
      {'usuario': usuario, 'password': password},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> validarAdminLocal(String usuario, String password) async {
    final db   = await database;
    final rows = await db.query(
      'admin_local',
      where: 'usuario = ? AND password = ?',
      whereArgs: [usuario, password],
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getAdminLocal(String usuario) async {
    final db   = await database;
    final rows = await db.query(
      'admin_local',
      where: 'usuario = ?',
      whereArgs: [usuario],
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // USUARIOS TRANSPASOS LOCAL
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> guardarUsuariosTranspasos(
      List<Map<String, dynamic>> usuarios) async {
    final db    = await database;
    final batch = db.batch();
    batch.delete('usuarios_transpasos_local');
    for (final u in usuarios) {
      batch.insert(
        'usuarios_transpasos_local',
        {
          'Cod_UsuarioT'    : u['Cod_UsuarioT'],
          'Nombre_UsuarioT' : u['Nombre_UsuarioT'],
          'Clave_UsuarioT'  : u['Clave_UsuarioT']?.toString().trim(),
          'Codigo_Almacen'  : u['Codigo_Almacen'],
          'Stand'           : u['Stand'],
          'Empresa'         : u['Empresa'],
          'Actividad'       : u['Actividad'],
          'Estado_UsuarioT' : u['Estado_UsuarioT'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> buscarUsuarioPorClave(String clave) async {
    final db   = await database;
    final rows = await db.query(
      'usuarios_transpasos_local',
      where: 'Clave_UsuarioT = ? AND Estado_UsuarioT = 1',
      whereArgs: [clave],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getTodosUsuariosTranspasos() async {
    final db = await database;
    return await db.query(
      'usuarios_transpasos_local',
      where: 'Estado_UsuarioT = 1',
      orderBy: 'Nombre_UsuarioT ASC',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRODUCTOS LOCAL
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> guardarProductos(List<Map<String, dynamic>> productos) async {
    final db    = await database;
    final batch = db.batch();
    batch.delete('productos_local');
    for (final p in productos) {
      batch.insert(
        'productos_local',
        {
          'id'             : p['id'],
          'ISBN'           : p['ISBN'],
          'EAN'            : p['EAN'],
          'Referencia'     : p['Referencia'],
          'Desc_Referencia': p['Desc_Referencia'],
          'Precio'         : p['Precio'],
          'Cantidad'       : p['Cantidad'],
          'Autor'          : p['Autor'],
          'Sello_Editorial': p['Sello_Editorial'],
          'Familia'        : p['Familia'],
          'Porc_impuesto'  : p['Porc_impuesto'] ?? 0,
          'pendiente_sync' : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getProductos() async {
    final db = await database;
    return await db.query('productos_local');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSERTAR O ACTUALIZAR PRODUCTO INDIVIDUAL
  // ─────────────────────────────────────────────────────────────────────────
  // Usado por ApiService.agregarProducto() y buscarLibro() para cachear
  // productos nuevos sin borrar el catálogo completo.
  //
  // Campos requeridos: EAN, Desc_Referencia, Precio
  // Campos opcionales con defaults: ISBN='', Referencia='999999',
  //   Porc_impuesto=0, pendiente_sync=0
  //
  // Si el EAN ya existe → actualiza Desc_Referencia, Precio y pendiente_sync.
  // Si no existe → inserta con todos los campos.

  Future<void> insertarOActualizarProducto(
      Map<String, dynamic> producto) async {
    final db  = await database;
    final ean = producto['EAN']?.toString().trim() ?? '';

    if (ean.isEmpty) return;

    // ── Buscar si ya existe por EAN ───────────────────────────────────
    final existentes = await db.query(
      'productos_local',
      where: 'EAN = ?',
      whereArgs: [ean],
      limit: 1,
    );

    if (existentes.isNotEmpty) {
      // Actualizar solo los campos que pueden cambiar
      await db.update(
        'productos_local',
        {
          'Desc_Referencia': producto['Desc_Referencia'] ?? existentes.first['Desc_Referencia'],
          'Precio'         : producto['Precio']          ?? existentes.first['Precio'],
          'Porc_impuesto'  : producto['Porc_impuesto']   ?? existentes.first['Porc_impuesto'] ?? 0,
          'pendiente_sync' : producto['pendiente_sync']  ?? 0,
        },
        where: 'EAN = ?',
        whereArgs: [ean],
      );
    } else {
      // Insertar nuevo — id es autoincrement cuando no se pasa
      await db.insert(
        'productos_local',
        {
          'ISBN'           : producto['ISBN']            ?? '',
          'EAN'            : ean,
          'Referencia'     : producto['Referencia']      ?? '999999',
          'Desc_Referencia': producto['Desc_Referencia'] ?? '',
          'Precio'         : producto['Precio']          ?? 0,
          'Cantidad'       : null,
          'Autor'          : '',
          'Sello_Editorial': '',
          'Familia'        : null,
          'Porc_impuesto'  : producto['Porc_impuesto']   ?? 0,
          'pendiente_sync' : producto['pendiente_sync']  ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TRASPASOS
  // ════════════════════════════════════════════════════════════════════════════

  Future<int> insertarTraspasoReturnId(Map<String, dynamic> datos) async {
    final db = await database;

    if (!datos.containsKey('device_id')) {
      throw Exception('device_id es obligatorio');
    }

    return await db.insert(
      'traspasos_local',
      datos,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertarTraspaso(Map<String, dynamic> datos) async {
    await insertarTraspasoReturnId(datos);
  }

  Future<void> actualizarTraspaso(
      String uuid, Map<String, dynamic> cambios) async {
    final db = await database;
    await db.update('traspasos_local', cambios,
        where: 'local_uuid = ?', whereArgs: [uuid]);
  }

  Future<Map<String, dynamic>?> getTraspasoEnProceso() async {
    final db   = await database;
    final rows = await db.query(
      'traspasos_local',
      where: "estado = 'en_proceso'",
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
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
  // LOG DE TRASPASOS — para el panel admin
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getUltimosTraspasos(
      {int limite = 30}) async {
    final db = await database;

    final traspasos = await db.query(
      'traspasos_local',
      orderBy: 'id DESC',
      limit: limite,
    );

    final resultado = <Map<String, dynamic>>[];

    for (final t in traspasos) {
      final uuid = t['local_uuid'] as String;

      final lineas = await db.query(
        'lineas_local',
        where: 'traspaso_uuid = ?',
        whereArgs: [uuid],
      );

      final totalLibros = lineas.fold<int>(
          0, (sum, l) => sum + ((l['cantidad'] as int?) ?? 0));

      Map<String, dynamic> origen  = {};
      Map<String, dynamic> destino = {};
      try {
        origen  = Map<String, dynamic>.from(
            jsonDecode(t['origen_json']  as String? ?? '{}'));
        destino = Map<String, dynamic>.from(
            jsonDecode(t['destino_json'] as String? ?? '{}'));
      } catch (_) {}

      resultado.add({
        'id'             : t['id'],
        'local_uuid'     : uuid,
        'estado'         : t['estado'] ?? 'pendiente',
        'fecha_creacion' : t['fecha_creacion'] ?? '',
        'fecha_sync'     : t['fecha_sync'],
        'num_refs'       : lineas.length,
        'total_libros'   : totalLibros,
        'origen_almacen' : origen['Codigo_Almacen'] ?? '—',
        'origen_stand'   : origen['Stand']?.toString() ?? '—',
        'destino_almacen': destino['Codigo_Almacen'] ?? '—',
        'destino_stand'  : destino['Stand']?.toString() ?? '—',
        'lineas'         : lineas,
      });
    }

    return resultado;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LÍNEAS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> insertarLinea(Map<String, dynamic> linea) async {
    final db = await database;
    await db.insert(
      'lineas_local',
      linea,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<List<Map<String, dynamic>>> getLineasDeTraspaso(
      String traspasoUuid) async {
    final db = await database;
    return await db.query('lineas_local',
        where: 'traspaso_uuid = ?', whereArgs: [traspasoUuid]);
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
        'intentos'     : 0,
        'creado'       : DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> incrementarIntento(String uuid, String error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE sync_queue SET intentos = intentos + 1, ultimo_error = ? '
      'WHERE traspaso_uuid = ?',
      [error, uuid],
    );
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

  // ════════════════════════════════════════════════════════════════════════════
  // SYNC — SUBIDA A NUBE
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getTraspasosPendientesConLineas() async {
    final db = await database;

    final traspasos = await db.rawQuery('''
      SELECT
        t.*,
        COALESCE(q.intentos,     0)    AS q_intentos,
        COALESCE(q.ultimo_error, '')   AS q_ultimo_error
      FROM traspasos_local t
      LEFT JOIN sync_queue q ON q.traspaso_uuid = t.local_uuid
      WHERE t.estado = 'pendiente'
      ORDER BY q.intentos ASC, t.fecha_creacion ASC
    ''');

    final resultado = <Map<String, dynamic>>[];

    for (final t in traspasos) {
      final uuid   = t['local_uuid'] as String;
      final lineas = await db.query(
        'lineas_local',
        where: 'traspaso_uuid = ?',
        whereArgs: [uuid],
      );

      Map<String, dynamic> origen  = {};
      Map<String, dynamic> destino = {};
      try {
        origen  = Map<String, dynamic>.from(
            jsonDecode(t['origen_json']  as String? ?? '{}'));
        destino = Map<String, dynamic>.from(
            jsonDecode(t['destino_json'] as String? ?? '{}'));
      } catch (_) {}

      resultado.add({
        ...t,
        'origen_decoded' : origen,
        'destino_decoded': destino,
        'lineas'         : lineas,
        'intentos'       : t['q_intentos'],
        'ultimo_error'   : t['q_ultimo_error'],
      });
    }

    return resultado;
  }

  Future<void> marcarTraspasosSincronizados(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db    = await database;
    final batch = db.batch();
    final ahora = DateTime.now().toIso8601String();

    for (final uuid in uuids) {
      batch.update(
        'traspasos_local',
        {'estado': 'sincronizado', 'fecha_sync': ahora},
        where: 'local_uuid = ?',
        whereArgs: [uuid],
      );
      batch.delete(
        'sync_queue',
        where: 'traspaso_uuid = ?',
        whereArgs: [uuid],
      );
    }

    await batch.commit(noResult: true);
  }

  Future<int> contarPendientes() async {
    final db   = await database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as total FROM traspasos_local WHERE estado = 'pendiente'",
    );
    return (rows.first['total'] as int?) ?? 0;
  }
}