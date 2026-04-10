// lib/core/device_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Maneja la identidad única de cada dispositivo físico.
// Incluye:
// - Validaciones completas
// - Generación de UUID para traspasos
// ─────────────────────────────────────────────────────────────────────────────

import 'database_service.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final DatabaseService _db = DatabaseService();

  String? _deviceId;

  // 👇 GENERADOR DE UUID (NUEVO)
  final Uuid _uuid = const Uuid();

  /// Genera un UUID único para cada traspaso
  Future<String> generarUUID() async {
    return _uuid.v4();
  }

  // ── ¿Ya fue inicializado este dispositivo? ─────────────────────────────────
  Future<bool> estaInicializado() async {
    final val = await _db.getConfig('inicializado');
    return val == '1';
  }

  // ── Obtener el device_id guardado ─────────────────────────────────────────
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final val = await _db.getConfig('device_id');

    if (val == null || val.isEmpty) {
      // Caso extremo: no está inicializado correctamente
      _deviceId = 'DESCONOCIDO';
    } else {
      _deviceId = val;
    }

    return _deviceId!;
  }

  // ── Inicializar el dispositivo (primer uso) ───────────────────────────────
  Future<void> inicializar(String numeroCortado) async {
    final yaInicializado = await estaInicializado();
    if (yaInicializado) {
      throw Exception('El dispositivo ya fue inicializado');
    }

    final limpio = numeroCortado.trim();

    if (limpio.isEmpty) {
      throw Exception('Debe ingresar un número de dispositivo');
    }

    final numeroInt = int.tryParse(limpio);
    if (numeroInt == null) {
      throw Exception('El número debe ser solo dígitos');
    }

    if (numeroInt <= 0 || numeroInt > 99) {
      throw Exception('El número debe estar entre 1 y 99');
    }

    final numero = numeroInt.toString().padLeft(2, '0');
    final deviceId = 'DV$numero';

    await _db.setConfig('device_id', deviceId);
    await _db.setConfig('inicializado', '1');

    _deviceId = deviceId;
  }

  // ── Reset manual ──────────────────────────────────────────────────────────
  Future<void> resetearDispositivo() async {
    await _db.setConfig('device_id', '');
    await _db.setConfig('inicializado', '0');
    _deviceId = null;
  }
}