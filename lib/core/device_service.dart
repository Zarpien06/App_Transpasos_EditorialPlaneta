// lib/core/device_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Maneja la identidad única de cada dispositivo físico.
// Al encender por primera vez, el operario ingresa el número (DV01, DV02…).
// Eso se guarda en SQLite y nunca más se pide. No hay que tocar el código.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:intl/intl.dart';
import 'database_service.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final DatabaseService _db = DatabaseService();

  String? _deviceId;

  // ── ¿Ya fue inicializado este dispositivo? ─────────────────────────────────
  Future<bool> estaInicializado() async {
    final val = await _db.getConfig('inicializado');
    return val == '1';
  }

  // ── Obtener el device_id guardado ─────────────────────────────────────────
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final val = await _db.getConfig('device_id');
    _deviceId = val ?? 'DESCONOCIDO';
    return _deviceId!;
  }

  // ── Inicializar el dispositivo (pantalla de primer uso) ───────────────────
  /// Recibe el código corto que ingresa el operario en la pantalla de inicio,
  /// por ejemplo "01", "02", "15".
  /// Genera el device_id en formato "DV01", "DV15", etc.
  Future<void> inicializar(String numeroCortado) async {
    final numero = numeroCortado.trim().padLeft(2, '0');
    final deviceId = 'DV$numero';

    await _db.setConfig('device_id', deviceId);
    await _db.setConfig('inicializado', '1');

    _deviceId = deviceId;
  }

  // ── Generar UUID único para cada traspaso ─────────────────────────────────
  /// Formato: DV01-20260327-092548-a3f1
  /// Incluye el device_id + fecha + hora + sufijo aleatorio para evitar
  /// cualquier colisión incluso si dos dispositivos crean un traspaso al
  /// mismo segundo exacto.
  Future<String> generarUUID() async {
    final id = await getDeviceId();
    final now = DateTime.now();
    final fecha = DateFormat('yyyyMMdd').format(now);
    final hora = DateFormat('HHmmss').format(now);
    final sufijo = _randomHex(4);
    return '$id-$fecha-$hora-$sufijo';
  }

  String _randomHex(int length) {
    const chars = '0123456789abcdef';
    final rand = DateTime.now().microsecondsSinceEpoch;
    var result = '';
    var seed = rand;
    for (var i = 0; i < length; i++) {
      seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
      result += chars[seed % chars.length];
    }
    return result;
  }
}