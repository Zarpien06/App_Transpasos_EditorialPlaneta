// lib/services/backup_service.dart
// ─────────────────────────────────────────────────────────────
// Genera 3 archivos de backup:
//   📄 .sql  — DROP/CREATE TABLE + INSERT sobre hmoval
//              Compatible con phpMyAdmin · MySQL 5.7+ · MariaDB 10.3+
//              Mismo mapeo que usa subirDatos() en api_service.dart
//   📊 .xlsx — Excel con hojas detalladas:
//              · 📋 Resumen  (incluye totales de productos, sin hoja detalle)
//              · 📦 Traspasos  (datos reales de traspasos_local + lineas_local)
//              · 👥 Usuarios_Transpasos (usuarios_transpasos_local)
//              · resto de tablas SQLite
//   🗜  .zip  — comprimido con los 2 archivos anteriores
//
// CAMBIOS v5:
//   - SQL     → mnube=1 en todos los INSERT (antes era 0)
//   - SQL     → Comentario corregido: '0 = pendiente nube, 1 = subido'
//   - Los registros quedan en 1 directamente al importar en phpMyAdmin
//
// CAMBIOS v4:
//   - SQL     → DROP TABLE IF EXISTS + CREATE TABLE (elimina ALTER TABLE
//               ADD COLUMN IF NOT EXISTS que no existe en MySQL 5.7)
//   - SQL     → Compatible 100% con MySQL 5.7, MySQL 8 y MariaDB 10.3+
//               sin necesidad de DELIMITER ni PROCEDURE
//
// CAMBIOS v3:
//   - SQL     → ALTER TABLE ADD COLUMN IF NOT EXISTS mnube DEFAULT 0
//   - SQL     → UPDATE hmoval SET mnube=1 WHERE mnube IS NULL (filas viejas)
//   - mnube   → 0 al insertar = pendiente de confirmar; el PHP lo pone en 1
//
// CAMBIOS v2:
//   - mnube   → int NOT NULL DEFAULT 0: ya no falla el INSERT
//   - Excel   → sin hoja 📚 Productos ni 🔑 Admin; Resumen muestra solo totales
//   - SQL     → incluye CREATE TABLE IF NOT EXISTS hmoval antes del INSERT
//
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:excel/excel.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database_service.dart';
import '../core/device_service.dart';
import '../core/trusted_clock_service.dart';

// ════════════════════════════════════════════════════════════
// DDL — tabla `hmoval`
// ════════════════════════════════════════════════════════════
//
// Estrategia DROP + CREATE (compatible MySQL 5.7+):
//
//  1. DROP TABLE IF EXISTS   — elimina la tabla si ya existe
//  2. CREATE TABLE           — crea con la estructura correcta (incluye mnube)
//  3. INSERT INTO            — mete los movimientos de ESTE backup (mnube=1)
//                              Los registros quedan listos desde la importación.
//
// Con esto: SELECT * FROM hmoval WHERE mnube=0  → pendientes de subir a la nube
//           SELECT * FROM hmoval WHERE mnube=1  → ya subidos y confirmados
//
// NOTA: Se abandona ALTER TABLE ADD COLUMN IF NOT EXISTS porque esa sintaxis
//       NO existe en MySQL 5.7 (solo en MySQL 8.0.3+ y MariaDB 10.3+).
//       DROP + CREATE es idempotente, más simple y compatible con todo.
// ════════════════════════════════════════════════════════════
const _ddlHmoval = """
-- ════════════════════════════════════════════════════════════
-- PASO 1 · Eliminar tabla si ya existe
--          Compatible con MySQL 5.7+, MySQL 8, MariaDB 10.3+
-- ════════════════════════════════════════════════════════════
DROP TABLE IF EXISTS `hmoval`;

-- ════════════════════════════════════════════════════════════
-- PASO 2 · Crear tabla con estructura completa (incluye mnube)
-- ════════════════════════════════════════════════════════════
CREATE TABLE `hmoval` (
  `manuca` varchar(4)   NOT NULL COMMENT 'Numero de Caja',
  `macdhr` varchar(2)   NOT NULL COMMENT 'Holding Origen',
  `macdso` varchar(2)   NOT NULL COMMENT 'Subholding Origen',
  `macdeo` varchar(2)   NOT NULL COMMENT 'Empresa Origen',
  `macdao` varchar(4)   NOT NULL COMMENT 'Actividad Origen',
  `macdhd` varchar(2)   NOT NULL COMMENT 'Holding Destino',
  `macdsd` varchar(2)   NOT NULL COMMENT 'Subholding Destino',
  `macded` varchar(2)   NOT NULL COMMENT 'Empresa Destino',
  `macdad` varchar(4)   NOT NULL COMMENT 'Actividad Destino',
  `manuma` int          NOT NULL COMMENT 'Numero de Movimiento',
  `manuml` int          NOT NULL COMMENT 'Numero de Linea',
  `macdco` varchar(3)   NOT NULL COMMENT 'Codigo Concepto',
  `matran` varchar(2)   NOT NULL COMMENT 'Transaccion Analitica',
  `matrge` varchar(2)   NOT NULL COMMENT 'Transaccion Generica',
  `mafemo` int          NOT NULL COMMENT 'Fecha Movimiento (yyyyMMdd)',
  `mafman` int          NOT NULL COMMENT 'Anio',
  `mafmme` int          NOT NULL COMMENT 'Mes',
  `mafmdi` int          NOT NULL COMMENT 'Dia',
  `mahogr` int          NOT NULL COMMENT 'Hora',
  `macdlo` varchar(8)   NOT NULL COMMENT 'Almacen Origen',
  `macdld` varchar(8)   NOT NULL COMMENT 'Almacen Destino',
  `macdpt` varchar(15)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
                        NOT NULL COMMENT 'Codigo Producto',
  `macant` int          NOT NULL COMMENT 'Cantidad',
  `mnube`  int          NOT NULL DEFAULT 1 COMMENT '0 = pendiente nube, 1 = subido'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

""";

// ════════════════════════════════════════════════════════════
// CABECERAS LEGIBLES — hoja de traspasos (datos reales SQLite)
// ════════════════════════════════════════════════════════════

const _traspasoHeaders = <String, String>{
  't_id'            : 'ID Local',
  't_local_uuid'    : 'UUID',
  't_device_id'     : 'Dispositivo',
  't_num_movimiento': 'N° Movimiento',
  't_fecha_creacion': 'Fecha Creación',
  't_fecha_sync'    : 'Fecha Sync',
  't_estado'        : 'Estado',
  'o_Codigo_Almacen': 'Almacén Origen',
  'o_Stand'         : 'Stand Origen',
  'o_Empresa'       : 'Empresa Origen',
  'o_Actividad'     : 'Actividad Origen',
  'o_Nombre'        : 'Nombre Origen',
  'd_Codigo_Almacen': 'Almacén Destino',
  'd_Stand'         : 'Stand Destino',
  'd_Empresa'       : 'Empresa Destino',
  'd_Actividad'     : 'Actividad Destino',
  'd_Nombre'        : 'Nombre Destino',
  'l_id'            : 'ID Línea',
  'l_codigo'        : 'Código / EAN',
  'l_descripcion'   : 'Descripción Libro',
  'l_cantidad'      : 'Cantidad',
  'h_manuca'        : 'hmoval: manuca',
  'h_macdlo'        : 'hmoval: macdlo',
  'h_macdld'        : 'hmoval: macdld',
  'h_macdpt'        : 'hmoval: macdpt',
  'h_macant'        : 'hmoval: macant',
  'h_mafemo'        : 'hmoval: mafemo',
  'h_mahogr'        : 'hmoval: mahogr',
};

