// lib/services/data_usage_interceptor.dart
// ─────────────────────────────────────────────────────────────
// Interceptor de Dio que mide el consumo de datos de cada
// petición HTTP y lo registra en DataUsageService.
//
// INTEGRACIÓN en ApiService:
//   static final Dio _dio = Dio(BaseOptions(...))
//     ..interceptors.add(DataUsageInterceptor());   // ← agregar esta línea
//
// MEDICIÓN DE BYTES:
//   • Enviados  → longitud del body serializado (JSON string)
//   • Recibidos → longitud del body de respuesta serializado
//   • Ambos en UTF-8 bytes (aproximación precisa para JSON ASCII/latin1)
//
// OVERHEAD NO MEDIDO (intencional — bajo impacto):
//   • Headers HTTP (~200-500 bytes por request)
//   • TLS handshake
//   • TCP/IP framing
//   Estos representan < 2% del total en peticiones de datos reales.
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'data_usage_service.dart';

class DataUsageInterceptor extends Interceptor {
  // Marca de tiempo guardada al inicio de cada request
  // Clave: requestId (hashCode de la RequestOptions)
  final Map<int, int> _startTimes = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _startTimes[options.hashCode] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _registrar(
      options   : response.requestOptions,
      statusCode: response.statusCode ?? 0,
      respData  : response.data,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _registrar(
      options   : err.requestOptions,
      statusCode: err.response?.statusCode ?? 0,
      respData  : err.response?.data,
    );
    handler.next(err);
  }

  // ── Cálculo y registro ────────────────────────────────────────────────────

  void _registrar({
    required RequestOptions options,
    required int            statusCode,
    dynamic                 respData,
  }) {
    try {
      final inicio     = _startTimes.remove(options.hashCode) ??
                         DateTime.now().millisecondsSinceEpoch;
      final duracionMs = DateTime.now().millisecondsSinceEpoch - inicio;

      final bytesSent = _medirBytes(options.data);
      final bytesRecv = _medirBytes(respData);
      final proceso   = inferirProceso(options.uri.toString(), options.method);

      debugPrint(
        '📊 DataUsage: ${options.method} ${_shortUrl(options.uri.toString())} '
        '→ ↑${_fmt(bytesSent)} ↓${_fmt(bytesRecv)} '
        '${duracionMs}ms HTTP $statusCode',
      );

      // Registrar de forma asíncrona, sin bloquear la respuesta
      DataUsageService().registrar(
        proceso    : proceso,
        url        : options.uri.toString(),
        metodo     : options.method,
        bytesSent  : bytesSent,
        bytesRecv  : bytesRecv,
        duracionMs : duracionMs,
        statusCode : statusCode,
      );
    } catch (e) {
      debugPrint('⚠ DataUsageInterceptor._registrar: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Convierte cualquier tipo de dato Dio a bytes (aproximación UTF-8)
  static int _medirBytes(dynamic data) {
    if (data == null) return 0;
    try {
      if (data is String) {
        return utf8.encode(data).length;
      }
      if (data is List<int>) {
        return data.length;
      }
      // Map, List, etc. → serializar a JSON
      return utf8.encode(jsonEncode(data)).length;
    } catch (_) {
      return 0;
    }
  }

  static String _shortUrl(String url) {
    final uri  = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path.split('/').last;
    return path.isNotEmpty ? path : uri.host;
  }

  static String _fmt(int bytes) {
    if (bytes < 1024)    return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}