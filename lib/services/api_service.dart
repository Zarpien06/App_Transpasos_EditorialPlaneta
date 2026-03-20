import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://192.168.137.1/api';
  static const Duration _timeout = Duration(seconds: 10);

  // ── Validar usuario ───────────────────────────────────────────
  static Future<Map<String, dynamic>> validarUsuario(String clave) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/validar_usuario.php'),
        body: {'clave': clave},
      ).timeout(_timeout);
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': 'error', 'mensaje': 'Error de conexión con el servidor'};
    }
  }

  // ── Buscar libro (EAN o Referencia) ───────────────────────────
  static Future<Map<String, dynamic>> buscarLibro(String codigo) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/buscar_libro.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'codigo': codigo}),
      ).timeout(_timeout);
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': 'error', 'mensaje': 'Error al buscar el libro'};
    }
  }

  // ── Guardar libro nuevo en BD ─────────────────────────────────
  static Future<Map<String, dynamic>> guardarLibro({
    required String ean,
    required String ref,
    required String descripcion,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/buscar_libro.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'guardar':     true,
          'ean':         ean,
          'ref':         ref,
          'descripcion': descripcion,
        }),
      ).timeout(_timeout);
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': 'error', 'mensaje': 'Error al guardar el libro'};
    }
  }

  // ── Registrar traspaso ────────────────────────────────────────
  static Future<Map<String, dynamic>> registrarTraspaso(
      Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/traspaso.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body);
    } catch (e) {
      return {'status': 'error', 'mensaje': 'Error al registrar el traspaso'};
    }
  }
}