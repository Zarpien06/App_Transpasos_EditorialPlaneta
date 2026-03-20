import 'package:flutter/material.dart';
import 'origen_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0F1E), Color(0xFF0D1B2A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                // Header con logout
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Dashboard",
                      style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1.2),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white38, size: 20),
                      tooltip: "Cerrar sesión",
                      onPressed: () => _logout(context),
                    ),
                  ],
                ),

                // Card central
                Expanded(
                  child: Center(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1B2A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 52, color: Color(0xFF42A5F5)),
                          SizedBox(height: 16),
                          Text(
                            "Bienvenido a",
                            style: TextStyle(color: Color(0xFF90CAF9), fontSize: 14),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "TRASPASOS PLANETA",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Botones de acción
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text("NUEVO TRASPASO"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrigenScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}