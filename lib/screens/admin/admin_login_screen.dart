import 'dart:convert';
import 'package:flutter/material.dart';
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
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
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

  // 🔥 LOGIN ADAPTADO A TU BACKEND (SIN TOCAR PHP)
  Future<void> _login() async {
    final nick = _nickCtrl.text.trim();
    final pwd  = _pwdCtrl.text.trim();

    if (nick.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Ingresa usuario y contraseña');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final resp = await ApiService.adminLogin(nick: nick, pwd: pwd);

    setState(() => _loading = false);

    if (!mounted) return;

    // 🟢 LOGIN EXITOSO (aunque backend mande HTML)
    if (resp['status'] == 'ok') {

      Map<String, dynamic> adminData = {
        'usuario': nick,
        'tipo': 'admin'
      };

      // Si viene algo usable lo intentamos parsear
      final rawData = resp['data'];

      if (rawData is Map<String, dynamic>) {
        adminData = rawData;
      } else if (rawData is String) {
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is Map<String, dynamic>) {
            adminData = decoded;
          }
        } catch (_) {
          // ignoramos porque puede ser HTML
        }
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(
            adminData: adminData,
          ),
        ),
      );

    } else {
      setState(() {
        _error = resp['message'] ??
                 resp['mensaje'] ??
                 'Usuario o contraseña incorrectos';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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

                  // LOGO
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F8CFF), Color(0xFF1A3A8F)],
                      ),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'PANEL ADMINISTRADOR',
                    style: TextStyle(
                      color: Color(0xFF4F8CFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Editorial Planeta Colombia',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // CARD
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const CircularProgressIndicator()
                                : const Text('Ingresar'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('← Volver'),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}