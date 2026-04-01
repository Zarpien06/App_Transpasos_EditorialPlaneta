// lib/screens/admin/admin_dashboard_screen.dart
// ─────────────────────────────────────────────────────────────
// Panel Admin — 3 secciones:
//   🔒 Modo Kiosko     — local, sin red
//   ⬇  Descargar datos — nube → BD local del dispositivo
//   ⬆  Subir datos     — BD local → nube (hmoval + facturas)
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity_service.dart';
import '../../services/api_service.dart';
import '../../services/sync_service.dart';
import '../../main.dart';
import '../login_screen.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> adminData;
  const AdminDashboardScreen({super.key, required this.adminData});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {

  bool _descargaLoading = false;
  bool _subidaLoading   = false;

  String? _descargaMsg;
  bool?   _descargaOk;
  String? _subidaMsg;
  bool?   _subidaOk;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  // 🔒 KIOSKO — local, sin BD, sin red
  // ══════════════════════════════════════════════════════════
  Future<void> _toggleKiosko() async {
    final kiosk       = ref.read(kioskProvider);
    final nuevoEstado = !kiosk.isKioskActive;
    final accion      = nuevoEstado ? 'ACTIVAR' : 'DESACTIVAR';

    final confirm = await _showConfirmDialog(
      title:       '$accion Modo Kiosko',
      content:     nuevoEstado
          ? 'El dispositivo entrará en modo kiosko.\nLos usuarios NO podrán salir de la app.'
          : 'Se desactivará el modo kiosko y el dispositivo volverá al uso normal.',
      icon:        nuevoEstado ? Icons.lock : Icons.lock_open,
      color:       nuevoEstado ? Colors.orange : const Color(0xFF4F8CFF),
      confirmText: accion,
    );
    if (confirm != true) return;

    if (nuevoEstado) {
      // ✅ FIX: onTimeout ANTES de activate() para que el timer
      // arranque con el callback ya asignado
      kiosk.onTimeout = () {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      };
      await kiosk.activate();
    } else {
      await kiosk.forceDeactivate();
    }

    setState(() {});
    _showSnack(
      nuevoEstado ? '🔒 Modo kiosko ACTIVADO' : '🔓 Modo kiosko DESACTIVADO',
      success: true,
    );
  }

  // ══════════════════════════════════════════════════════════
  // ⬇ DESCARGAR — nube → BD local
  // ══════════════════════════════════════════════════════════
  Future<void> _descargar() async {
    if (!ConnectivityService().isOnline) {
      _showSnack('Sin conexión a internet', success: false);
      return;
    }

    final confirm = await _showConfirmDialog(
      title:       'Descargar datos',
      content:     'Se descargarán los datos maestros del servidor\n(usuarios, productos, configuración).\n¿Continuar?',
      icon:        Icons.cloud_download_outlined,
      color:       Colors.teal,
      confirmText: 'Descargar',
    );
    if (confirm != true) return;

    setState(() {
      _descargaLoading = true;
      _descargaMsg     = null;
      _descargaOk      = null;
    });

    final resultado = await SyncService.descargar();

    setState(() {
      _descargaLoading = false;
      _descargaOk      = resultado.exitoso;
      _descargaMsg     = resultado.exitoso
          ? '✅ Descarga completada\n'
            '• Admin: ${resultado.adminOk ? "ok" : "error"}\n'
            '• Usuarios: ${resultado.usuariosTraspasosOk ? "ok" : "error"}\n'
            '• Productos: ${resultado.productosOk ? "ok" : "error"}'
          : '❌ ${resultado.mensaje}';
    });

    _showSnack(
      resultado.exitoso ? 'Descarga completada' : resultado.mensaje,
      success: resultado.exitoso,
    );
  }

  // ══════════════════════════════════════════════════════════
  // ⬆ SUBIR — BD local → nube
  // ══════════════════════════════════════════════════════════
  Future<void> _abrirSubida() async {
    if (!ConnectivityService().isOnline) {
      _showSnack('Sin conexión a internet', success: false);
      return;
    }

    setState(() => _subidaLoading = true);
    final resp = await ApiService.getSyncPendientes();
    setState(() => _subidaLoading = false);

    if (!mounted) return;

    if (resp['status'] != 'ok') {
      _showSnack(resp['mensaje'] ?? 'Error al consultar pendientes', success: false);
      return;
    }

    _mostrarModalSubida(resp);
  }

  void _mostrarModalSubida(Map<String, dynamic> data) {
    final resumen     = data['resumen']          as Map<String, dynamic>? ?? {};
    final movimientos = data['movimientos']      as List<dynamic>?        ?? [];
    final total       = data['total_pendientes'] as int?                  ?? 0;
    final hmovalInfo  = resumen['hmoval']        as Map<String, dynamic>? ?? {};
    final mcabfaInfo  = resumen['mcabfa']        as Map<String, dynamic>? ?? {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize:     0.95,
        minChildSize:     0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141929),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        color: Color(0xFF4F8CFF), size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Subir al Servidor',
                              style: TextStyle(color: Colors.white,
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Datos pendientes de sincronizar',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildResumenTabla(
                      tabla: 'hmoval', label: 'Movimientos de Traspaso',
                      registros: hmovalInfo['registros'] as int? ?? 0,
                      extra: '${hmovalInfo['total_libros'] ?? 0} libros en total',
                      color: const Color(0xFF4F8CFF), icon: Icons.swap_horiz,
                    ),
                    const SizedBox(height: 10),
                    _buildResumenTabla(
                      tabla: 'mcabfa', label: 'Facturas',
                      registros: mcabfaInfo['registros'] as int? ?? 0,
                      extra: '',
                      color: Colors.green, icon: Icons.receipt_long_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: movimientos.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Colors.greenAccent, size: 52),
                            SizedBox(height: 12),
                            Text('¡Todo sincronizado!',
                                style: TextStyle(color: Colors.white70, fontSize: 16)),
                            SizedBox(height: 4),
                            Text('No hay datos pendientes de subir',
                                style: TextStyle(color: Colors.white38, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: movimientos.length,
                        itemBuilder: (_, i) => _buildMovimientoCard(
                            movimientos[i] as Map<String, dynamic>),
                      ),
              ),
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Se marcarán $total registros como sincronizados.',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity, height: 52,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.cloud_upload),
                          label: Text('Subir $total registros'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F8CFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _confirmarSubida(
                            movimientos: movimientos,
                            tieneFacturas:
                                (mcabfaInfo['registros'] as int? ?? 0) > 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarSubida({
    required List<dynamic> movimientos,
    required bool tieneFacturas,
  }) async {
    Navigator.pop(context);

    final confirm = await _showConfirmDialog(
      title:       'Confirmar sincronización',
      content:     '¿Confirmas subir todos los registros pendientes al servidor?',
      icon:        Icons.cloud_upload_outlined,
      color:       const Color(0xFF4F8CFF),
      confirmText: 'Subir ahora',
    );
    if (confirm != true) return;

    final nums = movimientos
        .map((m) => (m as Map<String, dynamic>)['num_movimiento'] as int)
        .toList();

    setState(() {
      _subidaLoading = true;
      _subidaMsg     = null;
      _subidaOk      = null;
    });

    final resp = await ApiService.marcarSincronizadoHmoval(nums);
    if (tieneFacturas) await ApiService.marcarSincronizadoFacturas();

    setState(() {
      _subidaLoading = false;
      _subidaOk      = resp['status'] == 'ok';
      _subidaMsg     = resp['status'] == 'ok'
          ? '✅ ${resp['afectados'] ?? nums.length} registros subidos correctamente'
          : '❌ ${resp['mensaje'] ?? 'Error al sincronizar'}';
    });

    _showSnack(
      resp['status'] == 'ok'
          ? '${resp['afectados'] ?? nums.length} registros subidos'
          : resp['mensaje'] ?? 'Error al sincronizar',
      success: resp['status'] == 'ok',
    );
  }

  // ══════════════════════════════════════════════════════════
  // HELPERS UI
  // ══════════════════════════════════════════════════════════
  Widget _buildResumenTabla({
    required String tabla, required String label,
    required int registros, required String extra,
    required Color color, required IconData icon,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(
                  color: Colors.white70, fontSize: 12,
                  fontWeight: FontWeight.w500)),
              Text('Tabla: $tabla', style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
              if (extra.isNotEmpty)
                Text(extra, style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: registros > 0 ? color : Colors.green,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            registros > 0 ? '$registros pend.' : '✓ Al día',
            style: const TextStyle(color: Colors.white,
                fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  Widget _buildMovimientoCard(Map<String, dynamic> m) {
    final fecha    = m['fecha']?.toString() ?? '';
    final fechaFmt = fecha.length == 8
        ? '${fecha.substring(6, 8)}/${fecha.substring(4, 6)}/${fecha.substring(0, 4)}'
        : fecha;
    final hora    = m['hora']?.toString() ?? '';
    final horaFmt = hora.length == 6
        ? '${hora.substring(0, 2)}:${hora.substring(2, 4)}:${hora.substring(4, 6)}'
        : hora;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2640),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F8CFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('MOV #${m['num_movimiento']}',
                    style: const TextStyle(color: Color(0xFF4F8CFF),
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text('$fechaFmt  $horaFmt',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(Icons.store_outlined, 'Origen',  m['origen_nombre']  ?? '—'),
          const SizedBox(height: 4),
          _infoRow(Icons.store,          'Destino', m['destino_nombre'] ?? '—'),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('${m['num_lineas']} líneas',   const Color(0xFF4F8CFF)),
              const SizedBox(width: 8),
              _chip('${m['total_libros']} libros', Colors.greenAccent),
            ],
          ),
          if ((m['detalle_libros'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(m['detalle_libros'].toString(),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, color: Colors.white38, size: 14),
      const SizedBox(width: 6),
      Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
      Expanded(
        child: Text(value,
            style: const TextStyle(color: Colors.white70, fontSize: 12,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis),
      ),
    ],
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Future<bool?> _showConfirmDialog({
    required String title, required String content,
    required IconData icon, required Color color, required String confirmText,
  }) => showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => Dialog(
      backgroundColor: const Color(0xFF1A2035),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white,
                fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(content, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60,
                    fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(ctx, rootNavigator: true).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white60,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(ctx, rootNavigator: true).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(confirmText),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    transitionBuilder: (_, anim, __, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
      child: child,
    ),
  );

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final kiosk  = ref.watch(kioskProvider);
    final activo = kiosk.isKioskActive;
    final nombre = widget.adminData['nombre'] ?? 'Administrador';
    final online = ConnectivityService().isOnline;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141929),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white54, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Panel Admin', style: TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Bienvenido, $nombre', style: const TextStyle(
                color: Color(0xFF4F8CFF), fontSize: 11)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (online ? Colors.green : Colors.red).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (online ? Colors.green : Colors.red).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(online ? Icons.wifi : Icons.wifi_off,
                    color: online ? Colors.green : Colors.red, size: 13),
                const SizedBox(width: 4),
                Text(online ? 'Online' : 'Offline',
                    style: TextStyle(
                        color: online ? Colors.green : Colors.red,
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4F8CFF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF4F8CFF).withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFF4F8CFF), size: 13),
                SizedBox(width: 4),
                Text('ADMIN', style: TextStyle(color: Color(0xFF4F8CFF),
                    fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),

      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ══ KIOSKO ══════════════════════════════════
              _sectionLabel('MODO KIOSKO'),
              const SizedBox(height: 12),
              _AdminCard(
                icon:        activo ? Icons.lock : Icons.lock_open_outlined,
                iconColor:   activo ? Colors.orange : const Color(0xFF4F8CFF),
                title:       'Modo Kiosko',
                subtitle:    activo
                    ? 'Activo — usuarios no pueden salir de la app'
                    : 'Inactivo — uso normal del dispositivo',
                statusLabel: activo ? 'ACTIVO' : 'INACTIVO',
                statusColor: activo ? Colors.orange : Colors.green,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Estado del modo kiosko:',
                              style: TextStyle(color: Colors.white60, fontSize: 13)),
                        ),
                        Switch(
                          value: activo,
                          onChanged: (_) => _toggleKiosko(),
                          activeThumbColor: Colors.orange,
                          inactiveTrackColor: Colors.white24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(activo ? Icons.lock_open : Icons.lock),
                        label: Text(activo
                            ? 'Desactivar modo kiosko'
                            : 'Activar modo kiosko'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activo
                              ? Colors.orange
                              : const Color(0xFF4F8CFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: _toggleKiosko,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ══ SINCRONIZACIÓN ═══════════════════════════
              _sectionLabel('SINCRONIZACIÓN DE DATOS'),
              const SizedBox(height: 12),

              if (!online)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sin conexión a internet. Conéctate para sincronizar.',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── CARD DESCARGAR ─────────────────────────
              _AdminCard(
                icon:        Icons.cloud_download_outlined,
                iconColor:   Colors.teal,
                title:       'Descargar datos',
                subtitle:    'Nube → dispositivo',
                statusLabel: '',
                statusColor: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _syncRow(Icons.people_outline, 'Usuarios y perfiles de traspaso'),
                    const SizedBox(height: 6),
                    _syncRow(Icons.inventory_2_outlined, 'Catálogo de productos'),
                    const SizedBox(height: 6),
                    _syncRow(Icons.manage_accounts_outlined,
                        'Configuración de administrador'),
                    if (_descargaMsg != null) ...[
                      const SizedBox(height: 12),
                      _resultBox(_descargaMsg!, _descargaOk ?? false),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _descargaLoading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_download),
                        label: Text(_descargaLoading
                            ? 'Descargando...' : 'Descargar ahora'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: (_descargaLoading || !online) ? null : _descargar,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── CARD SUBIR ────────────────────────────
              _AdminCard(
                icon:        Icons.cloud_upload_outlined,
                iconColor:   const Color(0xFF4F8CFF),
                title:       'Subir datos',
                subtitle:    'Dispositivo → nube',
                statusLabel: '',
                statusColor: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _syncRow(Icons.swap_horiz, 'Movimientos de traspaso (hmoval)'),
                    const SizedBox(height: 6),
                    _syncRow(Icons.receipt_long_outlined, 'Facturas de venta (mcabfa)'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.white38, size: 14),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Solo registros con mnube=0. Puedes revisar el listado antes de confirmar.',
                              style: TextStyle(color: Colors.white38,
                                  fontSize: 11, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_subidaMsg != null) ...[
                      const SizedBox(height: 12),
                      _resultBox(_subidaMsg!, _subidaOk ?? false),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _subidaLoading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_upload),
                        label: Text(_subidaLoading
                            ? 'Consultando...' : 'Ver pendientes y subir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F8CFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: (_subidaLoading || !online) ? null : _abrirSubida,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(label,
      style: const TextStyle(color: Colors.white38, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 2));

  Widget _syncRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: Colors.white38, size: 15),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ],
  );

  Widget _resultBox(String msg, bool ok) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: (ok ? Colors.green : Colors.red).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: (ok ? Colors.green : Colors.red).withValues(alpha: 0.3),
      ),
    ),
    child: Text(msg,
        style: TextStyle(
            color: ok ? Colors.greenAccent : Colors.redAccent,
            fontSize: 11, height: 1.5)),
  );
}

// ══════════════════════════════════════════════════════════
// _AdminCard
// ══════════════════════════════════════════════════════════
class _AdminCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final String   statusLabel;
  final Color    statusColor;
  final Widget   child;

  const _AdminCard({
    required this.icon,        required this.iconColor,
    required this.title,       required this.subtitle,
    required this.statusLabel, required this.statusColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF141929),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: iconColor.withValues(alpha: 0.2)),
      boxShadow: [
        BoxShadow(color: iconColor.withValues(alpha: 0.05),
            blurRadius: 20, offset: const Offset(0, 4)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white,
                      fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (statusLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(statusLabel,
                    style: TextStyle(color: statusColor, fontSize: 10,
                        fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
          ],
        ),
        child,
      ],
    ),
  );
}