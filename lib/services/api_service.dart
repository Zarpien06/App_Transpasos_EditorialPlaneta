// lib/services/api_service.dart
// ─────────────────────────────────────────────────────────────
// API SERVICE - DIO (SYNC NUBE MÓVIL)
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  // ─────────────────────────────────────────────────────────────
  // BASE URLS
  // ─────────────────────────────────────────────────────────────
  static const String _baseUrl =
      'https://prologics.co/app_planeta_pruebas/controlador';

  static const String urlDescargar =
      '$_baseUrl/descarga_datos_nube.php';
  static const String urlSubir =
      '$_baseUrl/subir_datos_nube_app.php';

  // ─────────────────────────────────────────────────────────────
  // DIO GLOBAL
  // ─────────────────────────────────────────────────────────────
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // ─────────────────────────────────────────────────────────────
  // MÉTODO BASE REUTILIZABLE (CORREGIDO)
  // ─────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> _handleRequest(
    Future<Response> request,
  ) async {
    try {
      final response = await request;
      dynamic data = response.data;

      // DEBUG (puedes quitar luego)
      if (kDebugMode) {
        debugPrint('RESPONSE DATA: $data');
        debugPrint('TYPE: ${data.runtimeType}');
      }

      // 🟢 Si viene como String (muy común en PHP)
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          return {
            'status': 'ok',
            'data': data,
          };
        }
      }

      // 🟢 Si es MAP (lo ideal)
      if (data is Map<String, dynamic>) {
        return data;
      }

      // 🟢 Si es LISTA
      if (data is List) {
        return {
          'status': 'ok',
          'data': data,
        };
      }

      // ❌ Caso raro
      return {
        'status': 'error',
        'message': 'Formato de respuesta no válido',
      };
    } on DioException catch (e) {
      return {
        'status': 'error',
        'message': _parseDioError(e),
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Error inesperado: $e',
      };
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PARSEAR ERRORES DE DIO (MEJORADO)
  // ─────────────────────────────────────────────────────────────
  static String _parseDioError(DioException e) {
    try {
      final data = e.response?.data;

      if (data is Map<String, dynamic>) {
        return data['message']?.toString() ?? 'Error del servidor';
      }

      if (data is String) {
        return data;
      }

      return e.message ?? 'Error de conexión';
    } catch (_) {
      return 'Error de conexión';
    }
  }

  // ══════════════════════════════════════════════════════════
  // ☁️ DESCARGAR DATOS
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> descargarDatos() {
    return _handleRequest(_dio.get(urlDescargar));
  }

  // ══════════════════════════════════════════════════════════
  // ⬆️ SUBIR DATOS
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> subirDatos() {
    return _handleRequest(_dio.get(urlSubir));
  }

  // ══════════════════════════════════════════════════════════
  // 🟢 USUARIO
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> validarUsuario(String clave) {
    return _handleRequest(
      _dio.post(
        '$_baseUrl/utils.php',
        data: {'clave': clave},
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 📚 LIBROS
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> buscarLibro(String codigo) {
    return _handleRequest(
      _dio.post(
        '$_baseUrl/buscar_libro.php',
        data: {'codigo': codigo},
      ),
    );
  }

  static Future<Map<String, dynamic>> guardarLibro({
    required String ean,
    required String ref,
    required String descripcion,
  }) {
    return _handleRequest(
      _dio.post(
        '$_baseUrl/buscar_libro.php',
        data: {
          'guardar': true,
          'ean': ean,
          'ref': ref,
          'descripcion': descripcion,
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 🔄 TRASPASOS
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> registrarTraspaso(
      Map<String, dynamic> data) {
    return _handleRequest(
      _dio.post('$_baseUrl/utils.php', data: data),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 🔐 ADMIN LOGIN
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> adminLogin({
  required String nick,
  required String pwd,
}) {
  return _handleRequest(
    _dio.post(
      '$_baseUrl/login.php',
      data: {
        'usuario': nick,   // 👈 CAMBIO CLAVE
        'password': pwd,   // 👈 CAMBIO CLAVE
      },
    ),
  );
}

  
  // ══════════════════════════════════════════════════════════
  // ☁️ SYNC ADMIN
  // ══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> getSyncPendientes() {
    return _handleRequest(
      _dio.get('$_baseUrl/admin_sync.php'),
    );
  }

  static Future<Map<String, dynamic>> marcarSincronizadoHmoval(
      List<int> numMovimientos) {
    return _handleRequest(
      _dio.post(
        '$_baseUrl/admin_sync.php',
        data: {
          'accion': 'marcar_hmoval',
          'num_movimientos': numMovimientos,
        },
      ),
    );
  }

  static Future<Map<String, dynamic>> marcarSincronizadoFacturas() {
    return _handleRequest(
      _dio.post(
        '$_baseUrl/admin_sync.php',
        data: {'accion': 'marcar_mcabfa'},
      ),
    );
  }
}