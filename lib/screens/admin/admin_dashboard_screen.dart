// lib/screens/admin/admin_dashboard_screen.dart
// ─────────────────────────────────────────────────────────────
// Panel Admin — 4 secciones:
//   🔒 Modo Kiosko          — local, sin red
//   ⬇  Descargar datos      — nube → BD local del dispositivo
//   💾 Backup manual        — exportar BD + enviar por email
//   📋 Log traspasos        — historial completo con estado de sync
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity_service.dart';
import '../../core/database_service.dart';
import '../../services/sync_service.dart';
import '../../services/backup_service.dart';
import '../../main.dart';
import '../login_screen.dart';
import '../../widgets/sync_log_panel.dart';
import '../../widgets/data_usage_panel.dart';

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
  String? _descargaMsg;
  bool?   _descargaOk;

  bool _logLoading = true;
  List<Map<String, dynamic>> _logTraspasos = [];

  bool _backupLoading = false;
  String? _backupMsg;
  bool?   _backupOk;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _cargarLog();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  // CARGAR LOG DE TRASPASOS — todos, hasta 1000
  // ══════════════════════════════════════════════════════════
  Future<void> _cargarLog() async {
    setState(() => _logLoading = true);
    final db   = DatabaseService();
    final data = await db.getUltimosTraspasos(limite: 1000);
    if (mounted) {
      setState(() {
        _logTraspasos = data;
        _logLoading   = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════
  // 🔒 KIOSKO
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
  // ⬇ DESCARGAR
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
  // 💾 BACKUP MANUAL
  // ══════════════════════════════════════════════════════════
  Future<void> _hacerBackup() async {
    final confirm = await _showConfirmDialog(
      title:       'Generar Backup',
      content:     'Se exportará la base de datos completa (.db + .zip)\ny se enviará por email a los administradores.\n¿Continuar?',
      icon:        Icons.backup_outlined,
      color:       const Color(0xFF8B5CF6),
      confirmText: 'GENERAR',
    );
    if (confirm != true) return;

    setState(() {
      _backupLoading = true;
      _backupMsg     = null;
      _backupOk      = null;
    });

    final resultado = await BackupService.ejecutar();

    if (mounted) {
      setState(() {
        _backupLoading = false;
        _backupOk      = resultado.ok;
        _backupMsg     = resultado.mensaje;
      });
      _showSnack(
        resultado.ok ? '✅ Backup generado correctamente' : resultado.mensaje,
        success: resultado.ok,
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  // HELPERS UI
  // ══════════════════════════════════════════════════════════

  String _fmtFecha(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt  = DateTime.parse(iso).toLocal();
      final mes = ['ene','feb','mar','abr','may','jun',
                   'jul','ago','sep','oct','nov','dic'][dt.month - 1];
      return '${dt.day.toString().padLeft(2,'0')} $mes ${dt.year}  '
             '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'sincronizado': return Colors.greenAccent;
      case 'pendiente'   : return Colors.orange;
      case 'error'       : return Colors.redAccent;
      default            : return Colors.white38;
    }
  }

  IconData _estadoIcon(String estado) {
    switch (estado) {
      case 'sincronizado': return Icons.cloud_done_outlined;
      case 'pendiente'   : return Icons.cloud_upload_outlined;
      case 'error'       : return Icons.cloud_off_outlined;
      default            : return Icons.hourglass_empty;
    }
  }

  String _estadoLabel(String estado) {
    switch (estado) {
      case 'sincronizado': return 'SINCRONIZADO';
      case 'pendiente'   : return 'PENDIENTE';
      case 'error'       : return 'ERROR';
      default            : return estado.toUpperCase();
    }
  }

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
                  color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 14),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        confirmText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
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

    final nombre = widget.adminData['Nombre_Usuario']
            ?.toString().trim().isNotEmpty == true
        ? widget.adminData['Nombre_Usuario'].toString().trim()
        : widget.adminData['nombre']?.toString() ?? 'Administrador';

    final online = ConnectivityService().isOnline;

    final pendientes    = _logTraspasos.where((t) => t['estado'] == 'pendiente').length;
    final sincronizados = _logTraspasos.where((t) => t['estado'] == 'sincronizado').length;

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
                    ? 'Activo — usuarios no pueden salir'
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
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 13)),
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
                          backgroundColor:
                              activo ? Colors.orange : const Color(0xFF4F8CFF),
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

              // ══ SINCRONIZACIÓN DE DATOS ═══════════════════
              _sectionLabel('SINCRONIZACIÓN DE DATOS'),
              const SizedBox(height: 12),

              if (!online)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sin conexión. Los traspasos se subirán automáticamente al reconectar.',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

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
                    _syncRow(Icons.people_outline,
                        'Usuarios y perfiles de traspaso'),
                    const SizedBox(height: 6),
                    _syncRow(Icons.inventory_2_outlined,
                        'Catálogo de productos'),
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
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_download),
                        label: Text(_descargaLoading
                            ? 'Descargando...'
                            : 'Descargar ahora'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed:
                            (_descargaLoading || !online) ? null : _descargar,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ══ BACKUP MANUAL ════════════════════════════
              _sectionLabel('BACKUP MANUAL'),
              const SizedBox(height: 12),
              _AdminCard(
                icon:        Icons.backup_outlined,
                iconColor:   const Color(0xFF8B5CF6),
                title:       'Exportar backup',
                subtitle:    'BD completa · .sql + .zip · envío por email',
                statusLabel: '',
                statusColor: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _syncRow(Icons.storage_outlined,
                        'Base de datos SQLite completa (.sql)'),
                    const SizedBox(height: 6),
                    _syncRow(Icons.folder_zip_outlined,
                        'Archivo comprimido (.zip)'),
                    const SizedBox(height: 6),
                    _syncRow(Icons.email_outlined,
                        '4 destinatarios: Oscar · Jersan · Iván · Harold '),
                    const SizedBox(height: 6),
                    _syncRow(Icons.phone_android_outlined,
                        'También se guarda en el dispositivo'),
                    if (_backupMsg != null) ...[
                      const SizedBox(height: 12),
                      _resultBox(_backupMsg!, _backupOk ?? false),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _backupLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.backup_outlined),
                        label: Text(_backupLoading
                            ? 'Generando backup...'
                            : 'Generar backup ahora'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: _backupLoading ? null : _hacerBackup,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ══ PANEL DE SYNC AUTOMÁTICO ═════════════════
              _sectionLabel('SINCRONIZACIÓN AUTOMÁTICA'),
              const SizedBox(height: 12),
              const SyncLogPanel(),

              const SizedBox(height: 28),

              // ══ CONSUMO DE DATOS ══════════════════════════
              _sectionLabel('CONSUMO DE DATOS'),
              const SizedBox(height: 12),
              const DataUsagePanel(),

              const SizedBox(height: 28),

              // ══ LOG DE TRASPASOS ══════════════════════════
              _sectionLabel('REGISTRO DE TRASPASOS'),
              const SizedBox(height: 6),

              if (!_logLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      _statChip(
                        label: 'Total',
                        value: _logTraspasos.length.toString(),
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 8),
                      _statChip(
                        label: 'Subidos',
                        value: sincronizados.toString(),
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 8),
                      _statChip(
                        label: 'Pendientes',
                        value: pendientes.toString(),
                        color: pendientes > 0 ? Colors.orange : Colors.white38,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _cargarLog,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2640),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Icon(Icons.refresh_rounded,
                              color: Colors.white54, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

              // OPT: reemplaza Column + map().toList() que construía hasta
              // 1000 _logCard de golpe (todos en memoria, visibles o no).
              // ListView.builder con shrinkWrap + NeverScrollableScrollPhysics
              // construye solo los ítems que caben en pantalla y los recicla
              // al hacer scroll — elimina los Skipped 148-222 frames del log.
              if (_logLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                        color: Color(0xFF4F8CFF)),
                  ),
                )
              else if (_logTraspasos.isEmpty)
                _emptyLog()
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _logTraspasos.length,
                  itemBuilder: (_, i) => _logCard(_logTraspasos[i]),
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // LOG CARD INDIVIDUAL
  // ══════════════════════════════════════════════════════════
  Widget _logCard(Map<String, dynamic> t) {
    final estado         = t['estado'] as String? ?? 'pendiente';
    final estadoColor    = _estadoColor(estado);
    final estadoIcon     = _estadoIcon(estado);
    final estadoLabel    = _estadoLabel(estado);
    final id             = t['id']?.toString() ?? '—';
    final origenAlmacen  = t['origen_almacen']  as String? ?? '—';
    final origenStand    = t['origen_stand']    as String? ?? '—';
    final destinoAlmacen = t['destino_almacen'] as String? ?? '—';
    final destinoStand   = t['destino_stand']   as String? ?? '—';
    final numRefs        = t['num_refs']        as int? ?? 0;
    final totalLibros    = t['total_libros']    as int? ?? 0;
    final fechaCreacion  = _fmtFecha(t['fecha_creacion'] as String?);
    final fechaSync      = t['fecha_sync'] != null
        ? _fmtFecha(t['fecha_sync'] as String?)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141929),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: estadoColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: estadoColor.withValues(alpha: 0.35)),
                  ),
                  child: Center(
                    child: Text('#$id',
                        style: TextStyle(
                            color: estadoColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.store_outlined,
                                  color: Colors.white38, size: 12),
                              const SizedBox(width: 3),
                              Text('$origenAlmacen  St.$origenStand',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white24, size: 12),
                          Text('$destinoAlmacen  St.$destinoStand',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(fechaCreacion,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(estadoIcon, color: estadoColor, size: 11),
                      const SizedBox(width: 4),
                      Text(estadoLabel,
                          style: TextStyle(
                              color: estadoColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F1520),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                _miniChip('$numRefs refs', const Color(0xFF4F8CFF)),
                const SizedBox(width: 8),
                _miniChip('$totalLibros libros', Colors.greenAccent),
                const Spacer(),
                if (fechaSync != null)
                  Row(children: [
                    const Icon(Icons.cloud_done_outlined,
                        color: Colors.greenAccent, size: 11),
                    const SizedBox(width: 4),
                    Text(fechaSync,
                        style: const TextStyle(
                            color: Colors.greenAccent, fontSize: 9)),
                  ])
                else
                  const Row(children: [
                    Icon(Icons.schedule_rounded, color: Colors.orange, size: 11),
                    SizedBox(width: 4),
                    Text('En espera',
                        style: TextStyle(color: Colors.orange, fontSize: 9)),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyLog() => Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, color: Colors.white12, size: 52),
              SizedBox(height: 12),
              Text('Sin traspasos registrados',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
              SizedBox(height: 4),
              Text('Los traspasos aparecerán aquí al generarse',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _statChip({
    required String label,
    required String value,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      );

  Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      );

  Widget _sectionLabel(String label) => Text(label,
      style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2));

  Widget _syncRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, color: Colors.white38, size: 15),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );

  Widget _resultBox(String msg, bool ok) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (ok ? Colors.green : Colors.red).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (ok ? Colors.green : Colors.red).withValues(alpha: 0.3)),
        ),
        child: Text(msg,
            style: TextStyle(
                color: ok ? Colors.greenAccent : Colors.redAccent,
                fontSize: 11,
                height: 1.5)),
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
            BoxShadow(
                color: iconColor.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4)),
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
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                if (statusLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                  ),
              ],
            ),
            child,
          ],
        ),
      );
}