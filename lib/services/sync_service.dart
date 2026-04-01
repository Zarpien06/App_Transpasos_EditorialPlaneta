// lib/services/sync_service.dart

import 'package:flutter/foundation.dart';
import '../core/database_service.dart';
import 'api_service.dart';

class SyncResultadoDescarga {
  final bool exitoso;
  final String mensaje;
  final String? serverTime;
  final bool adminOk;
  final bool usuariosTraspasosOk;
  final bool productosOk;
  final Map<String, String> errores;

  const SyncResultadoDescarga({
    required this.exitoso,
    required this.mensaje,
    this.serverTime,
    this.adminOk = false,
    this.usuariosTraspasosOk = false,
    this.productosOk = false,
    this.errores = const {},
  });
}

class SyncResultadoSubida {
  final bool exitoso;
  final String mensaje;
  final int productosInsertados;
  final int productosOmitidos;
  final int hmovalOk;
  final int hmovalFail;
  final Map<String, dynamic> errores;

  const SyncResultadoSubida({
    required this.exitoso,
    required this.mensaje,
    this.productosInsertados = 0,
    this.productosOmitidos   = 0,
    this.hmovalOk            = 0,
    this.hmovalFail          = 0,
    this.errores             = const {},
  });
}

class SyncService {

  // ══════════════════════════════════════════════════════════
  // ⬇️ DESCARGAR — nube → local
  // Guarda admin y productos en SQLite para uso offline
  // ══════════════════════════════════════════════════════════
  static Future<SyncResultadoDescarga> descargar() async {
    try {
      final res = await ApiService.descargarDatos();

      final status     = res['status']      as String? ?? 'error';
      final mensaje    = res['message']     as String? ?? 'Sin respuesta';
      final serverTime = res['server_time'] as String?;
      final data       = res['data']        as Map<String, dynamic>? ?? {};
      final errores    = (res['errores']    as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString()));

      if (status == 'ok') {
        final db = DatabaseService();

        // ✅ Guardar credenciales admin en BD local
        final adminData = res['admin'] as Map<String, dynamic>?;
        if (adminData != null) {
          final usuario  = adminData['usuario']  as String? ?? '';
          final password = adminData['password'] as String? ?? '';
          if (usuario.isNotEmpty && password.isNotEmpty) {
            await db.guardarAdminLocal(usuario, password);
            debugPrint('✅ Admin guardado localmente: $usuario');
          }
        }

        // ✅ Guardar productos en BD local
        final productos = res['productos'] as List<dynamic>?;
        if (productos != null && productos.isNotEmpty) {
          await db.guardarProductos(
            productos.cast<Map<String, dynamic>>(),
          );
          debugPrint('✅ ${productos.length} productos guardados localmente');
        }
      }

      return SyncResultadoDescarga(
        exitoso:             status == 'ok',
        mensaje:             mensaje,
        serverTime:          serverTime,
        adminOk:             data['admin']               == 'ok',
        usuariosTraspasosOk: data['usuarios_transpasos'] == 'ok',
        productosOk:         data['productos']           == 'ok',
        errores:             errores,
      );
    } catch (e) {
      return SyncResultadoDescarga(
        exitoso: false,
        mensaje: 'Error al descargar: $e',
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  // ⬆️ SUBIR — local → nube
  // ══════════════════════════════════════════════════════════
  static Future<SyncResultadoSubida> subir() async {
    try {
      final res = await ApiService.subirDatos();

      final status  = res['status']  as String? ?? 'error';
      final mensaje = res['message'] as String? ?? 'Sin respuesta';
      final resumen = res['resumen'] as Map<String, dynamic>? ?? {};
      final errores = res['errores'] as Map<String, dynamic>? ?? {};

      return SyncResultadoSubida(
        exitoso:             status == 'ok',
        mensaje:             mensaje,
        productosInsertados: (resumen['productos_insertados'] as num?)?.toInt() ?? 0,
        productosOmitidos:   (resumen['productos_omitidos']   as num?)?.toInt() ?? 0,
        hmovalOk:            (resumen['hmoval_ok']            as num?)?.toInt() ?? 0,
        hmovalFail:          (resumen['hmoval_fail']          as num?)?.toInt() ?? 0,
        errores:             errores,
      );
    } catch (e) {
      return SyncResultadoSubida(
        exitoso: false,
        mensaje: 'Error al subir: $e',
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  // 🔄 COMPLETO
  // ══════════════════════════════════════════════════════════
  static Future<({
    SyncResultadoDescarga descarga,
    SyncResultadoSubida   subida,
    bool                  todoExitoso,
  })> sincronizarCompleto() async {
    final descarga = await descargar();
    final subida   = await subir();
    return (
      descarga:    descarga,
      subida:      subida,
      todoExitoso: descarga.exitoso && subida.exitoso,
    );
  }
}