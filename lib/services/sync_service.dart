// lib/services/sync_service.dart

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import '../core/connectivity_service.dart';
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
// FUNCIONES TOP-LEVEL PARA compute()
//
// OPT: compute() requiere funciones top-level (fuera de clase) porque las
// pasa a un isolate separado. El isolate no comparte memoria con el hilo
// principal, por eso no pueden ser métodos de instancia ni estáticos.
//
// Estas tres funciones mueven el parseo de listas grandes (2.3 MB de JSON)
// fuera del hilo de UI, eliminando los 308 frames saltados del log.
// ─────────────────────────────────────────────────────────────────────────────

/// Extrae la lista de productos del mapa de respuesta del servidor.
/// Se ejecuta en un isolate separado vía compute().
List<Map<String, dynamic>> _extraerProductos(Map<String, dynamic> res) {
  return ApiService.getProductos(res);
}

/// Extrae la lista de usuarios del mapa de respuesta del servidor.
/// Se ejecuta en un isolate separado vía compute().
List<Map<String, dynamic>> _extraerUsuarios(Map<String, dynamic> res) {
  final usuariosRaw = res['data']?['usuarios_transpasos'];
  if (usuariosRaw is List) {
    return usuariosRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (usuariosRaw is Map) {
    return [Map<String, dynamic>.from(usuariosRaw)];
  }
  return [];
}

/// Extrae la lista de datos de caja del mapa de respuesta del servidor.
/// Se ejecuta en un isolate separado vía compute().
List<Map<String, dynamic>> _extraerDatosCaja(Map<String, dynamic> res) {
  return ApiService.getDatosCaja(res);
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class SyncService {
  static final _log = SyncLogService();

  // FIX: Lock único que serializa TODOS los accesos concurrentes a la DB.
  // Los bool simples anteriores NO eran atómicos en Dart async — dos timers
  // podían leer _subidaEnCurso = false en el mismo frame y entrar juntos,
  // generando el warning "database has been locked for 0:00:10.000000".
  // Con Lock de 'synchronized', solo una operación entra a la vez; las demás
  // ven locked = true y se saltan ese tick en lugar de esperar en cola.
  static final Lock _syncLock = Lock();

  // Solo para consulta de la UI (no se usan como guard de concurrencia).
  static bool _subidaEnCurso   = false;
  static bool _descargaEnCurso = false;

  // Getters públicos — permiten que la UI consulte el estado del sync
  // y eliminan el warning "unused_field" del analizador de Dart.
  static bool get subidaEnCurso   => _subidaEnCurso;
  static bool get descargaEnCurso => _descargaEnCurso;

  // ── Timers ────────────────────────────────────────────────────────────────
  // • _timerSubida        : cada 30 s  → solo sube traspasos pendientes
  // • _timerHash          : cada 30 s  → consulta ?solo=hash (80 bytes)
  //                         Si hash cambió → descarga ?solo=productos (2.4 MB)
  //                         Si hash igual  → no descarga nada
  // • _timerAdminUsuarios : cada 15 min → descarga admin + usuarios
  //
  // _timerProductos fue eliminado. El timer de hash lo reemplaza con un
  // consumo radicalmente menor: 80 bytes × 2880 ticks = ~230 KB/día
  // en vez de 2.4 MB × 30 ticks = ~72 MB/día cuando no hay cambios.
  static Timer? _timerSubida;
  static Timer? _timerHash;
  static Timer? _timerAdminUsuarios;
  static String? _autoSyncStand;

  // Hash del catálogo de productos conocido por este dispositivo.
  // null = no se ha consultado aún (fuerza descarga al primer tick).
  static String? _hashActual;

  // Instancia de ConnectivityService reutilizada (no crea nueva cada tick).
  static final _connectivity = ConnectivityService();

  // ─────────────────────────────────────────────────────────────────────────
  // INICIAR AUTO-SYNC (idempotente)
  // ─────────────────────────────────────────────────────────────────────────

  /// Arranca los timers en background.
  /// Llamar una sola vez desde main.dart después del splash.
  /// La descarga inicial completa ya la hace el splash; aquí solo
  /// guardamos el hash inicial y arrancamos los timers.
  static Future<void> iniciarAutoSync({String? stand}) async {
    _autoSyncStand = stand;

    // ── Descarga completa al arrancar + hash inicial ───────────────────────
    // Garantiza que el catálogo es fresco desde el primer segundo y que
    // _hashActual queda inicializado antes de que arranquen los timers.
    await _descargarYActualizarHash(stand: stand, esArranque: true);

    // ── Timer subida: cada 30 segundos ────────────────────────────────────
    if (!(_timerSubida?.isActive ?? false)) {
      debugPrint('⬆ Auto-sync subida iniciado (cada 30 s)');

      _timerSubida = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (_syncLock.locked) return;

        final db = DatabaseService();
        final pendientesTraspasos = await db.contarPendientes();
        final pendientesProductos = await _contarProductosPendientes(db);

        if (pendientesTraspasos == 0 && pendientesProductos == 0) return;

        final hayInternet = await ApiService.hayInternetReal();
        if (!hayInternet) {
          debugPrint(
            '📵 Auto-sync subida: sin internet '
            '($pendientesTraspasos traspasos, $pendientesProductos productos pendientes)',
          );
          await _log.agregar(
            tipo   : SyncLogTipo.subida,
            estado : SyncLogEstado.omitido,
            mensaje: 'Sin internet — subida omitida '
                '($pendientesTraspasos traspasos)',
          );
          return;
        }

        await _syncLock.synchronized(() async {
          _subidaEnCurso = true;
          debugPrint(
            '⬆ Auto-sync subida: ejecutando… '
            '($pendientesTraspasos traspasos, $pendientesProductos productos)',
          );
          try {
            if (pendientesTraspasos > 0) await subir();
            if (pendientesProductos > 0) await subirProductosPendientes();
            debugPrint('✅ Auto-sync subida: completada');
          } catch (e) {
            debugPrint('⚠ Auto-sync subida: error — $e');
          } finally {
            _subidaEnCurso = false;
          }
        });
      });
    }

    // ── Timer hash: cada 30 segundos ──────────────────────────────────────
    if (!(_timerHash?.isActive ?? false)) {
      debugPrint('🔍 Auto-sync hash iniciado (cada 30 s)');

      _timerHash = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (_syncLock.locked) return;

        final hayConexion = await _connectivity.checkOnline();
        if (!hayConexion) {
          debugPrint('📵 Auto-sync hash: sin conexión, omitiendo');
          return;
        }

        await _syncLock.synchronized(() async {
          _descargaEnCurso = true;
          try {
            await _verificarHashYDescargarSiCambio();
          } finally {
            _descargaEnCurso = false;
          }
        });
      });
    }

    // ── Timer admin + usuarios: cada 15 minutos ───────────────────────────
    if (!(_timerAdminUsuarios?.isActive ?? false)) {
      debugPrint('⬇ Auto-sync admin+usuarios iniciado (cada 15 min)');

      _timerAdminUsuarios =
          Timer.periodic(const Duration(minutes: 15), (_) async {
        if (_syncLock.locked) return;

        final hayConexion = await _connectivity.checkOnline();
        if (!hayConexion) {
          debugPrint('📵 Auto-sync admin+usuarios: sin conexión, omitiendo');
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.omitido,
            mensaje: 'Sin conexión — descarga admin+usuarios omitida',
          );
          return;
        }

        await _syncLock.synchronized(() async {
          _descargaEnCurso = true;
          debugPrint(
            '⬇ Auto-sync admin+usuarios: descargando ?solo=admin y ?solo=usuarios…',
          );
          try {
            await descargar(stand: _autoSyncStand, solo: 'admin');
            await descargar(stand: _autoSyncStand, solo: 'usuarios');
            debugPrint('✅ Auto-sync admin+usuarios: completada');
          } catch (e) {
            debugPrint('⚠ Auto-sync admin+usuarios: error — $e');
          } finally {
            _descargaEnCurso = false;
          }
        });
      });
    }
  }

  /// Detiene todos los timers.
  static void detenerAutoSync() {
    _timerSubida?.cancel();
    _timerSubida = null;
    _timerHash?.cancel();
    _timerHash = null;
    _timerAdminUsuarios?.cancel();
    _timerAdminUsuarios = null;
    debugPrint('⏹ Auto-sync detenido');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VERIFICAR HASH Y DESCARGAR SI CAMBIÓ  (privado)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> _verificarHashYDescargarSiCambio() async {
    try {
      final res = await ApiService.descargarDatos(solo: 'hash');

      if (res['status'] != 'ok') {
        debugPrint('⚠ Hash: respuesta no ok — ${res['message']}');
        return false;
      }

      final hashServidor = res['hash']?.toString();
      if (hashServidor == null || hashServidor.isEmpty) {
        debugPrint('⚠ Hash: respuesta sin campo hash');
        return false;
      }

      if (hashServidor == _hashActual) {
        debugPrint('🔵 Hash igual ($_hashActual) — sin cambios en catálogo');
        return false;
      }

      debugPrint(
        '🟡 Hash cambió: '
        'local=$_hashActual | servidor=$hashServidor → descargando productos…',
      );

      final resultado = await descargar(
        stand: _autoSyncStand,
        solo : 'productos',
      );

      if (resultado.exitoso && resultado.productosOk) {
        _hashActual = hashServidor;
        debugPrint('✅ Hash actualizado a $hashServidor — catálogo sincronizado');
        return true;
      } else {
        debugPrint(
          '⚠ Descarga de productos falló — hash NO actualizado, '
          'se reintentará en el próximo tick',
        );
        return false;
      }
    } catch (e) {
      debugPrint('⚠ _verificarHashYDescargarSiCambio: error — $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VERIFICAR Y DESCARGAR SI CAMBIÓ  (público — llamado desde lineas_screen)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> verificarYDescargarSiCambio() async {
    if (_syncLock.locked) {
      debugPrint('⏳ verificarYDescargarSiCambio: sync en curso, esperando…');
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!_syncLock.locked) break;
      }
      return !_syncLock.locked;
    }

    final hayConexion = await _connectivity.checkOnline();
    if (!hayConexion) {
      debugPrint('📵 verificarYDescargarSiCambio: sin internet');
      return false;
    }

    return await _syncLock.synchronized(() async {
      _descargaEnCurso = true;
      try {
        return await _verificarHashYDescargarSiCambio();
      } finally {
        _descargaEnCurso = false;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DESCARGA COMPLETA + HASH INICIAL
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _descargarYActualizarHash({
    String? stand,
    bool esArranque = false,
  }) async {
    final hayConexion = await _connectivity.checkOnline();
    if (!hayConexion) {
      debugPrint(
        '📵 ${esArranque ? "Arranque" : "Reconexión"}: sin internet, '
        'usando catálogo local existente',
      );
      return;
    }

    debugPrint(
      '⬇ ${esArranque ? "Arranque" : "Reconexión"}: '
      'descargando catálogo completo…',
    );

    await _syncLock.synchronized(() async {
      _descargaEnCurso = true;
      try {
        await descargar(stand: stand, solo: 'todo');

        final res = await ApiService.descargarDatos(solo: 'hash');
        if (res['status'] == 'ok') {
          _hashActual = res['hash']?.toString();
          debugPrint('🔵 Hash inicial guardado: $_hashActual');
        }
      } catch (e) {
        debugPrint('⚠ ${esArranque ? "Arranque" : "Reconexión"}: error — $e');
      } finally {
        _descargaEnCurso = false;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AL RECONECTAR
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> onReconexion() async {
    debugPrint('📶 Reconexión detectada — consultando hash inmediatamente…');
    if (_syncLock.locked) return;

    await _syncLock.synchronized(() async {
      _descargaEnCurso = true;
      try {
        await _verificarHashYDescargarSiCambio();
      } finally {
        _descargaEnCurso = false;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS PRIVADOS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<int> _contarProductosPendientes(DatabaseService db) async {
    final raw = await (await db.database).rawQuery(
      'SELECT COUNT(*) as total FROM productos_local WHERE pendiente_sync = 1',
    );
    return (raw.first['total'] as int?) ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BACKOFF EXPONENCIAL
  // ─────────────────────────────────────────────────────────────────────────

  static const int _maxReintentos = 3;
  static const int _backoffBaseMs = 2000;
  static const int _backoffCapMs  = 30000;

  static Duration _backoffDelay(int intento) {
    final ms = min(_backoffBaseMs * pow(2, intento).toInt(), _backoffCapMs);
    return Duration(milliseconds: ms);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DESCARGA
  // ─────────────────────────────────────────────────────────────────────────

  static Future<SyncResultadoDescarga> descargar({
    String? stand,
    String solo = 'todo',
  }) async {
    await _log.agregar(
      tipo   : SyncLogTipo.descarga,
      estado : SyncLogEstado.enProceso,
      mensaje: solo == 'todo'
          ? 'Descargando datos desde la nube…'
          : 'Descargando ?solo=$solo desde la nube…',
    );

    try {
      final res = await ApiService.descargarDatos(stand: stand, solo: solo);

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
        // OPT: compute() mueve el parseo al isolate — libera el hilo de UI.
        final usuarios = await compute(_extraerUsuarios, res);

        if (usuarios.isNotEmpty) {
          await db.guardarUsuariosTranspasos(usuarios);
          usuariosTraspasosOk = true;
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.ok,
            mensaje: '${usuarios.length} usuarios de traspaso actualizados',
          );
        } else if (solo == 'usuarios' || solo == 'todo') {
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.omitido,
            mensaje: 'Sin usuarios de traspaso en la respuesta',
          );
        }

        // ── Productos ─────────────────────────────────────────────────────
        // OPT: compute() es el cambio más importante — parsear 2.3 MB de JSON
        // en el hilo principal causaba los 308 frames saltados del log.
        // Ahora corre en un isolate separado; la UI queda completamente libre.
        final productos = await compute(_extraerProductos, res);

        if (productos.isNotEmpty) {
          await db.guardarProductos(productos);
          productosOk = true;
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.ok,
            mensaje: '${productos.length} productos sincronizados',
          );
        } else if (solo == 'productos' || solo == 'todo') {
          await _log.agregar(
            tipo   : SyncLogTipo.descarga,
            estado : SyncLogEstado.omitido,
            mensaje: 'Sin productos en la respuesta del servidor',
          );
        }

        // ── Datos caja ────────────────────────────────────────────────────
        // OPT: también en isolate para consistencia.
        final datosCaja = await compute(_extraerDatosCaja, res);
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

  // ─────────────────────────────────────────────────────────────────────────
  // SUBIDA
  // ─────────────────────────────────────────────────────────────────────────

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

        if (result['status'] == 'ok' || result['status'] == 'partial') break;

        debugPrint('⚠ subirDatos() → ${result['status']}: ${result['message']}');

        if (intento == _maxReintentos) {
          debugPrint('❌ Máximo de reintentos alcanzado.');
        }
      }

      final res     = result!;
      final status  = res['status']?.toString()  ?? 'error';
      final mensaje = res['message']?.toString()  ?? 'Sin respuesta';

      final resHmoval     = (res['resumen']?['hmoval'] as Map<String, dynamic>?) ?? {};
      final insertados    = (resHmoval['insertados'] ?? 0) as int;
      final omitidos      = (resHmoval['omitidos']   ?? 0) as int;
      final fallidos      = (resHmoval['fallidos']   ?? 0) as int;
      final sincronizados = (res['sincronizados']    ?? 0) as int;
      final pendientes    = (res['pendientes']       ?? 0) as int;

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

  // ─────────────────────────────────────────────────────────────────────────
  // SUBIR PRODUCTOS PENDIENTES (creados offline)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> subirProductosPendientes() async {
    final db  = DatabaseService();
    final raw = await (await db.database).query(
      'productos_local',
      where  : 'pendiente_sync = 1',
      orderBy: 'id ASC',
    );

    if (raw.isEmpty) return;

    debugPrint('📦 Productos pendientes de subir: ${raw.length}');

    for (final p in raw) {
      final ean    = p['EAN']?.toString()             ?? '';
      final desc   = p['Desc_Referencia']?.toString() ?? '';
      final precio = (p['Precio'] as num?)?.toDouble() ?? 0;

      if (ean.isEmpty) continue;

      try {
        final result = await ApiService.agregarProducto(
          ean           : ean,
          descReferencia: desc,
          precio        : precio,
        );

        if (result['status'] == 'ok' && result['modo'] != 'offline') {
          await (await db.database).update(
            'productos_local',
            {'pendiente_sync': 0},
            where    : 'EAN = ?',
            whereArgs: [ean],
          );
          debugPrint('✅ Producto sincronizado: $desc');
        } else {
          debugPrint(
            '⚠ Producto no sincronizado (reintentará): '
            '$desc — ${result['message']}',
          );
        }
      } catch (e) {
        debugPrint('⚠ Error subiendo producto $ean: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SINCRONIZACIÓN COMPLETA (descarga + subida, para llamada manual)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<({
    SyncResultadoDescarga? descarga,
    SyncResultadoSubida subida,
    bool todoExitoso,
  })> sincronizarCompleto({
    String? stand,
    bool soloSubida = false,
    String solo = 'todo',
  }) async {
    if (_syncLock.locked) {
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

    await _log.agregar(
      tipo   : SyncLogTipo.sistema,
      estado : SyncLogEstado.enProceso,
      mensaje: soloSubida
          ? 'Iniciando subida rápida…'
          : 'Iniciando sincronización completa…',
    );

    return await _syncLock.synchronized(() async {
      _subidaEnCurso   = true;
      _descargaEnCurso = !soloSubida;

      try {
        SyncResultadoDescarga? descarga;

        if (!soloSubida) {
          descarga = await descargar(stand: stand, solo: solo);

          if (descarga.exitoso && (solo == 'todo' || solo == 'productos')) {
            final resHash = await ApiService.descargarDatos(solo: 'hash');
            if (resHash['status'] == 'ok') {
              _hashActual = resHash['hash']?.toString();
              debugPrint('🔵 Hash actualizado tras sync manual: $_hashActual');
            }
          }
        }

        final subida = await subir();
        await subirProductosPendientes();

        final ok = (descarga?.exitoso ?? true) && subida.exitoso;

        await _log.actualizarUltimo(
          tipo        : SyncLogTipo.sistema,
          nuevoEstado : ok ? SyncLogEstado.ok : SyncLogEstado.omitido,
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
        _subidaEnCurso   = false;
        _descargaEnCurso = false;
      }
    });
  }
}