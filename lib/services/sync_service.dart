// lib/services/sync_service.dart

import 'package:flutter/foundation.dart';
import '../core/database_service.dart';
import 'api_service.dart';
import 'sync_log_service.dart';
import '../core/device_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE RESULTADO
// ─────────────────────────────────────────────────────────────────────────────

class SyncResultadoDescarga {
  final bool exitoso;
  final String mensaje;
  final String? serverTime;
  final bool adminOk;
  final bool usuariosTraspasosOk;
  final bool productosOk;
  final bool datosCajaOk;
  final Map<String, String> errores;

  const SyncResultadoDescarga({
    required this.exitoso,
    required this.mensaje,
    this.serverTime,
    this.adminOk = false,
    this.usuariosTraspasosOk = false,
    this.productosOk = false,
    this.datosCajaOk = false,
    this.errores = const {},
  });
}

class SyncResultadoSubida {
  final bool exitoso;
  final String mensaje;
  final int hmovalInsertados;
  final int hmovalOmitidos;
  final int hmovalFallidos;
  final Map<String, dynamic> errores;
  final int productosInsertados;
  final int productosOmitidos;
  final int productosFallidos;

  const SyncResultadoSubida({
    required this.exitoso,
    required this.mensaje,
    this.hmovalInsertados = 0,
    this.hmovalOmitidos = 0,
    this.hmovalFallidos = 0,
    this.errores = const {},
    this.productosInsertados = 0,
    this.productosOmitidos = 0,
    this.productosFallidos = 0,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class SyncService {
  static final _log = SyncLogService();
  static bool _running = false;

  // ──────────────────────────────────────────────────────────────────────────
  // DESCARGA
  // ──────────────────────────────────────────────────────────────────────────

  static Future<SyncResultadoDescarga> descargar({String? stand}) async {
    await _log.agregar(
      tipo    : SyncLogTipo.descarga,
      estado  : SyncLogEstado.enProceso,
      mensaje : 'Descargando datos desde la nube…',
    );

    try {
      final res = await ApiService.descargarDatos(stand: stand);

      final status     = res['status']?.toString()     ?? 'error';
      final mensaje    = res['message']?.toString()     ?? 'Sin respuesta';
      final serverTime = res['server_time']?.toString();

      final erroresRaw = res['errores'];
      final Map<String, String> errores = (erroresRaw is Map)
          ? erroresRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : <String, String>{};

      bool adminOk             = false;
      bool usuariosTraspasosOk = false;
      bool productosOk         = false;
      bool datosCajaOk         = false;

      if (status == 'ok') {
        final db = DatabaseService();

        final admin = ApiService.getAdmin(res);
        if (admin != null) {
          final nick = admin['Nick_Usuario']?.toString().trim() ?? '';
          final pwd  = admin['Pwd_Usuario']?.toString().trim()  ?? '';
          if (nick.isNotEmpty) {
            await db.guardarAdminLocal(nick, pwd);
            adminOk = true;
            await _log.agregar(
              tipo    : SyncLogTipo.descarga,
              estado  : SyncLogEstado.ok,
              mensaje : 'Admin sincronizado: $nick',
            );
          }
        }

        final usuariosRaw = res['data']?['usuarios_transpasos'];
        final List<Map<String, dynamic>> usuarios;
        if (usuariosRaw is List) {
          usuarios = usuariosRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (usuariosRaw is Map) {
          usuarios = [Map<String, dynamic>.from(usuariosRaw)];
        } else {
          usuarios = [];
        }

        if (usuarios.isNotEmpty) {
          await db.guardarUsuariosTranspasos(usuarios);
          usuariosTraspasosOk = true;
          await _log.agregar(
            tipo    : SyncLogTipo.descarga,
            estado  : SyncLogEstado.ok,
            mensaje : '${usuarios.length} usuarios de traspaso actualizados',
          );
        } else {
          await _log.agregar(
            tipo    : SyncLogTipo.descarga,
            estado  : SyncLogEstado.omitido,
            mensaje : 'Sin usuarios de traspaso en la respuesta',
          );
        }

        final productos = ApiService.getProductos(res);
        if (productos.isNotEmpty) {
          await db.guardarProductos(productos);
          productosOk = true;
          await _log.agregar(
            tipo    : SyncLogTipo.descarga,
            estado  : SyncLogEstado.ok,
            mensaje : '${productos.length} productos sincronizados',
          );
        } else {
          await _log.agregar(
            tipo    : SyncLogTipo.descarga,
            estado  : SyncLogEstado.omitido,
            mensaje : 'Sin productos en la respuesta del servidor',
          );
        }

        final datosCaja = ApiService.getDatosCaja(res);
        if (datosCaja.isNotEmpty) {
          datosCajaOk = true;
          await _log.agregar(
            tipo    : SyncLogTipo.descarga,
            estado  : SyncLogEstado.ok,
            mensaje : '${datosCaja.length} datos de caja recibidos',
          );
        }

        for (final entry in errores.entries) {
          await _log.agregar(
            tipo    : SyncLogTipo.descarga,
            estado  : SyncLogEstado.fallido,
            mensaje : 'Error servidor [${entry.key}]',
            detalle : entry.value,
          );
        }

        await _log.actualizarUltimo(
          tipo         : SyncLogTipo.descarga,
          nuevoEstado  : SyncLogEstado.ok,
          nuevoMensaje : 'Descarga completada${serverTime != null ? " · $serverTime" : ""}',
        );
      } else {
        await _log.actualizarUltimo(
          tipo         : SyncLogTipo.descarga,
          nuevoEstado  : SyncLogEstado.fallido,
          nuevoMensaje : 'Descarga fallida: $mensaje',
          detalle      : errores.isNotEmpty ? errores.toString() : null,
        );
      }

      return SyncResultadoDescarga(
        exitoso             : status == 'ok',
        mensaje             : mensaje,
        serverTime          : serverTime,
        adminOk             : adminOk,
        usuariosTraspasosOk : usuariosTraspasosOk,
        productosOk         : productosOk,
        datosCajaOk         : datosCajaOk,
        errores             : errores,
      );
    } catch (e) {
      await _log.actualizarUltimo(
        tipo         : SyncLogTipo.descarga,
        nuevoEstado  : SyncLogEstado.fallido,
        nuevoMensaje : 'Error al descargar',
        detalle      : e.toString(),
      );
      return SyncResultadoDescarga(exitoso: false, mensaje: 'Error al descargar: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SUBIDA
  // ──────────────────────────────────────────────────────────────────────────

  static Future<SyncResultadoSubida> subir() async {
    await _log.agregar(
      tipo    : SyncLogTipo.subida,
      estado  : SyncLogEstado.enProceso,
      mensaje : 'Verificando traspasos pendientes…',
    );

    try {
      final db        = DatabaseService();
      final traspasos = await db.getTraspasosPendientesConLineas();

      if (traspasos.isEmpty) {
        await _log.actualizarUltimo(
          tipo         : SyncLogTipo.subida,
          nuevoEstado  : SyncLogEstado.ok,
          nuevoMensaje : 'Sin traspasos pendientes',
        );
        return const SyncResultadoSubida(exitoso: true, mensaje: 'Sin pendientes');
      }

      await _log.actualizarUltimo(
        tipo         : SyncLogTipo.subida,
        nuevoEstado  : SyncLogEstado.enProceso,
        nuevoMensaje : 'Subiendo ${traspasos.length} traspasos…',
      );

      final uuidsPendientes =
          traspasos.map((t) => t['local_uuid'] as String).toList();

      final movimientos = <Map<String, dynamic>>[];
      final manucaAUuid = <String, String>{};

      // ── deviceId UNA sola vez fuera del loop ──
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

      final result = await ApiService.subirDatosRaw(movimientos);

      final status  = result['status']?.toString()  ?? 'error';
      final mensaje = result['message']?.toString()  ?? 'Sin respuesta';

      final resumen   = result['resumen']  as Map<String, dynamic>? ?? {};
      final resHmoval = resumen['hmoval']  as Map<String, dynamic>? ?? {};

      final insertados = (resHmoval['insertados'] ?? 0) as int;
      final omitidos   = (resHmoval['omitidos']   ?? 0) as int;
      final fallidos   = (resHmoval['fallidos']   ?? 0) as int;

      if (status == 'ok') {
        await _log.actualizarUltimo(
          tipo         : SyncLogTipo.subida,
          nuevoEstado  : (fallidos > 0)
              ? SyncLogEstado.fallido
              : (omitidos > 0 ? SyncLogEstado.omitido : SyncLogEstado.ok),
          nuevoMensaje : '↑ $insertados insertados · $omitidos omitidos · $fallidos errores',
          detalle      : 'Total movimientos: ${movimientos.length}',
        );
      } else {
        await _log.actualizarUltimo(
          tipo         : SyncLogTipo.subida,
          nuevoEstado  : SyncLogEstado.fallido,
          nuevoMensaje : 'Error del servidor: $mensaje',
        );
      }

      final omitidosDetalle = result['omitidos_detalle'] as List? ??
                              resumen['omitidos_detalle'] as List? ?? [];

      for (final d in omitidosDetalle) {
        if (d is! Map) continue;
        final manucaVal = d['manuca']?.toString() ?? '?';
        final motivo    = d['motivo']?.toString()  ?? d['razon']?.toString() ?? 'Sin motivo';
        final uuidAsoc  = manucaAUuid[manucaVal] ?? '';
        debugPrint('⚠ Omitido — manuca=$manucaVal | motivo=$motivo | uuid=$uuidAsoc');
        await _log.agregar(
          tipo    : SyncLogTipo.subida,
          estado  : SyncLogEstado.omitido,
          mensaje : 'Movimiento omitido — $motivo',
          detalle : 'línea=${d['manuml'] ?? '?'} | código=${d['macdpt'] ?? '?'}',
          uuid    : uuidAsoc,
          manuca  : manucaVal,
        );
      }

      final erroresList = result['errores'] as List? ?? [];
      for (final e in erroresList) {
        if (e is! Map) continue;
        final manucaVal = e['manuca']?.toString() ?? '?';
        final motivo    = e['motivo']?.toString()  ?? e['message']?.toString() ?? 'Error desconocido';
        debugPrint('❌ Fallido — manuca=$manucaVal | motivo=$motivo');
        await _log.agregar(
          tipo    : SyncLogTipo.subida,
          estado  : SyncLogEstado.fallido,
          mensaje : 'Registro fallido — $motivo',
          detalle : 'línea=${e['manuml'] ?? '?'} | código=${e['macdpt'] ?? '?'}',
          uuid    : manucaAUuid[manucaVal],
          manuca  : manucaVal,
        );
      }

      if (status == 'ok' && insertados > 0 && omitidos == 0 && fallidos == 0) {
        for (final entry in manucaAUuid.entries) {
          await _log.agregar(
            tipo    : SyncLogTipo.subida,
            estado  : SyncLogEstado.ok,
            mensaje : 'Traspaso sincronizado correctamente',
            uuid    : entry.value,
            manuca  : entry.key,
          );
        }
      }

      if (status == 'ok') {
        if (fallidos == 0 && omitidos == 0) {
          await db.marcarTraspasosSincronizados(uuidsPendientes);
          debugPrint('✅ ${uuidsPendientes.length} traspasos sincronizados');
        } else {
          final manucasOmitidas = omitidosDetalle
              .whereType<Map>()
              .map((d) => d['manuca']?.toString())
              .whereType<String>()
              .toSet();
          final manucasError = erroresList
              .whereType<Map>()
              .map((e) => e['manuca']?.toString())
              .whereType<String>()
              .toSet();
          final manucasProblema = {...manucasOmitidas, ...manucasError};

          final uuidsOk = manucaAUuid.entries
              .where((e) => !manucasProblema.contains(e.key))
              .map((e) => e.value)
              .toList();

          if (uuidsOk.isNotEmpty) {
            await db.marcarTraspasosSincronizados(uuidsOk);
            debugPrint('✅ ${uuidsOk.length} OK | ${manucasProblema.length} con problemas');
          }
        }
      }

      final erroresMap = <String, dynamic>{};
      if (result['errores'] is Map) {
        erroresMap.addAll(Map<String, dynamic>.from(result['errores'] as Map));
      }

      return SyncResultadoSubida(
        exitoso          : status == 'ok',
        mensaje          : mensaje,
        hmovalInsertados : insertados,
        hmovalOmitidos   : omitidos,
        hmovalFallidos   : fallidos,
        errores          : erroresMap,
      );
    } catch (e) {
      await _log.actualizarUltimo(
        tipo         : SyncLogTipo.subida,
        nuevoEstado  : SyncLogEstado.fallido,
        nuevoMensaje : 'Error al subir traspasos',
        detalle      : e.toString(),
      );
      return SyncResultadoSubida(exitoso: false, mensaje: 'Error al subir: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SINCRONIZACIÓN COMPLETA
  // ──────────────────────────────────────────────────────────────────────────

  static Future<({
    SyncResultadoDescarga descarga,
    SyncResultadoSubida subida,
    bool todoExitoso,
  })> sincronizarCompleto({String? stand}) async {
    if (_running) {
      return (
        descarga    : const SyncResultadoDescarga(exitoso: false, mensaje: 'Sync en curso'),
        subida      : const SyncResultadoSubida(exitoso: false, mensaje: 'Sync en curso'),
        todoExitoso : false,
      );
    }

    _running = true;

    await _log.agregar(
      tipo    : SyncLogTipo.sistema,
      estado  : SyncLogEstado.enProceso,
      mensaje : 'Iniciando sincronización automática…',
    );

    try {
      final descarga = await descargar(stand: stand);
      final subida   = await subir();
      final ok       = descarga.exitoso && subida.exitoso;

      await _log.actualizarUltimo(
        tipo         : SyncLogTipo.sistema,
        nuevoEstado  : ok ? SyncLogEstado.ok : SyncLogEstado.omitido,
        nuevoMensaje : ok ? 'Sincronización completada' : 'Sincronización con advertencias',
      );

      return (descarga: descarga, subida: subida, todoExitoso: ok);
    } catch (e) {
      await _log.actualizarUltimo(
        tipo         : SyncLogTipo.sistema,
        nuevoEstado  : SyncLogEstado.fallido,
        nuevoMensaje : 'Fallo en sincronización',
        detalle      : e.toString(),
      );
      rethrow;
    } finally {
      _running = false;
    }
  }
}