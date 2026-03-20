import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "http://192.168.137.1/api";

  /// 🔥 VALIDAR USUARIO
  static Future<Map<String, dynamic>> validarUsuario(String clave) async {
    try {
      debugPrint("🔵 VALIDANDO USUARIO...");
      debugPrint("📤 CLAVE ENVIADA: $clave");

      final res = await http.post(
        Uri.parse("$baseUrl/validar_usuario.php"),
        body: {"clave": clave},
      ).timeout(const Duration(seconds: 10));

      debugPrint("📥 RESPUESTA CRUDA: ${res.body}");

      final data = jsonDecode(res.body);

      return data;
    } catch (e) {
      debugPrint("❌ ERROR VALIDAR USUARIO: $e");

      return {
        "status": "error",
        "mensaje": "Error de conexión con el servidor"
      };
    }
  }

  /// 🔥 BUSCAR LIBRO
  static Future<Map<String, dynamic>> buscarLibro(String codigo) async {
    try {
      debugPrint("🔵 BUSCANDO LIBRO...");
      debugPrint("📤 CÓDIGO ENVIADO: $codigo");

      final res = await http.post(
        Uri.parse("$baseUrl/buscar_libro.php"),
        body: {"codigo": codigo},
      ).timeout(const Duration(seconds: 10));

      debugPrint("📥 RESPUESTA LIBRO: ${res.body}");

      return jsonDecode(res.body);
    } catch (e) {
      debugPrint("❌ ERROR BUSCAR LIBRO: $e");

      return {
        "status": "error",
        "mensaje": "Error al buscar el libro"
      };
    }
  }

  /// 🔥 REGISTRAR TRASPASO
  static Future<Map<String, dynamic>> registrarTraspaso(
      Map<String, dynamic> data) async {
    try {
      debugPrint("🔵 REGISTRANDO TRASPASO...");
      debugPrint("📤 DATA ENVIADA: ${jsonEncode(data)}");

      final res = await http.post(
        Uri.parse("$baseUrl/traspaso.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));

      debugPrint("📥 RESPUESTA TRASPASO: ${res.body}");

      return jsonDecode(res.body);
    } catch (e) {
      debugPrint("❌ ERROR TRASPASO: $e");

      return {
        "status": "error",
        "mensaje": "Error al registrar el traspaso"
      };
    }
  }
}