// lib/screens/admin/admin_login_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/connectivity_service.dart';
import '../../core/database_service.dart';
import '../../services/api_service.dart';
import 'admin_dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {

  final _nickCtrl = TextEditingController();
  final _pwdCtrl  = TextEditingController();

  bool _loading = false;
  bool _showPwd = false;
  String? _error;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nickCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final nick = _nickCtrl.text.trim();
    final pwd  = _pwdCtrl.text.trim();

    if (nick.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Ingresa usuario y contraseña');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final online = ConnectivityService().isOnline;

    if (online) {
      // ══ CON INTERNET — valida en servidor ═══════════════
      await _loginOnline(nick, pwd);
    } else {
      // ══ SIN INTERNET — valida en BD local ═══════════════
      await _loginOffline(nick, pwd);
    }

    setState(() => _loading = false);
  }

  // ── LOGIN ONLINE ──────────────────────────────────────────
  Future<void> _loginOnline(String nick, String pwd) async {
    final resp = await ApiService.adminLogin(nick: nick, pwd: pwd);

    if (!mounted) return;

    if (resp['status'] == 'ok') {
      // ✅ Guardar credenciales localmente para uso offline futuro
      await DatabaseService().guardarAdminLocal(nick, pwd);

      Map<String, dynamic> adminData = {'usuario': nick, 'tipo': 'admin'};
      final rawData = resp['data'];
      if (rawData is Map<String, dynamic>) {
        adminData = rawData;
      } else if (rawData is String) {
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is Map<String, dynamic>) adminData = decoded;
        } catch (_) {}
      }

      _irAlDashboard(adminData);
    } else {
      setState(() {
        _error = resp['message'] ?? resp['mensaje'] ?? 'Usuario o contraseña incorrectos';
      });
    }
  }

  // ── LOGIN OFFLINE ─────────────────────────────────────────
  Future<void> _loginOffline(String nick, String pwd) async {
    final db    = DatabaseService();
    final valido = await db.validarAdminLocal(nick, pwd);

    if (!mounted) return;

    if (valido) {
      // ✅ Credenciales correctas en BD local
      final adminData = await db.getAdminLocal(nick) ?? {};
      _irAlDashboard({
        'usuario': nick,
        'tipo':    'admin',
        ...adminData,
      });
    } else {
      // Verificar si hay algún admin guardado
      final tieneAdmin = await _hayAdminGuardado();
      setState(() {
        _error = tieneAdmin
            ? 'Usuario o contraseña incorrectos'
            : 'Sin conexión y sin datos locales.\nConéctate a internet y descarga los datos primero.';
      });
    }
  }

  Future<bool> _hayAdminGuardado() async {
    final db   = DatabaseService();
    final rows = await (await db.database).query('admin_local', limit: 1);
    return rows.isNotEmpty;
  }

  void _irAlDashboard(Map<String, dynamic> adminData) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDashboardScreen(adminData: adminData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = ConnectivityService().isOnline;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  Container(
                    width: 80, height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF4F8CFF), Color(0xFF1A3A8F)],
                      ),
                    ),
                    child: const Icon(Icons.admin_panel_settings,
                        color: Colors.white, size: 40),
                  ),

                  const SizedBox(height: 24),

                  const Text('PANEL ADMINISTRADOR',
                      style: TextStyle(color: Color(0xFF4F8CFF),
                          fontSize: 13, fontWeight: FontWeight.w700,
                          letterSpacing: 3)),

                  const SizedBox(height: 6),

                  const Text('Editorial Planeta Colombia',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),

                  const SizedBox(height: 8),

                  // Badge online/offline
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: (online ? Colors.green : Colors.orange)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (online ? Colors.green : Colors.orange)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          online ? Icons.cloud_done_outlined
                                 : Icons.cloud_off_outlined,
                          color: online ? Colors.green : Colors.orange,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          online
                              ? 'Online — validando en servidor'
                              : 'Offline — usando datos locales',
                          style: TextStyle(
                            color: online ? Colors.green : Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141929),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [

                        _buildField(
                          controller: _nickCtrl,
                          label: 'Usuario administrador',
                          icon: Icons.person_outline,
                        ),

                        const SizedBox(height: 16),

                        TextField(
                          controller: _pwdCtrl,
                          obscureText: !_showPwd,
                          onSubmitted: (_) => _login(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_showPwd
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _showPwd = !_showPwd),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1E2640),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12)),
                          ),
                        ],

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F8CFF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _loading
                                ? const SizedBox(width: 22, height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Ingresar',
                                    style: TextStyle(fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('← Volver',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFF1E2640),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}