const _traspasoOrden = <String>[
  't_id', 't_local_uuid', 't_device_id', 't_num_movimiento',
  't_fecha_creacion', 't_fecha_sync', 't_estado',
  'o_Codigo_Almacen', 'o_Stand', 'o_Empresa', 'o_Actividad', 'o_Nombre',
  'd_Codigo_Almacen', 'd_Stand', 'd_Empresa', 'd_Actividad', 'd_Nombre',
  'l_id', 'l_codigo', 'l_descripcion', 'l_cantidad',
  'h_manuca', 'h_macdlo', 'h_macdld', 'h_macdpt', 'h_macant',
  'h_mafemo', 'h_mahogr',
];

// ════════════════════════════════════════════════════════════
// HELPER: construir filas aplanadas (1 fila por línea)
// ════════════════════════════════════════════════════════════

List<Map<String, String>> _aplanarTraspasos(
  List<Map<String, dynamic>> traspasos,
  String deviceId,
) {
  final filas = <Map<String, String>>[];

  final horaConfiable = TrustedClockService().ahora();
  final mahogr        = horaConfiable.horaLocal.hour.toString();

  for (final t in traspasos) {
    Map<String, dynamic> origen  = {};
    Map<String, dynamic> destino = {};
    try {
      origen  = Map<String, dynamic>.from(
          jsonDecode(t['origen_json']  as String? ?? '{}'));
      destino = Map<String, dynamic>.from(
          jsonDecode(t['destino_json'] as String? ?? '{}'));
    } catch (_) {}

    if (t.containsKey('origen_decoded') && t['origen_decoded'] is Map) {
      origen = Map<String, dynamic>.from(t['origen_decoded'] as Map);
    }
    if (t.containsKey('destino_decoded') && t['destino_decoded'] is Map) {
      destino = Map<String, dynamic>.from(t['destino_decoded'] as Map);
    }

    final lineas   = (t['lineas'] as List?) ?? [];
    final numMov   = t['num_movimiento']?.toString() ?? '';
    final fechaRaw = (t['fecha_creacion'] as String? ?? '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    final manuca   = '${deviceId}_$numMov';
    final macdlo   = origen['Codigo_Almacen']?.toString()  ?? '';
    final macdld   = destino['Codigo_Almacen']?.toString() ?? '';
    final mafemo   = fechaRaw.length >= 8 ? fechaRaw.substring(0, 8) : fechaRaw;

    final lineasIter = lineas.isEmpty
        ? [<String, dynamic>{}]
        : lineas.cast<Map<String, dynamic>>();

    for (var j = 0; j < lineasIter.length; j++) {
      final linea = lineasIter[j];
      filas.add({
        't_id'            : t['id']?.toString()              ?? '',
        't_local_uuid'    : t['local_uuid']?.toString()      ?? '',
        't_device_id'     : t['device_id']?.toString()       ?? deviceId,
        't_num_movimiento': numMov,
        't_fecha_creacion': t['fecha_creacion']?.toString()  ?? '',
        't_fecha_sync'    : t['fecha_sync']?.toString()      ?? '',
        't_estado'        : t['estado']?.toString()          ?? '',
        'o_Codigo_Almacen': macdlo,
        'o_Stand'         : origen['Stand']?.toString()      ?? '',
        'o_Empresa'       : origen['Empresa']?.toString()    ?? '',
        'o_Actividad'     : origen['Actividad']?.toString()  ?? '',
        'o_Nombre'        : origen['Nombre_UsuarioT']?.toString() ?? '',
        'd_Codigo_Almacen': macdld,
        'd_Stand'         : destino['Stand']?.toString()     ?? '',
        'd_Empresa'       : destino['Empresa']?.toString()   ?? '',
        'd_Actividad'     : destino['Actividad']?.toString() ?? '',
        'd_Nombre'        : destino['Nombre_UsuarioT']?.toString() ?? '',
        'l_id'            : linea['id']?.toString()          ?? '',
        'l_codigo'        : linea['codigo']?.toString()      ?? '',
        'l_descripcion'   : linea['descripcion']?.toString() ?? '',
        'l_cantidad'      : linea['cantidad']?.toString()    ?? '0',
        'h_manuca'        : manuca,
        'h_macdlo'        : macdlo,
        'h_macdld'        : macdld,
        'h_macdpt'        : linea['codigo']?.toString()      ?? '',
        'h_macant'        : linea['cantidad']?.toString()    ?? '0',
        'h_mafemo'        : mafemo,
        'h_mahogr'        : mahogr,
      });
    }
  }

  return filas;
}

// ════════════════════════════════════════════════════════════
// BACKUP SERVICE
// ════════════════════════════════════════════════════════════

class BackupService {
  static const _destinatarios = [
    'jtorres@planeta.com.co',
    'oscarcruzsena2006@gmail.com',
    'ivancamilo.ordonez@planeta.com.co',
    'becario.sistemas01@planeta.com.co',
    'haroldesteban.gaona@planeta.com.co',
    'oscarmauricio.cruz@colaborador.planeta.com.co',
  ];

  static const _smtpHost = 'smtp.gmail.com';
  static const _smtpPort = 587;
  static const _smtpUser = 'oscarmauriciocruz908@gmail.com';
  static const _smtpPass = 'syft leaz zxly lxlb';

  // ── Paleta Excel ────────────────────────────────────────────
  static const _azulOscuro  = '0D1B4B';
  static const _azulMedio   = '1A3272';
  static const _azulPlaneta = '2563EB';
  static const _blanco      = 'FFFFFF';
  static const _grisClaro   = 'F5F7FA';
  static const _negro       = '111111';
  static const _verdeSync   = '16A34A';
  static const _amarillo    = 'D97706';
  static const _rojo        = 'DC2626';
  static const _morado      = '7C3AED';
  static const _grisTecnico = '6B7280';

  static bool modoOffice = false;

  // Tablas que tienen hoja dedicada en el Excel
  // NOTA: productos_local y admin_local ya NO tienen hoja propia,
  //       solo aparecen como totales en el Resumen.
  static const _tablasEspeciales = {
    'traspasos_local',
    'lineas_local',
    'productos_local',   // sin hoja detalle — solo total en Resumen
    'usuarios_transpasos_local',
    'admin_local',       // sin hoja detalle — solo total en Resumen
    'sync_queue',
    'config',
  };

  // ══════════════════════════════════════════════════════════
  // PUNTO DE ENTRADA PRINCIPAL
  // ══════════════════════════════════════════════════════════
  static Future<BackupResult> ejecutar({bool office = false}) async {
    modoOffice = office;
    try {
      if (!await _pedirPermiso()) {
        return BackupResult(
          ok: false,
          mensaje: '❌ Sin permiso de almacenamiento. Ve a Ajustes → Permisos.',
        );
      }

      final dbSvc    = DatabaseService();
      final db       = await dbSvc.database;
      final deviceId = await DeviceService().getDeviceId();

      final tablasCrudas = await _leerTablasCrudas(db);
      final traspasos    = await _leerTodosLosTraspasos(db);

      final fecha       = _fechaArchivo();
      final prefijo     = '${deviceId}_$fecha';
      final carpeta     = await _crearCarpetaBackup(prefijo);
      final nombreBase  = 'backup_traspasos_$prefijo';

      final sqlPath  = p.join(carpeta, '$nombreBase.sql');
      final xlsxPath = p.join(carpeta, '$nombreBase.xlsx');
      final zipPath  = p.join(carpeta, '$nombreBase.zip');

      await _generarArchivosEnIsolate(
        tablasCrudas : tablasCrudas,
        traspasos    : traspasos,
        sqlPath      : sqlPath,
        xlsxPath     : xlsxPath,
        zipPath      : zipPath,
        fecha        : prefijo,
        deviceId     : deviceId,
      );

      bool   emailOk  = false;
      String emailMsg = '';
      try {
        await _enviarEmail(
          zipFile     : File(zipPath),
          fecha       : prefijo,
          deviceId    : deviceId,
          tablasCrudas: tablasCrudas,
          traspasos   : traspasos,
        );
        emailOk  = true;
        emailMsg = '✉️ Correo enviado a ${_destinatarios.length} destinatarios.';
      } catch (e) {
        emailMsg = modoOffice
            ? '⚠️ Correo falló: $e'
            : '⚠️ Correo falló: $e\nSe abrirá el panel de compartir.';
      }

      if (!emailOk && !modoOffice) {
        await Share.shareXFiles(
          [XFile(zipPath)],
          subject: 'Backup Traspasos Planeta — $prefijo',
        );
      }

      final totalLineas = traspasos.fold<int>(
        0, (s, t) => s + ((t['lineas'] as List?)?.length ?? 0));

      return BackupResult(
        ok      : true,
        mensaje : '✅ Backup guardado en:\n$carpeta\n\n'
                  '📦 ${traspasos.length} traspasos · $totalLineas líneas\n\n'
                  '$emailMsg',
        sqlPath : sqlPath,
        xlsxPath: xlsxPath,
        zipPath : zipPath,
        carpeta : carpeta,
      );
    } catch (e) {
      return BackupResult(ok: false, mensaje: '❌ Error al generar backup: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // LECTURA DE DATOS
  // ══════════════════════════════════════════════════════════

  static Future<Map<String, List<Map<String, dynamic>>>> _leerTablasCrudas(
      Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' "
      "ORDER BY name",
    );

    const orden = [
      'traspasos_local', 'lineas_local', 'productos_local',
      'usuarios_transpasos_local', 'admin_local', 'sync_queue', 'config',
    ];

    final out = <String, List<Map<String, dynamic>>>{};
    for (final n in orden) {
      try {
        out[n] = (await db.query(n))
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
      } catch (_) {
        out[n] = [];
      }
    }
    for (final r in rows) {
      final n = r['name'] as String;
      if (!out.containsKey(n)) {
        out[n] = (await db.query(n))
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
      }
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _leerTodosLosTraspasos(
      Database db) async {
    final traspasos = await db.query(
      'traspasos_local',
      orderBy: 'id DESC',
    );

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
        ...Map<String, dynamic>.from(t),
        'origen_decoded' : origen,
        'destino_decoded': destino,
        'lineas'         : lineas.map((l) => Map<String, dynamic>.from(l)).toList(),
      });
    }

    return resultado;
  }

  // ══════════════════════════════════════════════════════════
  // ISOLATE
  // ══════════════════════════════════════════════════════════
  static Future<void> _generarArchivosEnIsolate({
    required Map<String, List<Map<String, dynamic>>> tablasCrudas,
    required List<Map<String, dynamic>> traspasos,
    required String sqlPath,
    required String xlsxPath,
    required String zipPath,
    required String fecha,
    required String deviceId,
  }) async {
    final args = _BackupArgs(
      tablasCrudas: tablasCrudas,
      traspasos   : traspasos,
      sqlPath     : sqlPath,
      xlsxPath    : xlsxPath,
      zipPath     : zipPath,
      fecha       : fecha,
      deviceId    : deviceId,
    );
    final receivePort = ReceivePort();
    await Isolate.spawn(_isolateEntry, [receivePort.sendPort, args]);
    final result = await receivePort.first;
    if (result is Exception) throw result;
  }

  static void _isolateEntry(List<dynamic> message) async {
    final SendPort    sendPort = message[0] as SendPort;
    final _BackupArgs args     = message[1] as _BackupArgs;
    try {
      await _generarSQL(
          args.traspasos, args.sqlPath, args.fecha, args.deviceId);
      await _generarExcel(
          args.tablasCrudas, args.traspasos,
          args.xlsxPath, args.fecha, args.deviceId);
      await _generarZip([args.sqlPath, args.xlsxPath], args.zipPath);
      sendPort.send('ok');
    } catch (e) {
      sendPort.send(Exception(e.toString()));
    }
  }

  // ══════════════════════════════════════════════════════════
  // CARPETA
  // ══════════════════════════════════════════════════════════
  static Future<String> _crearCarpetaBackup(String prefijo) async {
    Future<String> intentar(String base) async {
      final dir  = Directory(p.join(base, prefijo));
      await dir.create(recursive: true);
      final test = File(p.join(dir.path, '.test'));
      await test.writeAsString('ok');
      await test.delete();
      return dir.path;
    }
    try { return await intentar('/storage/emulated/0/Traspasos'); } catch (_) {}
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null && dirs.isNotEmpty) {
        return await intentar(p.join(dirs.first.path, 'Traspasos'));
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return await intentar(p.join(docs.path, 'Traspasos'));
  }

  // ══════════════════════════════════════════════════════════
  // PERMISO
  // ══════════════════════════════════════════════════════════
  static Future<bool> _pedirPermiso() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _getSdkVersion();
    if (sdk >= 30) {
      if ((await Permission.manageExternalStorage.request()).isGranted) return true;
    }
    return (await Permission.storage.request()).isGranted;
  }

  static Future<int> _getSdkVersion() async {
    try {
      final r = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(r.stdout.toString().trim()) ?? 29;
    } catch (_) { return 29; }
  }

  // ══════════════════════════════════════════════════════════
  // GENERAR .SQL
  // ══════════════════════════════════════════════════════════
  // Flujo del archivo generado (100% compatible con phpMyAdmin):
  //   Paso 1 — DROP TABLE IF EXISTS hmoval
  //   Paso 2 — CREATE TABLE hmoval (con mnube incluido)
  //   Paso 3 — INSERT INTO hmoval … (todos con mnube=1)
  //
  // Sin PROCEDURE ni DELIMITER ni ALTER TABLE IF NOT EXISTS
  // → funciona directo en phpMyAdmin Import con MySQL 5.7+.
  // mnube=1 = subido y confirmado desde la importación
  // ══════════════════════════════════════════════════════════
  static Future<void> _generarSQL(
    List<Map<String, dynamic>> traspasos,
    String ruta,
    String fecha,
    String deviceId,
  ) async {
    String escape(dynamic v) {
      if (v == null)               return 'NULL';
      if (v is int || v is double) return v.toString();
      final s = v.toString()
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'");
      return "'$s'";
    }

    final horaConfiable = TrustedClockService().ahora();
    final mahogr        = horaConfiable.horaLocal.hour.toString();

    final movimientos = <Map<String, dynamic>>[];

    for (final t in traspasos) {
      Map<String, dynamic> origen  = {};
      Map<String, dynamic> destino = {};
      try {
        origen  = t.containsKey('origen_decoded')
            ? Map<String, dynamic>.from(t['origen_decoded'] as Map)
            : Map<String, dynamic>.from(
                jsonDecode(t['origen_json'] as String? ?? '{}'));
        destino = t.containsKey('destino_decoded')
            ? Map<String, dynamic>.from(t['destino_decoded'] as Map)
            : Map<String, dynamic>.from(
                jsonDecode(t['destino_json'] as String? ?? '{}'));
      } catch (_) {}

      final lineas = (t['lineas'] as List?) ?? [];
      final numMov = t['num_movimiento']?.toString() ??
                     DateTime.now().millisecondsSinceEpoch.toString();
      final base   = '${deviceId}_$numMov';

      final fechaRaw = (t['fecha_creacion'] as String? ?? '')
          .replaceAll(RegExp(r'[^0-9]'), '');

      for (var j = 0; j < lineas.length; j++) {
        final linea = lineas[j] as Map<String, dynamic>;
        movimientos.add({
          'manuca': base,
          'manuml': (j + 1),
          'manuma': numMov,
          'macdhr': '1',
          'macdso': '1',
          'macdeo': 'PL',
          'macdao': '23',
          'macdhd': '1',
          'macdsd': '1',
          'macded': 'PL',
          'macdad': '23',
          'macdco': 'TRA',
          'matran': 'TF',
          'matrge': 'ET',
          'mafemo': fechaRaw.length >= 8 ? fechaRaw.substring(0, 8) : '',
          'mafman': fechaRaw.length >= 4 ? fechaRaw.substring(0, 4) : '',
          'mafmme': fechaRaw.length >= 6 ? fechaRaw.substring(4, 6) : '0',
          'mafmdi': fechaRaw.length >= 8 ? fechaRaw.substring(6, 8) : '0',
          'mahogr': mahogr,
          'macdlo': origen['Codigo_Almacen']?.toString()  ?? '',
          'macdld': destino['Codigo_Almacen']?.toString() ?? '',
          'macdpt': linea['codigo']?.toString()           ?? '',
          'macant': (linea['cantidad'] as num?)?.toInt()  ?? 1,
          'mnube' : 1, // ← CAMBIO v5: 1 = subido desde la importación
        });
      }
    }

    final cols   = movimientos.isNotEmpty ? movimientos.first.keys.toList() : <String>[];
    final colStr = cols.map((c) => '`$c`').join(', ');
    final buf    = StringBuffer();

    buf.writeln('-- ============================================================');
    buf.writeln('-- BACKUP · EDITORIAL PLANETA COLOMBIA · hmoval');
    buf.writeln('-- Dispositivo         : $deviceId');
    buf.writeln('-- Fecha de generación : $fecha');
    buf.writeln('-- Hora (confiable)    : ${horaConfiable.etiquetaFuente}');
    buf.writeln('-- Traspasos           : ${traspasos.length}');
    buf.writeln('-- Movimientos hmoval  : ${movimientos.length}');
    buf.writeln('--');
    buf.writeln('-- Paso 1: DROP TABLE IF EXISTS — elimina tabla previa.');
    buf.writeln('-- Paso 2: CREATE TABLE         — estructura correcta con mnube.');
    buf.writeln('-- Paso 3: INSERT INTO          — movimientos con mnube=1.');
    buf.writeln('-- Consulta util: SELECT * FROM hmoval WHERE mnube=0 (pendientes nube).');
    buf.writeln('--');
    buf.writeln('-- Compatible con: phpMyAdmin · MySQL 5.7+ · MySQL 8 · MariaDB 10.3+');
    buf.writeln('-- ============================================================');
    buf.writeln();
    buf.writeln('SET FOREIGN_KEY_CHECKS = 0;');
    buf.writeln('SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";');
    buf.writeln('SET NAMES utf8mb4;');
    buf.writeln('SET time_zone = "+00:00";');
    buf.writeln();

    // ── Pasos 1-2: DROP + CREATE ──────────────────────────────
    buf.writeln(_ddlHmoval);

    // ── Paso 3: INSERT INTO ───────────────────────────────────
    if (movimientos.isEmpty) {
      buf.writeln('-- Sin movimientos para exportar.');
    } else {
      buf.writeln('-- ── hmoval (${movimientos.length} filas) — mnube=1 en todos ──');
      buf.writeln();

      const bloque = 500;
      for (int i = 0; i < movimientos.length; i += bloque) {
        final lote = movimientos.sublist(
            i, (i + bloque).clamp(0, movimientos.length));
        buf.writeln('INSERT INTO `hmoval` ($colStr) VALUES');
        final lineas = lote.map((fila) {
          final vals = cols.map((col) => escape(fila[col])).join(', ');
          return '  ($vals)';
        }).join(',\n');
        buf.writeln('$lineas;');
        buf.writeln();
      }
    }

    buf.writeln('SET FOREIGN_KEY_CHECKS = 1;');
    buf.writeln('-- ============================================================');
    buf.writeln('-- Fin del backup · Editorial Planeta · $deviceId · $fecha');
    buf.writeln('-- ============================================================');

    await File(ruta).writeAsString(buf.toString(), flush: true);
  }

  // ══════════════════════════════════════════════════════════
  // GENERAR .XLSX
  // Hojas: 📋 Resumen · 📦 Traspasos · 👥 Usuarios · ⏳ Cola Sync · ⚙️ Config
  // Eliminadas: 📚 Productos (solo total en Resumen) · 🔑 Admin (ídem)
  // ══════════════════════════════════════════════════════════
  static Future<void> _generarExcel(
    Map<String, List<Map<String, dynamic>>> tablasCrudas,
    List<Map<String, dynamic>> traspasos,
    String ruta,
    String fecha,
    String deviceId,
  ) async {
    final excel = Excel.createExcel();

    final totalReg = tablasCrudas.values.fold(0, (s, f) => s + f.length);
    final totalLineas = traspasos.fold<int>(
        0, (s, t) => s + ((t['lineas'] as List?)?.length ?? 0));
    final totalLibros = traspasos.fold<int>(0, (s, t) {
      final lineas = (t['lineas'] as List?) ?? [];
      return s + lineas.fold<int>(
          0, (sl, l) => sl + ((l['cantidad'] as int?) ?? 0));
    });
    final sincronizados = traspasos.where((t) => t['estado'] == 'sincronizado').length;
    final pendientes    = traspasos.where((t) => t['estado'] == 'pendiente').length;
    final enProceso     = traspasos.where((t) => t['estado'] == 'en_proceso').length;

    _generarHojaResumen(
      excel,
      tablasCrudas  : tablasCrudas,
      traspasos     : traspasos,
      totalReg      : totalReg,
      totalLineas   : totalLineas,
      totalLibros   : totalLibros,
      sincronizados : sincronizados,
      pendientes    : pendientes,
      enProceso     : enProceso,
      deviceId      : deviceId,
      fecha         : fecha,
    );

    _generarHojaTraspasos(excel, traspasos, deviceId, fecha);

    _generarHojaUsuariosT(
        excel, tablasCrudas['usuarios_transpasos_local'] ?? [], deviceId, fecha);

    _generarHojaGenerica(
      excel, 'sync_queue', '⏳ Cola Sync',
      tablasCrudas['sync_queue'] ?? [], deviceId, fecha,
    );

    _generarHojaGenerica(
      excel, 'config', '⚙️ Config',
      tablasCrudas['config'] ?? [], deviceId, fecha,
    );

    // Tablas extra (no especiales) siguen teniendo su propia hoja
    for (final entry in tablasCrudas.entries) {
      if (_tablasEspeciales.contains(entry.key)) continue;
      _generarHojaGenerica(
          excel, entry.key, entry.key, entry.value, deviceId, fecha);
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes != null) await File(ruta).writeAsBytes(bytes, flush: true);
  }

  // ══════════════════════════════════════════════════════════
  // HOJA 1: RESUMEN
  // ══════════════════════════════════════════════════════════
  static void _generarHojaResumen(
    Excel excel, {
    required Map<String, List<Map<String, dynamic>>> tablasCrudas,
    required List<Map<String, dynamic>> traspasos,
    required int totalReg,
    required int totalLineas,
    required int totalLibros,
    required int sincronizados,
    required int pendientes,
    required int enProceso,
    required String deviceId,
    required String fecha,
  }) {
    final hoja = excel['📋 Resumen'];
    hoja.setColumnWidth(0, 36);
    hoja.setColumnWidth(1, 16);
    hoja.setColumnWidth(2, 20);
    hoja.setColumnWidth(3, 16);

    hoja.setRowHeight(0, 36);
    _cel(hoja, 0, 0,
        value: 'EDITORIAL PLANETA  ·  BACKUP DE TRASPASOS',
        bold: true, size: 14, fg: _blanco, bg: _azulOscuro, span: 4);

    hoja.setRowHeight(1, 24);
    _cel(hoja, 1, 0,
        value: 'Dispositivo: $deviceId  ·  Generado el $fecha',
        size: 10, fg: _blanco, bg: _azulMedio, span: 4);

    hoja.setRowHeight(2, 10);
    _cel(hoja, 2, 0, value: '', bg: _blanco, span: 4);

    // ── Tarjetas métricas ─────────────────────────────────────
    hoja.setRowHeight(3, 20);
    hoja.setRowHeight(4, 30);
    _tarjeta(hoja, 3, 0, 'TRASPASOS TOTALES', traspasos.length.toString());
    _tarjeta(hoja, 3, 1, 'LÍNEAS (LIBROS)',   totalLineas.toString());
    _tarjeta(hoja, 3, 2, 'LIBROS MOVIDOS',    totalLibros.toString());
    _tarjeta(hoja, 3, 3, 'DISPOSITIVO',       deviceId);

    hoja.setRowHeight(5, 20);
    hoja.setRowHeight(6, 30);
    _tarjeta(hoja, 5, 0, 'SINCRONIZADOS', sincronizados.toString());
    _tarjeta(hoja, 5, 1, 'PENDIENTES',    pendientes.toString());
    _tarjeta(hoja, 5, 2, 'EN PROCESO',    enProceso.toString());
    final totalProductos = (tablasCrudas['productos_local'] ?? []).length;
    _tarjeta(hoja, 5, 3, 'PRODUCTOS EN CATÁLOGO', totalProductos.toString());

    hoja.setRowHeight(7, 10);
    _cel(hoja, 7, 0, value: '', bg: _blanco, span: 4);

    // ── Estado de traspasos ───────────────────────────────────
    hoja.setRowHeight(8, 20);
    _cel(hoja, 8, 0,
        value: 'ESTADO DE TRASPASOS',
        bold: true, fg: _blanco, bg: _azulOscuro, span: 4);

    hoja.setRowHeight(9, 22);
    _cel(hoja, 9, 0, value: 'Estado',        bold: true, fg: _blanco, bg: _azulMedio);
    _cel(hoja, 9, 1, value: 'Cantidad',       bold: true, fg: _blanco, bg: _azulMedio);
    _cel(hoja, 9, 2, value: 'Líneas',         bold: true, fg: _blanco, bg: _azulMedio);
    _cel(hoja, 9, 3, value: 'Libros movidos', bold: true, fg: _blanco, bg: _azulMedio);

    final grupos = <String, Map<String, int>>{};
    for (final t in traspasos) {
      final estado = t['estado']?.toString() ?? 'desconocido';
      final lineas = (t['lineas'] as List?) ?? [];
      final libros = lineas.fold<int>(
          0, (s, l) => s + ((l['cantidad'] as int?) ?? 0));
      grupos[estado] ??= {'count': 0, 'lineas': 0, 'libros': 0};
      grupos[estado]!['count']  = (grupos[estado]!['count']  ?? 0) + 1;
      grupos[estado]!['lineas'] = (grupos[estado]!['lineas'] ?? 0) + lineas.length;
      grupos[estado]!['libros'] = (grupos[estado]!['libros'] ?? 0) + libros;
    }

    int f = 10;
    for (final entry in grupos.entries) {
      hoja.setRowHeight(f, 22);
      final bg  = (f % 2 == 0) ? _grisClaro : _blanco;
      String fg = _negro;
      if (entry.key == 'sincronizado') fg = _verdeSync;
      if (entry.key == 'pendiente')    fg = _amarillo;
      if (entry.key == 'en_proceso')   fg = _azulPlaneta;

      _cel(hoja, f, 0, value: entry.key,
          bold: true, fg: fg, bg: bg);
      _cel(hoja, f, 1,
          value: (entry.value['count']  ?? 0).toString(),
          fg: _azulPlaneta, bold: true, bg: bg);
      _cel(hoja, f, 2,
          value: (entry.value['lineas'] ?? 0).toString(),
          fg: _negro, bg: bg);
      _cel(hoja, f, 3,
          value: (entry.value['libros'] ?? 0).toString(),
          fg: _negro, bg: bg);
      f++;
    }

    hoja.setRowHeight(f, 26);
    _cel(hoja, f, 0, value: 'TOTAL',
        bold: true, fg: _blanco, bg: _azulOscuro);
    _cel(hoja, f, 1, value: traspasos.length.toString(),
        bold: true, fg: _blanco, bg: _azulOscuro);
    _cel(hoja, f, 2, value: totalLineas.toString(),
        bold: true, fg: _blanco, bg: _azulOscuro);
    _cel(hoja, f, 3, value: totalLibros.toString(),
        bold: true, fg: _blanco, bg: _azulOscuro);
    f++;

    // ── Tabla de tablas SQLite ────────────────────────────────
    f++;
    hoja.setRowHeight(f, 20);
    _cel(hoja, f, 0,
        value: 'TABLAS SQLite EN EL DISPOSITIVO',
        bold: true, fg: _blanco, bg: _azulOscuro, span: 4);
    f++;

    hoja.setRowHeight(f, 22);
    _cel(hoja, f, 0, value: 'Tabla',       bold: true, fg: _blanco, bg: _azulMedio);
    _cel(hoja, f, 1, value: 'Registros',   bold: true, fg: _blanco, bg: _azulMedio);
    _cel(hoja, f, 2, value: 'Hoja Excel',  bold: true, fg: _blanco, bg: _azulMedio);
    _cel(hoja, f, 3, value: '% del total', bold: true, fg: _blanco, bg: _azulMedio);
    f++;

    const sinHojaDetalle = {'productos_local', 'admin_local', 'lineas_local'};

    for (final entry in tablasCrudas.entries) {
      hoja.setRowHeight(f, 22);
      final bg       = (f % 2 == 0) ? _grisClaro : _blanco;
      final pct      = totalReg > 0
          ? '${(entry.value.length / totalReg * 100).toStringAsFixed(1)} %'
          : '—';
      final tieneHoja = !sinHojaDetalle.contains(entry.key);
      final hojaLabel = tieneHoja ? '✓ Ver hoja' : '— solo total';
      final hojaFg    = tieneHoja ? _verdeSync   : _grisTecnico;

      _cel(hoja, f, 0, value: entry.key,
          fg: _negro, bg: bg);
      _cel(hoja, f, 1, value: entry.value.length.toString(),
          fg: _azulPlaneta, bold: true, bg: bg);
      _cel(hoja, f, 2, value: hojaLabel,
          fg: hojaFg, bg: bg);
      _cel(hoja, f, 3, value: pct,
          fg: _negro, bg: bg);
      f++;
    }

    hoja.setRowHeight(f, 26);
    _cel(hoja, f, 0, value: 'TOTAL',
        bold: true, fg: _blanco, bg: _azulOscuro);
    _cel(hoja, f, 1, value: totalReg.toString(),
        bold: true, fg: _blanco, bg: _azulOscuro);
    _cel(hoja, f, 2, value: '${tablasCrudas.length} tablas',
        fg: _blanco, bg: _azulOscuro);
    _cel(hoja, f, 3, value: '100 %',
        bold: true, fg: _blanco, bg: _azulOscuro);
  }

  // ══════════════════════════════════════════════════════════
  // HOJA 2: TRASPASOS
  // ══════════════════════════════════════════════════════════
  static void _generarHojaTraspasos(
    Excel excel,
    List<Map<String, dynamic>> traspasos,
    String deviceId,
    String fecha,
  ) {
    final hoja  = excel['📦 Traspasos'];
    final filas = _aplanarTraspasos(traspasos, deviceId);

    final anchos = <String, double>{
      't_id': 10, 't_local_uuid': 32, 't_device_id': 14,
      't_num_movimiento': 16, 't_fecha_creacion': 22, 't_fecha_sync': 22,
      't_estado': 16, 'o_Codigo_Almacen': 18, 'o_Stand': 12,
      'o_Empresa': 14, 'o_Actividad': 14, 'o_Nombre': 22,
      'd_Codigo_Almacen': 18, 'd_Stand': 12, 'd_Empresa': 14,
      'd_Actividad': 14, 'd_Nombre': 22, 'l_id': 10, 'l_codigo': 18,
      'l_descripcion': 40, 'l_cantidad': 12, 'h_manuca': 24,
      'h_macdlo': 16, 'h_macdld': 16, 'h_macdpt': 18, 'h_macant': 12,
      'h_mafemo': 14, 'h_mahogr': 12,
    };

    for (int c = 0; c < _traspasoOrden.length; c++) {
      hoja.setColumnWidth(c, anchos[_traspasoOrden[c]] ?? 16.0);
    }

    final totalLineas = filas.length;
    final totalLibros = filas.fold<int>(
        0, (s, f) => s + (int.tryParse(f['l_cantidad'] ?? '0') ?? 0));

    hoja.setRowHeight(0, 34);
    _cel(hoja, 0, 0,
        value: '📦 TRASPASOS · traspasos_local + lineas_local  [$deviceId]  —  '
               '${traspasos.length} traspasos · $totalLineas líneas · $totalLibros libros',
        bold: true, size: 11, fg: _blanco, bg: _azulOscuro,
        span: _traspasoOrden.length);

    hoja.setRowHeight(1, 16);
    _cel(hoja, 1, 0,  value: 'TRASPASO LOCAL', fg: _blanco, bg: _azulMedio,  span: 7);
    _cel(hoja, 1, 7,  value: 'ORIGEN (JSON)',  fg: _blanco, bg: '1E40AF',    span: 5);
    _cel(hoja, 1, 12, value: 'DESTINO (JSON)', fg: _blanco, bg: '1D4ED8',    span: 5);
    _cel(hoja, 1, 17, value: 'LÍNEA / LIBRO',  fg: _blanco, bg: _azulMedio,  span: 4);
    _cel(hoja, 1, 21, value: 'MAPEO hmoval → subir_datos_nube_movil.php',
        fg: _blanco, bg: '1E3A5F', span: 7);

    hoja.setRowHeight(2, 26);
    for (int c = 0; c < _traspasoOrden.length; c++) {
      final campo  = _traspasoOrden[c];
      final cabeza = _traspasoHeaders[campo] ?? campo;
      _cel(hoja, 2, c,
          value: cabeza.toUpperCase(),
          bold: true, fg: _blanco, bg: _azulMedio);
    }

    hoja.setRowHeight(3, 16);
    for (int c = 0; c < _traspasoOrden.length; c++) {
      _cel(hoja, 3, c,
          value: _traspasoOrden[c],
          size: 8, fg: _grisTecnico, bg: _grisClaro);
    }

    if (filas.isEmpty) {
      hoja.setRowHeight(4, 28);
      _cel(hoja, 4, 0,
          value: 'Sin traspasos registrados en este dispositivo.',
          fg: _amarillo, bg: _blanco, span: _traspasoOrden.length);
      return;
    }

    for (int r = 0; r < filas.length; r++) {
      hoja.setRowHeight(r + 4, 20);
      final fila = filas[r];
      final bg   = (r % 2 == 0) ? _blanco : _grisClaro;

      for (int c = 0; c < _traspasoOrden.length; c++) {
        final campo = _traspasoOrden[c];
        final val   = fila[campo] ?? '';
        String fg   = _negro;

        switch (campo) {
          case 't_estado':
            if (val == 'sincronizado') fg = _verdeSync;
            if (val == 'pendiente')    fg = _amarillo;
            if (val == 'en_proceso')   fg = _azulPlaneta;
            if (val == 'error')        fg = _rojo;
            break;
          case 'l_codigo':
          case 'h_macdpt':
            fg = _morado;
            break;
          case 'l_cantidad':
          case 'h_macant':
            fg = _azulPlaneta;
            break;
          case 'h_manuca':
            fg = '374151';
            break;
          case 't_local_uuid':
            fg = _grisTecnico;
            break;
        }

        _cel(hoja, r + 4, c, value: val, fg: fg, bg: bg);
      }
    }

    final fTot = filas.length + 4;
    hoja.setRowHeight(fTot, 26);
    _cel(hoja, fTot, 0,
        value: 'TOTAL: ${traspasos.length} traspasos · $totalLineas líneas',
        bold: true, fg: _blanco, bg: _azulOscuro,
        span: _traspasoOrden.length - 1);
    _cel(hoja, fTot, _traspasoOrden.length - 1,
        value: '$totalLibros libros',
        bold: true, fg: _blanco, bg: _azulOscuro);
  }

  // ══════════════════════════════════════════════════════════
  // HOJA 3: USUARIOS TRASPASOS
  // ══════════════════════════════════════════════════════════
  static void _generarHojaUsuariosT(
    Excel excel,
    List<Map<String, dynamic>> filas,
    String deviceId,
    String fecha,
  ) {
    final hoja = excel['👥 Usuarios'];

    final cabeceras = {
      'Cod_UsuarioT'   : 'Cód. Usuario',
      'Nombre_UsuarioT': 'Nombre',
      'Clave_UsuarioT' : 'Clave',
      'Codigo_Almacen' : 'Cód. Almacén',
      'Stand'          : 'Stand',
      'Empresa'        : 'Empresa',
      'Actividad'      : 'Actividad',
      'Estado_UsuarioT': 'Estado',
    };
    final cols   = cabeceras.keys.toList();
    final anchos = [14.0, 28.0, 20.0, 18.0, 14.0, 22.0, 18.0, 12.0];

    for (int c = 0; c < cols.length; c++) {
      hoja.setColumnWidth(c, anchos[c]);
    }

    hoja.setRowHeight(0, 34);
    _cel(hoja, 0, 0,
        value: '👥 USUARIOS TRASPASOS (usuarios_transpasos_local)  [$deviceId]  —  '
               '${filas.length} usuarios',
        bold: true, size: 12, fg: _blanco, bg: _azulOscuro,
        span: cols.length);

    hoja.setRowHeight(1, 26);
    for (int c = 0; c < cols.length; c++) {
      _cel(hoja, 1, c,
          value: cabeceras[cols[c]]!.toUpperCase(),
          bold: true, fg: _blanco, bg: _azulMedio);
    }

    if (filas.isEmpty) {
      _cel(hoja, 2, 0,
          value: 'Sin usuarios de traspasos.',
          fg: _amarillo, bg: _blanco, span: cols.length);
      return;
    }

    for (int r = 0; r < filas.length; r++) {
      hoja.setRowHeight(r + 2, 20);
      final fila   = filas[r];
      final bg     = (r % 2 == 0) ? _blanco : _grisClaro;
      final activo = (fila['Estado_UsuarioT'] == 1 ||
                      fila['Estado_UsuarioT'] == '1');

      for (int c = 0; c < cols.length; c++) {
        final col = cols[c];
        final val = fila[col];
        String fg = _negro;

        if (col == 'Cod_UsuarioT')    fg = _azulPlaneta;
        if (col == 'Estado_UsuarioT') fg = activo ? _verdeSync : _rojo;

        _cel(hoja, r + 2, c,
            value: col == 'Estado_UsuarioT'
                ? (activo ? '✓ Activo' : '✗ Inactivo')
                : (val?.toString() ?? ''),
            fg: fg, bg: bg);
      }
    }

    hoja.setRowHeight(filas.length + 2, 26);
    _cel(hoja, filas.length + 2, 0,
        value: 'Total: ${filas.length} usuarios',
        bold: true, fg: _blanco, bg: _azulOscuro, span: cols.length);
  }

  // ══════════════════════════════════════════════════════════
  // HOJA GENÉRICA
  // ══════════════════════════════════════════════════════════
  static void _generarHojaGenerica(
    Excel excel,
    String nombreTabla,
    String nombreHoja,
    List<Map<String, dynamic>> filas,
    String deviceId,
    String fecha,
  ) {
    final safe = nombreHoja.length > 31
        ? nombreHoja.substring(0, 31)
        : nombreHoja;
    final hoja = excel[safe];

    if (filas.isEmpty) {
      hoja.setColumnWidth(0, 50);
      hoja.setRowHeight(0, 28);
      _cel(hoja, 0, 0,
          value: 'La tabla "$nombreTabla" no tiene registros.',
          fg: _amarillo, bg: _blanco);
      return;
    }

    final cols = filas.first.keys.toList();

    for (int c = 0; c < cols.length; c++) {
      final col = cols[c].toLowerCase();
      double w = 20;
      if (col.contains('desc') || col.contains('json') ||
          col.contains('mensaje') || col.contains('detalle') ||
          col.contains('error')) { w = 45; }
      else if (col.contains('fecha') || col.contains('timestamp') ||
               col.contains('creado')) { w = 26; }
      else if (col.contains('id') || col.contains('estado')) { w = 14; }
      else if (col.contains('nombre') || col.contains('referencia')) { w = 32; }
      hoja.setColumnWidth(c, w);
    }

    hoja.setRowHeight(0, 34);
    _cel(hoja, 0, 0,
        value: '$nombreTabla  [$deviceId]  —  ${filas.length} registros',
        bold: true, size: 12, fg: _blanco, bg: _azulOscuro,
        span: cols.length);

    hoja.setRowHeight(1, 26);
    for (int c = 0; c < cols.length; c++) {
      _cel(hoja, 1, c,
          value: cols[c].toUpperCase(),
          bold: true, fg: _blanco, bg: _azulMedio);
    }

    for (int r = 0; r < filas.length; r++) {
      hoja.setRowHeight(r + 2, 20);
      final bg = (r % 2 == 0) ? _blanco : _grisClaro;
      for (int c = 0; c < cols.length; c++) {
        final val  = filas[r][cols[c]];
        String fg  = _negro;
        final colL = cols[c].toLowerCase();
        if (colL == 'estado') {
          final v = val?.toString() ?? '';
          if (v == 'sincronizado') fg = _verdeSync;
          if (v == 'pendiente')    fg = _amarillo;
          if (v == 'error')        fg = _rojo;
          if (v == 'en_proceso')   fg = _azulPlaneta;
        }
        _cel(hoja, r + 2, c, value: val?.toString() ?? '', fg: fg, bg: bg);
      }
    }

    hoja.setRowHeight(filas.length + 2, 26);
    _cel(hoja, filas.length + 2, 0,
        value: 'Total: ${filas.length} registros',
        bold: true, fg: _blanco, bg: _azulOscuro, span: cols.length);
  }

  // ══════════════════════════════════════════════════════════
  // CELDA ESTILIZADA
  // ══════════════════════════════════════════════════════════
  static void _cel(
    Sheet hoja, int fila, int col, {
    required String value,
    bool    bold = false,
    double? size,
    String  fg   = '111111',
    String  bg   = 'FFFFFF',
    int?    span,
  }) {
    final idx  = CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila);
    final cell = hoja.cell(idx);
    cell.value = TextCellValue(value);
    cell.cellStyle = CellStyle(
      bold               : bold,
      fontSize           : size?.toInt(),
      fontColorHex       : ExcelColor.fromHexString('#$fg'),
      backgroundColorHex : ExcelColor.fromHexString('#$bg'),
    );
    if (span != null && span > 1) {
      hoja.merge(
        idx,
        CellIndex.indexByColumnRow(
            columnIndex: col + span - 1, rowIndex: fila),
      );
    }
  }

  static void _tarjeta(
      Sheet hoja, int fila, int col, String label, String valor) {
    _cel(hoja, fila,     col,
        value: label, bold: false, size: 9,  fg: _blanco,     bg: _azulMedio);
    _cel(hoja, fila + 1, col,
        value: valor, bold: true,  size: 16, fg: _azulOscuro, bg: _grisClaro);
  }

  // ══════════════════════════════════════════════════════════
  // ZIP
  // ══════════════════════════════════════════════════════════
  static Future<void> _generarZip(
      List<String> archivos, String ruta) async {
    final enc = ZipFileEncoder();
    enc.create(ruta);
    for (final a in archivos) {
      final f = File(a);
      if (await f.exists()) enc.addFile(f);
    }
    enc.close();
  }

  // ══════════════════════════════════════════════════════════
  // EMAIL
  // ══════════════════════════════════════════════════════════
  static Future<void> _enviarEmail({
    required File   zipFile,
    required String fecha,
    required String deviceId,
    required Map<String, List<Map<String, dynamic>>> tablasCrudas,
    required List<Map<String, dynamic>> traspasos,
  }) async {
    final totalReg    = tablasCrudas.values.fold(0, (s, f) => s + f.length);
    final totalLineas = traspasos.fold<int>(
        0, (s, t) => s + ((t['lineas'] as List?)?.length ?? 0));
    final totalLibros = traspasos.fold<int>(0, (s, t) {
      final lineas = (t['lineas'] as List?) ?? [];
      return s + lineas.fold<int>(
          0, (sl, l) => sl + ((l['cantidad'] as int?) ?? 0));
    });
    final sincronizados = traspasos.where((t) => t['estado'] == 'sincronizado').length;
    final pendientes    = traspasos.where((t) => t['estado'] == 'pendiente').length;

    final filasTablaHtml = tablasCrudas.entries.map((e) {
      final ok    = e.value.isNotEmpty;
      final color = ok ? '#16A34A' : '#D97706';
      final est   = ok ? '✓ OK'   : 'Sin datos';
      return '''
        <tr>
          <td style="padding:7px 12px;border-bottom:1px solid #E5E7EB;">${e.key}</td>
          <td style="padding:7px 12px;border-bottom:1px solid #E5E7EB;text-align:center;font-weight:600;color:#2563EB;">${e.value.length}</td>
          <td style="padding:7px 12px;border-bottom:1px solid #E5E7EB;text-align:center;color:$color;font-weight:600;">$est</td>
        </tr>''';
    }).join('\n');

    final html = '''
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#F3F4F6;font-family:Arial,Helvetica,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F3F4F6;padding:32px 0;">
    <tr><td align="center">
      <table width="640" cellpadding="0" cellspacing="0"
             style="background:#FFFFFF;border-radius:10px;overflow:hidden;
                    box-shadow:0 2px 12px rgba(0,0,0,0.08);">
        <tr>
          <td style="background:#0D1B4B;padding:28px 36px;">
            <p style="margin:0;font-size:11px;color:#93C5FD;letter-spacing:2px;text-transform:uppercase;">
              Editorial Planeta Colombia
            </p>
            <h1 style="margin:6px 0 0;font-size:22px;color:#FFFFFF;font-weight:700;">
              Backup de Traspasos
            </h1>
            <p style="margin:6px 0 0;font-size:13px;color:#93C5FD;">
              Dispositivo: <strong style="color:#FFFFFF;">$deviceId</strong>
              &nbsp;·&nbsp; $fecha
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:0;background:#1A3272;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td align="center" style="padding:18px 0;border-right:1px solid #2563EB;">
                  <p style="margin:0;font-size:26px;font-weight:700;color:#FFFFFF;">${traspasos.length}</p>
                  <p style="margin:4px 0 0;font-size:11px;color:#93C5FD;text-transform:uppercase;">Traspasos</p>
                </td>
                <td align="center" style="padding:18px 0;border-right:1px solid #2563EB;">
                  <p style="margin:0;font-size:26px;font-weight:700;color:#FFFFFF;">$totalLineas</p>
                  <p style="margin:4px 0 0;font-size:11px;color:#93C5FD;text-transform:uppercase;">Líneas</p>
                </td>
                <td align="center" style="padding:18px 0;border-right:1px solid #2563EB;">
                  <p style="margin:0;font-size:26px;font-weight:700;color:#34D399;">$totalLibros</p>
                  <p style="margin:4px 0 0;font-size:11px;color:#93C5FD;text-transform:uppercase;">Libros movidos</p>
                </td>
                <td align="center" style="padding:18px 0;border-right:1px solid #2563EB;">
                  <p style="margin:0;font-size:26px;font-weight:700;color:#34D399;">$sincronizados</p>
                  <p style="margin:4px 0 0;font-size:11px;color:#93C5FD;text-transform:uppercase;">Sincronizados</p>
                </td>
                <td align="center" style="padding:18px 0;">
                  <p style="margin:0;font-size:26px;font-weight:700;color:#FCD34D;">$pendientes</p>
                  <p style="margin:4px 0 0;font-size:11px;color:#93C5FD;text-transform:uppercase;">Pendientes</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:32px 36px;">
            <h2 style="margin:0 0 12px;font-size:14px;font-weight:700;color:#0D1B4B;text-transform:uppercase;">
              Resumen de tablas SQLite
            </h2>
            <table width="100%" cellpadding="0" cellspacing="0"
                   style="border-collapse:collapse;font-size:13px;border:1px solid #E5E7EB;border-radius:6px;overflow:hidden;">
              <thead>
                <tr style="background:#0D1B4B;">
                  <th style="padding:10px 12px;text-align:left;color:#FFFFFF;">Tabla</th>
                  <th style="padding:10px 12px;text-align:center;color:#FFFFFF;">Registros</th>
                  <th style="padding:10px 12px;text-align:center;color:#FFFFFF;">Estado</th>
                </tr>
              </thead>
              <tbody>$filasTablaHtml</tbody>
              <tfoot>
                <tr style="background:#F5F7FA;">
                  <td style="padding:9px 12px;font-weight:700;color:#0D1B4B;">Total</td>
                  <td style="padding:9px 12px;text-align:center;font-weight:700;color:#2563EB;">$totalReg</td>
                  <td style="padding:9px 12px;text-align:center;">${tablasCrudas.length} tablas</td>
                </tr>
              </tfoot>
            </table>
            <div style="margin-top:20px;padding:12px 16px;background:#EFF6FF;border:1px solid #BFDBFE;border-radius:6px;">
              <p style="margin:0;font-size:12px;color:#1E40AF;line-height:1.7;">
                <strong>📁 Archivo adjunto:</strong> .ZIP con script SQL (hmoval) + Excel detallado<br>
                <strong>📦 Traspasos:</strong> ${traspasos.length} movimientos · $totalLineas líneas · $totalLibros libros movidos<br>
                <strong>✅ Sincronizados:</strong> $sincronizados &nbsp;·&nbsp; <strong>⏳ Pendientes:</strong> $pendientes<br>
                <strong>💾 Guardado en:</strong> <code>/storage/emulated/0/Traspasos/$fecha/</code>
              </p>
            </div>
          </td>
        </tr>
        <tr>
          <td style="background:#F5F7FA;padding:18px 36px;border-top:1px solid #E5E7EB;">
            <p style="margin:0;font-size:11px;color:#9CA3AF;text-align:center;">
              App Traspasos · Editorial Planeta Colombia · No responder este correo.
            </p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>''';

    final smtpServer = SmtpServer(
      _smtpHost,
      port                : _smtpPort,
      username            : _smtpUser,
      password            : _smtpPass,
      ignoreBadCertificate: false,
      ssl                 : false,
    );

    final msg = Message()
      ..from        = Address(_smtpUser,
          'App Traspasos · Editorial Planeta [$deviceId]')
      ..recipients.addAll(_destinatarios.map((e) => Address(e)))
      ..subject     = '📦 Backup Traspasos Planeta [$deviceId] — $fecha'
      ..html        = html
      ..attachments = [FileAttachment(zipFile)..location = Location.attachment];

    await send(msg, smtpServer);
  }

  // ══════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════
  static String _fechaArchivo() {
    final n = TrustedClockService().horaActual;
    return '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}

// ══════════════════════════════════════════════════════════
// DTO ISOLATE
// ══════════════════════════════════════════════════════════
class _BackupArgs {
  final Map<String, List<Map<String, dynamic>>> tablasCrudas;
  final List<Map<String, dynamic>> traspasos;
  final String sqlPath, xlsxPath, zipPath, fecha, deviceId;

  const _BackupArgs({
    required this.tablasCrudas,
    required this.traspasos,
    required this.sqlPath,
    required this.xlsxPath,
    required this.zipPath,
    required this.fecha,
    required this.deviceId,
  });
}

// ══════════════════════════════════════════════════════════
// RESULTADO
// ══════════════════════════════════════════════════════════
class BackupResult {
  final bool    ok;
  final String  mensaje;
  final String? sqlPath, xlsxPath, zipPath, carpeta;

  const BackupResult({
    required this.ok,
    required this.mensaje,
    this.sqlPath,
    this.xlsxPath,
    this.zipPath,
    this.carpeta,
  });
}