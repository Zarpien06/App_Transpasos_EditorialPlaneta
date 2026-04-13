import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/connectivity_service.dart';
import '../core/database_service.dart';
import '../core/device_service.dart';
import '../services/sync_log_service.dart';  // ← NUEVO

class ApiService {
  static const String _baseUrl =
      'https://prologics.co/app_planeta/controlador';

  static const String urlDescargar =
      '$_baseUrl/descarga_datos_nube_movil2.php';

  // ── Un solo endpoint para movimientos Y productos ────────────────────────
  static const String urlSubir =
      '$_baseUrl/subir_datos_nube_movil.php';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static const int _tamanoLote = 5;

  // ─────────────────────────────────────────────
  // HELPERS INTERNOS
  // ─────────────────────────────────────────────

  static String extraerNumeroCompleto(dynamic value) {
    final match = RegExp(r'\d+').firstMatch(value.toString());
    return match != null ? match.group(0)! : '';
  }

  static Future<Map<String, dynamic>> _handle(Future<Response> req) async {
    try {
      final response = await req;
      var data = response.data;

      if (kDebugMode) {
        debugPrint('▶ RESPONSE: $data');
        debugPrint('▶ TYPE: ${data.runtimeType}');
      }

      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return {'status': 'ok', 'data': data};
        }
      }

      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is List) return {'status': 'ok', 'data': data};

      return {'status': 'error', 'message': 'Formato inválido'};
    } on DioException catch (e) {
      return {'status': 'error', 'message': _parseError(e)};
    } catch (e) {
      return {'status': 'error', 'message': 'Error inesperado: $e'};
    }
  }

  static String _parseError(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['message']?.toString() ?? 'Error servidor';
    if (data is String) return data;
    return e.message ?? 'Error de conexión';
  }

  // ─────────────────────────────────────────────
  // VERIFICACIÓN DE INTERNET REAL POR HTTP
  // ─────────────────────────────────────────────
  static Future<bool> hayInternetReal() async {
    try {
      final response = await _dio.head(
        '$_baseUrl/ping.php',
        options: Options(
          sendTimeout:    const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
        ),
      );
      final ok = (response.statusCode ?? 0) > 0;
      debugPrint(ok
          ? '🌐 Con conexión a internet : OK (HTTP ${response.statusCode})'
          : '🚫 Sin conexión a internet : sin respuesta HTTP');
      return ok;
    } catch (_) {
      debugPrint('🚫 Sin conexión a internet : error al verificar');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // DESCARGAR DATOS
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> descargarDatos({
    String? stand,
    String? codigoUsuario,
  }) {
    return _handle(
      _dio.get(
        urlDescargar,
        queryParameters: {
          if (stand != null) 'stand': stand,
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SUBIR DATOS — CON ENVÍO POR LOTES
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> subirDatos() async {
    final db = DatabaseService();
    final traspasos = await db.getTraspasosPendientesConLineas();

    if (traspasos.isEmpty) {
      return {
        'status': 'ok',
        'message': 'Sin pendientes',
        'resumen': {
          'hmoval': {'insertados': 0, 'omitidos': 0, 'fallidos': 0}
        }
      };
    }

    final deviceId = await DeviceService().getDeviceId();

    int totalInsertados = 0;
    int totalOmitidos   = 0;
    int totalFallidos   = 0;
    final uuidsSincronizados = <String>[];

    for (var i = 0; i < traspasos.length; i += _tamanoLote) {
      final lote = traspasos.sublist(i, min(i + _tamanoLote, traspasos.length));

      debugPrint(
        '📦 Lote ${(i ~/ _tamanoLote) + 1} → '
        '${lote.length} traspasos (índices $i–${i + lote.length - 1})',
      );

      final movimientos  = <Map<String, dynamic>>[];
      final manucaAUuid  = <String, String>{};
      final uuidsDelLote = <String>[];

      for (final t in lote) {
        final lineas = t['lineas'] as List;
        final uuid   = t['local_uuid'] as String;

        final fecha = (t['fecha_creacion'] as String? ?? '')
            .replaceAll(RegExp(r'[^0-9]'), '');

        final numMov = t['num_movimiento']?.toString() ??
                       DateTime.now().millisecondsSinceEpoch.toString();
        final base   = '${deviceId}_$numMov';

        manucaAUuid[base] = uuid;
        uuidsDelLote.add(uuid);

        debugPrint(
          '   📄 Traspaso uuid=$uuid | base=$base | líneas=${lineas.length}',
        );

        for (var j = 0; j < lineas.length; j++) {
          final linea = lineas[j] as Map<String, dynamic>;
          movimientos.add({
            'manuca': base,
            'manuml': (j + 1).toString(),
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
            'mafemo': fecha.length >= 8 ? fecha.substring(0, 8) : '',
            'mafman': fecha.length >= 4 ? fecha.substring(0, 4) : '',
            'mafmme': fecha.length >= 6 ? fecha.substring(4, 6) : '0',
            'mafmdi': fecha.length >= 8 ? fecha.substring(6, 8) : '0',
            'mahogr': DateTime.now().hour.toString(),
            'macdlo': t['origen_decoded']?['Codigo_Almacen']  ?? '',
            'macdld': t['destino_decoded']?['Codigo_Almacen'] ?? '',
            'macdpt': linea['codigo']   ?? '',
            'macant': (linea['cantidad'] as num?)?.toInt() ?? 1,
          });
        }
      }

      debugPrint('   📤 Movimientos en lote: ${movimientos.length}');

      Map<String, dynamic> result;
      try {
        final response = await _dio.post(
          urlSubir,
          data: {'movimientos': movimientos},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        result = await _handle(Future.value(response));
      } catch (e) {
        debugPrint('❌ Lote falló por red: $e — deteniendo sync');
        return {
          'status' : 'error',
          'message': 'Lote falló: $e',
          'resumen': {
            'hmoval': {
              'insertados': totalInsertados,
              'omitidos'  : totalOmitidos,
              'fallidos'  : totalFallidos + lote.length,
            }
          }
        };
      }

      if (result['status'] != 'ok') {
        debugPrint('❌ Servidor rechazó el lote: ${result['message']}');
        break;
      }

      final resumen    = result['resumen']  as Map<String, dynamic>? ?? {};
      final resHmoval  = resumen['hmoval']  as Map<String, dynamic>? ?? {};
      final fallidos   = (resHmoval['fallidos']   ?? 0) as int;
      final omitidos   = (resHmoval['omitidos']   ?? 0) as int;
      final insertados = (resHmoval['insertados'] ?? 0) as int;

      totalInsertados += insertados;
      totalOmitidos   += omitidos;
      totalFallidos   += fallidos;

      debugPrint(
        '   📊 Lote → insertados: $insertados | omitidos: $omitidos | fallidos: $fallidos',
      );

      if (omitidos > 0 && kDebugMode) {
        final detalles = resumen['detalle']          as List? ??
                         resumen['omitidos_detalle']  as List? ??
                         result['detalle']            as List? ??
                         result['omitidos_detalle']   as List? ??
                         [];
        debugPrint('   ⚠ $omitidos omitido(s):');
        for (final d in detalles) {
          if (d is Map) {
            debugPrint(
              '     🔸 manuca=${d['manuca']} | línea=${d['manuml']} '
              '| código=${d['macdpt']} | motivo=${d['motivo'] ?? d['razon']}',
            );
          }
        }
      }

      if (fallidos == 0) {
        uuidsSincronizados.addAll(uuidsDelLote);
        debugPrint('   ✅ Lote marcado como sincronizado (${uuidsDelLote.length} traspasos)');
      } else {
        debugPrint(
          '   ⚠ Lote con $fallidos fallido(s) — traspasos quedan pendientes',
        );
      }
    }

    if (uuidsSincronizados.isNotEmpty) {
      await db.marcarTraspasosSincronizados(uuidsSincronizados);
      debugPrint('✅ Total sincronizados: ${uuidsSincronizados.length}');
    }

    final pendientesRestantes = traspasos.length - uuidsSincronizados.length;
    if (pendientesRestantes > 0) {
      debugPrint('📌 Pendientes para próximo ciclo: $pendientesRestantes');
    }

    return {
      'status' : totalFallidos == 0 ? 'ok' : 'partial',
      'message': 'Sincronización completada',
      'resumen': {
        'hmoval': {
          'insertados': totalInsertados,
          'omitidos'  : totalOmitidos,
          'fallidos'  : totalFallidos,
        }
      },
      'sincronizados': uuidsSincronizados.length,
      'pendientes'   : pendientesRestantes,
    };
  }

  // ─────────────────────────────────────────────
  // SUBIR DATOS RAW
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> subirDatosRaw(
    List<Map<String, dynamic>> movimientos,
  ) async {
    if (movimientos.isEmpty) {
      return {
        'status'          : 'ok',
        'message'         : 'Sin movimientos',
        'resumen'         : {
          'hmoval': {'insertados': 0, 'omitidos': 0, 'fallidos': 0}
        },
        'omitidos_detalle': [],
        'errores'         : [],
      };
    }
    try {
      final response = await _dio.post(
        urlSubir,
        data   : {'movimientos': movimientos},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return await _handle(Future.value(response));
    } catch (e) {
      return {'status': 'error', 'message': 'Error al subir: $e'};
    }
  }

  // ─────────────────────────────────────────────
  // HELPERS PÚBLICOS
  // ─────────────────────────────────────────────

  static Map<String, dynamic>? getAdmin(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return null;
    final admin = data['admin'];
    return admin is Map ? Map<String, dynamic>.from(admin) : null;
  }

  static List<Map<String, dynamic>> getUsuariosTranspasos(
      Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return [];
    final raw = data['usuarios_transpasos'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (raw is Map) return [Map<String, dynamic>.from(raw)];
    return [];
  }

  static List<Map<String, dynamic>> getProductos(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return [];
    final list = data['productos'];
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static List<Map<String, dynamic>> getDatosCaja(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return [];
    final list = data['datos_caja'];
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static bool isModoOffline(Map<String, dynamic> res) =>
      res['modo'] == 'offline';

  // ─────────────────────────────────────────────
  // LOGIN ADMIN
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> adminLogin({
    required String nick,
    required String pwd,
  }) async {
    final connectivity = ConnectivityService();
    final hayInternet = await connectivity.checkOnline();

    if (!hayInternet) {
      debugPrint('⚠ adminLogin: sin internet, validando en local...');
      return _adminLoginLocal(nick: nick, pwd: pwd);
    }

    debugPrint('✅ adminLogin: con internet, validando en servidor...');
    final res = await descargarDatos();

    if (res['status'] != 'ok') {
      debugPrint('⚠ adminLogin: servidor falló, fallback a local...');
      return _adminLoginLocal(nick: nick, pwd: pwd);
    }

    final admin = getAdmin(res);
    if (admin == null) {
      return {'status': 'error', 'message': 'No hay admin en servidor'};
    }

    final nickOk = admin['Nick_Usuario']?.toString().trim() == nick.trim();

    String pwdServer = '';
    try {
      pwdServer = utf8.decode(
          base64Decode(admin['Pwd_Usuario']?.toString().trim() ?? ''));
    } catch (_) {
      pwdServer = admin['Pwd_Usuario']?.toString().trim() ?? '';
    }

    final pwdOk = pwdServer == pwd.trim();

    if (!nickOk || !pwdOk) {
      return {'status': 'error', 'message': 'Credenciales incorrectas'};
    }

    try {
      final db = DatabaseService();
      await db.guardarAdminLocal(nick.trim(), pwd.trim());
      debugPrint('✅ Admin guardado en local para uso offline');
    } catch (e) {
      debugPrint('⚠ No se pudo guardar admin en local: $e');
    }

    return {'status': 'ok', 'admin': admin};
  }

  // ─────────────────────────────────────────────
  // LOGIN ADMIN LOCAL
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> _adminLoginLocal({
    required String nick,
    required String pwd,
  }) async {
    try {
      final db = DatabaseService();
      final adminLocal = await db.getAdminLocal(nick.trim());

      if (adminLocal == null) {
        return {
          'status': 'error',
          'message': 'Sin conexión y no hay datos locales.\n'
              'Sincroniza el dispositivo con internet.',
        };
      }

      final pwdOk = adminLocal['password']?.toString() == pwd.trim();
      if (!pwdOk) {
        return {'status': 'error', 'message': 'Credenciales incorrectas'};
      }

      debugPrint('✅ Admin validado en LOCAL (modo offline)');
      return {'status': 'ok', 'admin': adminLocal, 'modo': 'offline'};
    } catch (e) {
      debugPrint('⚠ Error en adminLoginLocal: $e');
      return {'status': 'error', 'message': 'Error al validar admin local'};
    }
  }

  // ─────────────────────────────────────────────
  // VALIDAR USUARIO — SOLO LOCAL
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> validarUsuario(String clave) async {
    final claveNorm = clave.trim();
    try {
      final db = DatabaseService();
      final local = await db.buscarUsuarioPorClave(claveNorm);
      if (local != null) {
        debugPrint('✅ Usuario encontrado en LOCAL: ${local['Nombre_UsuarioT']}');
        return {'status': 'ok', 'data': local};
      }
      debugPrint('⚠ Usuario no encontrado en local: $claveNorm');
      return {
        'status': 'error',
        'message': 'Usuario no encontrado. Sincroniza el dispositivo.',
      };
    } catch (e) {
      debugPrint('⚠ Error buscando usuario en local: $e');
      return {'status': 'error', 'message': 'Error al buscar usuario'};
    }
  }

  // ─────────────────────────────────────────────
  // BUSCAR LIBRO — LOCAL PRIMERO, LUEGO NUBE
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> buscarLibro(String codigo) async {
    final codigoNorm = codigo.trim();

    // ── 1. Buscar en local ─────────────────────────────────────────────
    try {
      final db = DatabaseService();
      final productos = await db.getProductos();
      final match = productos.where((p) {
        return p['EAN']?.toString().trim()        == codigoNorm ||
               p['ISBN']?.toString().trim()       == codigoNorm ||
               p['Referencia']?.toString().trim() == codigoNorm;
      }).toList();

      if (match.isNotEmpty) {
        final p = match.first;
        debugPrint('✅ Libro encontrado en LOCAL: ${p['Desc_Referencia']}');
        return {
          'status' : 'ok',
          'fuente' : 'local',
          'producto': {
            'codigo'     : p['EAN'] ?? p['Referencia'] ?? '',
            'descripcion': p['Desc_Referencia'] ?? '',
            'precio'     : p['Precio'] ?? 0,
          }
        };
      }
    } catch (e) {
      debugPrint('⚠ Error buscando libro en local: $e');
    }

    // ── 2. Buscar en nube si hay internet ──────────────────────────────
    debugPrint('🔍 Libro no en local, buscando en nube: $codigoNorm');
    final hayInternet = await hayInternetReal();

    if (!hayInternet) {
      return {
        'status' : 'error',
        'message': 'Libro no encontrado. Sin conexión para buscar en servidor.',
      };
    }

    try {
      // GET al mismo urlSubir con ?ean=xxx  ← el PHP maneja GET con ?ean=
      final response = await _dio.get(
        urlSubir,
        queryParameters: {'ean': codigoNorm},
        options: Options(
          sendTimeout   : const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final result = await _handle(Future.value(response));

      if (result['status'] == 'ok' && result['producto'] != null) {
        final p = result['producto'] as Map<String, dynamic>;
        debugPrint('✅ Libro encontrado en NUBE: ${p['Desc_Referencia']}');

        // Cachear en local
        try {
          final db = DatabaseService();
          await db.insertarOActualizarProducto({
            'EAN'            : p['EAN']             ?? codigoNorm,
            'ISBN'           : p['ISBN']            ?? '',
            'Referencia'     : p['Referencia']      ?? '999999',
            'Desc_Referencia': p['Desc_Referencia'] ?? '',
            'Precio'         : p['Precio']          ?? 0,
            'Porc_impuesto'  : p['Porc_impuesto']   ?? 0,
          });
          debugPrint('💾 Libro cacheado en local');
        } catch (e) {
          debugPrint('⚠ No se pudo cachear en local: $e');
        }

        return {
          'status' : 'ok',
          'fuente' : 'nube',
          'producto': {
            'codigo'     : p['EAN']             ?? codigoNorm,
            'descripcion': p['Desc_Referencia'] ?? '',
            'precio'     : p['Precio']          ?? 0,
          }
        };
      }

      debugPrint('⚠ Libro no encontrado en nube: $codigoNorm');
      return {
        'status' : 'not_found',
        'message': 'Libro no encontrado en local ni en servidor.',
      };
    } catch (e) {
      debugPrint('⚠ Error buscando en nube: $e');
      return {'status': 'error', 'message': 'Error al buscar en servidor'};
    }
  }

  // ─────────────────────────────────────────────
  // AGREGAR PRODUCTO — NUBE + LOCAL + LOG
  // ─────────────────────────────────────────────
  // POST { action: "agregar_producto", EAN, Desc_Referencia, Precio }
  // El PHP detecta "action" y bifurca al bloque agregar_producto.
  // Respuesta exitosa del PHP:
  //   { status: "ok", producto: { id, EAN, Referencia, Desc_Referencia,
  //                               Precio, accion: "insertado"|"actualizado" } }
  //
  // Cada resultado queda registrado en SyncLogService con tipo=producto
  // y es visible en tiempo real en el SyncLogPanel del admin dashboard.

  static Future<Map<String, dynamic>> agregarProducto({
    required String ean,
    required String descReferencia,
    required double precio,
  }) async {
    final eanNorm  = ean.trim();
    final descNorm = descReferencia.trim();
    final log      = SyncLogService();  // ← instancia del log

    if (eanNorm.isEmpty || descNorm.isEmpty) {
      return {'status': 'error', 'message': 'EAN y descripción son requeridos'};
    }

    final hayInternet = await hayInternetReal();

    // ── Sin internet: guardar solo en local con pendiente_sync = 1 ────
    if (!hayInternet) {
      debugPrint('📵 Sin internet — guardando producto solo en local');
      try {
        final db = DatabaseService();
        await db.insertarOActualizarProducto({
          'EAN'            : eanNorm,
          'ISBN'           : '',
          'Referencia'     : '999999',
          'Desc_Referencia': descNorm,
          'Precio'         : precio,
          'Porc_impuesto'  : 0,
          'pendiente_sync' : 1,
        });

        // ── LOG: guardado offline, pendiente de sync ───────────────────
        await log.agregar(
          tipo   : SyncLogTipo.producto,
          estado : SyncLogEstado.omitido,
          mensaje: '$descNorm — guardado offline (pendiente sync)',
          detalle: 'EAN: $eanNorm | Precio: $precio',
        );

        return {
          'status' : 'ok',
          'message': 'Producto guardado localmente (se sincronizará con internet)',
          'modo'   : 'offline',
          'producto': {
            'EAN'            : eanNorm,
            'Desc_Referencia': descNorm,
            'Precio'         : precio,
          }
        };
      } catch (e) {
        return {'status': 'error', 'message': 'Error al guardar en local: $e'};
      }
    }

    // ── Con internet: POST { action: "agregar_producto", ... } ────────
    // El PHP bifurca en: if (isset($data['action']) && $data['action'] === 'agregar_producto')
    try {
      debugPrint('📤 Enviando producto a nube: EAN=$eanNorm');
      final response = await _dio.post(
        urlSubir,
        data: {
          'action'         : 'agregar_producto',
          'EAN'            : eanNorm,
          'Desc_Referencia': descNorm,
          'Precio'         : precio,
        },
        options: Options(
          headers        : {'Content-Type': 'application/json'},
          sendTimeout    : const Duration(seconds: 10),
          receiveTimeout : const Duration(seconds: 15),
        ),
      );

      final result = await _handle(Future.value(response));

      // ── Servidor rechazó el producto ──────────────────────────────
      if (result['status'] != 'ok') {
        debugPrint('❌ Servidor rechazó producto: ${result['message']}');

        // ── LOG: error del servidor ────────────────────────────────
        await log.agregar(
          tipo   : SyncLogTipo.producto,
          estado : SyncLogEstado.fallido,
          mensaje: '$descNorm — servidor rechazó el producto',
          detalle: 'EAN: $eanNorm | Error: ${result['message']}',
        );

        return result;
      }

      // ── Producto procesado OK en nube ─────────────────────────────
      // PHP responde: { status:"ok", producto:{ id, EAN, Referencia,
      //                Desc_Referencia, Precio, accion:"insertado"|"actualizado" } }
      final p      = result['producto'] as Map<String, dynamic>? ?? {};
      final accion = p['accion']?.toString() ?? 'procesado'; // "insertado" o "actualizado"
      debugPrint('✅ Producto $accion en nube: ID=${p['id']}');

      // Guardar/actualizar en local con pendiente_sync = 0
      try {
        final db = DatabaseService();
        await db.insertarOActualizarProducto({
          'EAN'            : eanNorm,
          'ISBN'           : '',
          'Referencia'     : '999999',
          'Desc_Referencia': descNorm,
          'Precio'         : precio,
          'Porc_impuesto'  : 0,
          'pendiente_sync' : 0,          // ← ya sincronizado
        });
        debugPrint('💾 Producto guardado en local');
      } catch (e) {
        debugPrint('⚠ No se pudo guardar en local (no crítico): $e');
      }

      // ── LOG: éxito — muestra si fue insertado o actualizado ───────
      await log.agregar(
        tipo   : SyncLogTipo.producto,
        estado : SyncLogEstado.ok,
        mensaje: '$descNorm — $accion en nube',
        detalle: 'EAN: $eanNorm | Precio: $precio | ID: ${p['id']}',
      );

      return {
        'status' : 'ok',
        'message': result['message'] ?? 'Producto guardado',
        'accion' : accion,
        'producto': {
          'id'             : p['id'],
          'EAN'            : eanNorm,
          'Referencia'     : '999999',
          'Desc_Referencia': descNorm,
          'Precio'         : precio,
        }
      };
    } catch (e) {
      debugPrint('⚠ Error al agregar producto: $e');

      // ── LOG: excepción de red u otro error ────────────────────────
      await log.agregar(
        tipo   : SyncLogTipo.producto,
        estado : SyncLogEstado.fallido,
        mensaje: '$descNorm — error al conectar con el servidor',
        detalle: 'EAN: $eanNorm | Excepción: $e',
      );

      return {'status': 'error', 'message': 'Error al agregar producto: $e'};
    }
  }

  // ─────────────────────────────────────────────
  // REGISTRAR TRASPASO — SOLO LOCAL
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> registrarTraspaso(
      Map<String, dynamic> data) async {
    try {
      final db        = DatabaseService();
      final deviceSvc = DeviceService();

      final uuid        = await deviceSvc.generarUUID();
      final deviceId    = await deviceSvc.getDeviceId();
      final ahora       = DateTime.now().toIso8601String();
      final numMovLocal = await db.getNextManuma(deviceId);

      final origen  = data['origen']  as Map<String, dynamic>?;
      final destino = data['destino'] as Map<String, dynamic>?;
      final items   = data['items']   as List<dynamic>? ?? [];

      final rowId = await db.insertarTraspasoReturnId({
        'local_uuid'    : uuid,
        'device_id'     : deviceId,
        'origen_json'   : jsonEncode(origen),
        'destino_json'  : jsonEncode(destino),
        'estado'        : 'pendiente',
        'num_movimiento': numMovLocal.toString(),
        'fecha_creacion': ahora,
      });

      for (final item in items) {
        await db.insertarLinea({
          'traspaso_uuid': uuid,
          'codigo'       : item['codigo']?.toString()      ?? '',
          'descripcion'  : item['descripcion']?.toString() ?? '',
          'cantidad'     : (item['cantidad'] as num?)?.toInt() ?? 1,
        });
      }

      await db.encolarSync(uuid);

      debugPrint(
        '✅ Traspaso guardado: uuid=$uuid | rowId=$rowId | manuma=$numMovLocal | '
        'items=${items.length}',
      );

      final hayInternet = await hayInternetReal();
      if (hayInternet) {
        final resultadoSubida = await ApiService.subirDatos();
        debugPrint(resultadoSubida['status'] == 'ok'
            ? '✅ Sincronizado inmediatamente'
            : '⚠ Subida falló: ${resultadoSubida['message']}');
      } else {
        debugPrint('📵 Sin internet — traspaso en cola');
      }

      return {
        'status'           : 'ok',
        'numero_movimiento': numMovLocal.toString(),
        'uuid'             : uuid,
        'modo'             : 'offline',
      };
    } catch (e) {
      debugPrint('⚠ Error guardando traspaso local: $e');
      return {'status': 'error', 'message': 'Error al guardar el traspaso'};
    }
  }

  // ─────────────────────────────────────────────
  // MÉTODOS COMPATIBILIDAD
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSyncPendientes() => descargarDatos();

  static Future<Map<String, dynamic>> guardarLibro({
    required String ean,
    required String ref,
    required String descripcion,
  }) => subirDatos();

  static Future<Map<String, dynamic>> marcarSincronizadoHmoval(
          List<int> numMovimientos) =>
      subirDatos();

  static Future<Map<String, dynamic>> marcarSincronizadoFacturas() =>
      subirDatos();
}