import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/connectivity_service.dart';
import '../core/database_service.dart';
import '../core/device_service.dart';

class ApiService {
  static const String _baseUrl =
      'https://prologics.co/app_planeta/controlador';

  static const String urlDescargar =
      '$_baseUrl/descarga_datos_nube_movil2.php';

  static const String urlSubir =
      '$_baseUrl/subir_datos_nube_movil.php';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ),
  );

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
  // SUBIR DATOS
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

    final uuidsPendientes =
        traspasos.map((t) => t['local_uuid'] as String).toList();

    final movimientos  = <Map<String, dynamic>>[];
    final manucaAUuid  = <String, String>{};

    // ── deviceId se obtiene UNA sola vez fuera del loop ──
    final deviceId = await DeviceService().getDeviceId();

    for (final t in traspasos) {
      final lineas = t['lineas'] as List;
      final uuid   = t['local_uuid'] as String;

      final fecha = (t['fecha_creacion'] as String? ?? '')
          .replaceAll(RegExp(r'[^0-9]'), '');

      // ── base fijo por traspaso: usa num_movimiento estable ──
      final numMov = t['num_movimiento']?.toString() ?? 
                     DateTime.now().millisecondsSinceEpoch.toString();
      final base   = '${deviceId}_$numMov';

      manucaAUuid[base] = uuid;

      debugPrint(
        '📦 Preparando traspaso uuid=$uuid | base=$base | '
        'líneas=${lineas.length} | manuma=$numMov',
      );

      for (var i = 0; i < lineas.length; i++) {
        final linea = lineas[i] as Map<String, dynamic>;

        debugPrint(
          '   📄 línea ${i + 1}/${lineas.length} | '
          'código=${linea['codigo']} | cantidad=${linea['cantidad']}',
        );

        movimientos.add({
          'manuca': base,
          'manuml': (i + 1).toString(),
          'manuma': numMov,
          // ── campos fijos ──
          'macdhr': '1',
          'macdso': '1',
          'macdeo': 'PL',
          'macdao': '23',
          'macdhd': '1',
          'macdsd': '1',
          'macded': 'PL',
          'macdad': '23',
          // ── fijos de operación ──
          'macdco': 'TRA',
          'matran': 'TF',
          'matrge': 'ET',
          // ── dinámicos ──
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

    debugPrint('📤 Total movimientos a subir: ${movimientos.length}');

    try {
      final response = await _dio.post(
        urlSubir,
        data: {'movimientos': movimientos},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      final result = await _handle(Future.value(response));

      if (result['status'] == 'ok') {
        final resumen    = result['resumen']  as Map<String, dynamic>? ?? {};
        final resHmoval  = resumen['hmoval']  as Map<String, dynamic>? ?? {};
        final fallidos   = (resHmoval['fallidos']  ?? 0) as int;
        final omitidos   = (resHmoval['omitidos']  ?? 0) as int;
        final insertados = (resHmoval['insertados'] ?? 0) as int;

        debugPrint(
          '📊 Resumen subida → '
          'insertados: $insertados | omitidos: $omitidos | fallidos: $fallidos',
        );

        final detalles = resumen['detalle']         as List? ??
                         resumen['omitidos_detalle'] as List? ??
                         result['detalle']           as List? ??
                         result['omitidos_detalle']  as List? ??
                         result['items']             as List? ??
                         [];

        if (omitidos > 0) {
          debugPrint('──────────────────────────────────────────');
          debugPrint('⚠ $omitidos MOVIMIENTO(S) OMITIDO(S):');
          if (detalles.isNotEmpty) {
            for (final d in detalles) {
              if (d is Map) {
                final motivo     = d['motivo'] ?? d['razon'] ?? 'Sin motivo';
                final manucaVal  = d['manuca'] ?? '?';
                final manulVal   = d['manuml'] ?? '?';
                final codigoVal  = d['macdpt'] ?? '?';
                final uuidAsoc   = manucaAUuid[manucaVal.toString()] ?? 'uuid desconocido';
                debugPrint('   🔸 manuca=$manucaVal | línea=$manulVal | código=$codigoVal');
                debugPrint('      motivo: $motivo');
                debugPrint('      uuid local: $uuidAsoc');
              }
            }
          } else {
            debugPrint('   ℹ Sin detalle del servidor.');
            debugPrint('   ${jsonEncode(result)}');
          }
          debugPrint('──────────────────────────────────────────');
        }

        if (fallidos == 0 && omitidos == 0) {
          await db.marcarTraspasosSincronizados(uuidsPendientes);
          debugPrint('✅ ${uuidsPendientes.length} traspasos sincronizados');
        } else {
          debugPrint(
            '⚠ NO sincronizados (fallidos=$fallidos, omitidos=$omitidos) — reintento próximo ciclo',
          );
          for (final uuid in uuidsPendientes) {
            debugPrint('   📌 UUID pendiente: $uuid');
          }
        }
      }

      return result;
    } catch (e) {
      return {'status': 'error', 'message': 'Error al subir: $e'};
    }
  }

  // ─────────────────────────────────────────────
  // SUBIR DATOS RAW
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> subirDatosRaw(
    List<Map<String, dynamic>> movimientos,
  ) async {
    if (movimientos.isEmpty) {
      return {
        'status'  : 'ok',
        'message' : 'Sin movimientos',
        'resumen' : {
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
  // BUSCAR LIBRO — SOLO LOCAL
  // ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> buscarLibro(String codigo) async {
    final codigoNorm = codigo.trim();
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
        return {
          'status': 'ok',
          'producto': {
            'codigo'     : p['EAN'] ?? p['Referencia'] ?? '',
            'descripcion': p['Desc_Referencia'] ?? '',
            'precio'     : p['Precio'] ?? 0,
          }
        };
      }

      debugPrint('⚠ Libro no encontrado en local: $codigoNorm');
      return {
        'status': 'error',
        'message': 'Libro no encontrado. Sincroniza el dispositivo.',
      };
    } catch (e) {
      debugPrint('⚠ Error buscando libro en local: $e');
      return {'status': 'error', 'message': 'Error al buscar el libro'};
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

      final hayInternet = await ConnectivityService().checkOnline();
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