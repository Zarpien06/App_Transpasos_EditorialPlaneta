// lib/services/sync_service.dart

import 'dart:math';

import 'package:flutter/foundation.dart';
import '../core/database_service.dart';
import 'api_service.dart';
import 'sync_log_service.dart';

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
  final int sincronizados;
  final int pendientes;
  final Map<String, dynamic> errores;

  const SyncResultadoSubida({
    required this.exitoso,
    required this.mensaje,
    this.hmovalInsertados = 0,
    this.hmovalOmitidos = 0,
    this.hmovalFallidos = 0,
    this.sincronizados = 0,
    this.pendientes = 0,
    this.errores = const {},
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class SyncService {
  static final _log = SyncLogService();
  static bool _running = false;

  // Reintentos con backoff exponencial
  // Intentos: 0 ms → 2 s → 4 s → 8 s (cap 30 s)
  static const int _maxReintentos = 3;
  static const int _backoffBaseMs = 2000;
  static const int _backoffCapMs  = 30000;

  static Duration _backoffDelay(int intento) {
    final ms = min(_backoffBaseMs * pow(2, intento).toInt(), _backoffCapMs);
    return Duration(milliseconds: ms);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DESCARGA
  // ──────────────────────────────────────────────────────────────────────────

  static Future<SyncResultadoDescarga> descargar({String? stand}) async {
    await _log.agregar(
      tipo   : SyncLogTipo.descarga,
      estado : SyncLogEstado.enProceso,
      mensaje: 'Descargando datos desde la nube…',
    );

    try {
      final res = await ApiService.descargarDatos(stand: stand);

      final status     = res['status']?.toString()  ?? 'error';
      final mensaje    = res['message']?.toString()  ?? 'Sin respuesta';
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

        // ── Admin ──────────────────────────────────────────────────────────
        final admin = ApiService.getAdmin(res);
        if (admin != null) {
          final nick = admin['Nick_Usuario']?.toString().trim() ?? '';
          final pwd  = admin['Pwd_Usuario']?.toString().trim()  ?? '';
          if (nick.isNotEmpty) {
            await db.guardarAdminLocal(nick, pwd);
            adminOk = true;
            await _log.agregar(
              tipo   : SyncLogTipo.descarga,
              estado : SyncLogEstado.ok,
              mensaje: 'Admin sincronizado: $nick',
            );
          }
        }

        // ── Usuarios traspasos ─────────────────────────────────────────────
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
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.ok,
            mensaje: '${usuarios.length} usuarios de traspaso actualizados',
          );
        } else {
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.omitido,
            mensaje: 'Sin usuarios de traspaso en la respuesta',
          );
        }

        // ── Productos ─────────────────────────────────────────────────────
        final productos = ApiService.getProductos(res);
        if (productos.isNotEmpty) {
          await db.guardarProductos(productos);
          productosOk = true;
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.ok,
            mensaje: '${productos.length} productos sincronizados',
          );
        } else {
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.omitido,
            mensaje: 'Sin productos en la respuesta del servidor',
          );
        }

        // ── Datos caja ────────────────────────────────────────────────────
        final datosCaja = ApiService.getDatosCaja(res);
        if (datosCaja.isNotEmpty) {
          datosCajaOk = true;
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.ok,
            mensaje: '${datosCaja.length} datos de caja recibidos',
          );
        }

        // ── Errores del servidor ───────────────────────────────────────────
        for (final entry in errores.entries) {
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.fallido,
            mensaje: 'Error servidor [${entry.key}]',
            detalle: entry.value,
          );
        }

        await _log.actualizarUltimo(
          tipo        : SyncLogTipo.descarga,
          nuevoEstado : SyncLogEstado.ok,
          nuevoMensaje: 'Descarga completada'
              '${serverTime != null ? " · $serverTime" : ""}',
        );
      } else {
        await _log.actualizarUltimo(
          tipo        : SyncLogTipo.descarga,
          nuevoEstado : SyncLogEstado.fallido,
          nuevoMensaje: 'Descarga fallida: $mensaje',
          detalle     : errores.isNotEmpty ? errores.toString() : null,
        );
      }

      return SyncResultadoDescarga(
        exitoso            : status == 'ok',
        mensaje            : mensaje,
        serverTime         : serverTime,
        adminOk            : adminOk,
        usuariosTraspasosOk: usuariosTraspasosOk,
        productosOk        : productosOk,
        datosCajaOk        : datosCajaOk,
        errores            : errores,
      );
    } catch (e) {
      await _log.actualizarUltimo(
        tipo        : SyncLogTipo.descarga,
        nuevoEstado : SyncLogEstado.fallido,
        nuevoMensaje: 'Error al descargar',
        detalle     : e.toString(),
      );
      return SyncResultadoDescarga(
        exitoso: false,
        mensaje: 'Error al descargar: $e',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SUBIDA — delega totalmente en ApiService.subirDatos()
  //
  // FIX: ya no construye movimientos aquí. subirDatos() tiene los lotes,
  // el FIX 3 (batch de _tamanoLote traspasos) y el FIX 4 (omitidos no
  // bloquean la marca como sincronizado). Este método solo agrega:
  //   • verificación de pendientes antes de llamar
  //   • backoff exponencial en caso de error de red
  //   • logging en SyncLogService
  // ──────────────────────────────────────────────────────────────────────────

  static Future<SyncResultadoSubida> subir() async {
    await _log.agregar(
      tipo   : SyncLogTipo.subida,
      estado : SyncLogEstado.enProceso,
      mensaje: 'Verificando traspasos pendientes…',
    );

    try {
      final db        = DatabaseService();
      final traspasos = await db.getTraspasosPendientesConLineas();

      if (traspasos.isEmpty) {
        await _log.actualizarUltimo(
          tipo        : SyncLogTipo.subida,
          nuevoEstado : SyncLogEstado.ok,
          nuevoMensaje: 'Sin traspasos pendientes',
        );
        return const SyncResultadoSubida(
          exitoso: true,
          mensaje: 'Sin pendientes',
        );
      }

      await _log.actualizarUltimo(
        tipo        : SyncLogTipo.subida,
        nuevoEstado : SyncLogEstado.enProceso,
        nuevoMensaje: 'Subiendo ${traspasos.length} traspasos…',
      );

      // ── Backoff exponencial ───────────────────────────────────────────────
      Map<String, dynamic>? result;
      for (var intento = 0; intento <= _maxReintentos; intento++) {
        if (intento > 0) {
          final delay = _backoffDelay(intento - 1);
          debugPrint(
            '⏳ Reintento $intento/$_maxReintentos — '
            'esperando ${delay.inSeconds}s…',
          );
          await Future<void>.delayed(delay);
        }

        result = await ApiService.subirDatos();

        if (result['status'] == 'ok' || result['status'] == 'partial') {
          // éxito total o parcial: no reintentar
          break;
        }

        debugPrint(
          '⚠ subirDatos() → ${result['status']}: ${result['message']}',
        );

        if (intento == _maxReintentos) {
          debugPrint('❌ Máximo de reintentos alcanzado.');
        }
      }

      final res = result!;
      final status  = res['status']?.toString()  ?? 'error';
      final mensaje = res['message']?.toString()  ?? 'Sin respuesta';

      final resHmoval = (res['resumen']?['hmoval'] as Map<String, dynamic>?) ?? {};
      final insertados   = (resHmoval['insertados'] ?? 0) as int;
      final omitidos     = (resHmoval['omitidos']   ?? 0) as int;
      final fallidos     = (resHmoval['fallidos']   ?? 0) as int;
      final sincronizados = (res['sincronizados']   ?? 0) as int;
      final pendientes    = (res['pendientes']      ?? 0) as int;

      if (status == 'ok' || status == 'partial') {
        await _log.actualizarUltimo(
          tipo        : SyncLogTipo.subida,
          nuevoEstado : fallidos > 0
              ? SyncLogEstado.fallido
              : (omitidos > 0 ? SyncLogEstado.omitido : SyncLogEstado.ok),
          nuevoMensaje: '↑ $insertados insertados · '
              '$omitidos omitidos · $fallidos errores',
          detalle     : 'Sincronizados: $sincronizados | '
              'Pendientes: $pendientes',
        );
      } else {
        await _log.actualizarUltimo(
          tipo        : SyncLogTipo.subida,
          nuevoEstado : SyncLogEstado.fallido,
          nuevoMensaje: 'Error del servidor: $mensaje',
        );
      }

      return SyncResultadoSubida(
        exitoso         : status == 'ok' || status == 'partial',
        mensaje         : mensaje,
        hmovalInsertados: insertados,
        hmovalOmitidos  : omitidos,
        hmovalFallidos  : fallidos,
        sincronizados   : sincronizados,
        pendientes      : pendientes,
      );
    } catch (e) {
      await _log.actualizarUltimo(
        tipo        : SyncLogTipo.subida,
        nuevoEstado : SyncLogEstado.fallido,
        nuevoMensaje: 'Error al subir traspasos',
        detalle     : e.toString(),
      );
      return SyncResultadoSubida(
        exitoso: false,
        mensaje: 'Error al subir: $e',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SINCRONIZACIÓN COMPLETA
  //
  // [soloSubida]: si true, omite la descarga cuando solo quieres vaciar
  // la cola de pendientes sin gastar ancho de banda en el GET de descarga.
  // Útil al llamar desde registrarTraspaso() justo después de guardar.
  // ──────────────────────────────────────────────────────────────────────────

  static Future<({
    SyncResultadoDescarga? descarga,
    SyncResultadoSubida subida,
    bool todoExitoso,
  })> sincronizarCompleto({
    String? stand,
    bool soloSubida = false,
  }) async {
    if (_running) {
      const bloqueado = SyncResultadoSubida(
        exitoso: false,
        mensaje: 'Sync en curso',
      );
      return (
        descarga   : soloSubida
            ? null
            : const SyncResultadoDescarga(
                exitoso: false,
                mensaje: 'Sync en curso',
              ),
        subida     : bloqueado,
        todoExitoso: false,
      );
    }

    _running = true;

    await _log.agregar(
      tipo   : SyncLogTipo.sistema,
      estado : SyncLogEstado.enProceso,
      mensaje: soloSubida
          ? 'Iniciando subida rápida…'
          : 'Iniciando sincronización completa…',
    );

    try {
      SyncResultadoDescarga? descarga;

      if (!soloSubida) {
        descarga = await descargar(stand: stand);
      }

      final subida = await subir();
      final ok     = (descarga?.exitoso ?? true) && subida.exitoso;

      await _log.actualizarUltimo(
        tipo        : SyncLogTipo.sistema,
        nuevoEstado : ok
            ? SyncLogEstado.ok
            : SyncLogEstado.omitido,
        nuevoMensaje: ok
            ? 'Sincronización completada'
            : 'Sincronización con advertencias',
      );

      return (descarga: descarga, subida: subida, todoExitoso: ok);
    } catch (e) {
      await _log.actualizarUltimo(
        tipo        : SyncLogTipo.sistema,
        nuevoEstado : SyncLogEstado.fallido,
        nuevoMensaje: 'Fallo en sincronización',
        detalle     : e.toString(),
      );
      rethrow;
    } finally {
      _running = false;
    }
  }
}