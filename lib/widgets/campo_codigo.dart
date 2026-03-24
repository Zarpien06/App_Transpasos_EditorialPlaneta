import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CampoCodigo extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool ocultable;
  final FocusNode? focusNode;
  final void Function(String)? onSubmitted;

  const CampoCodigo({
    super.key,
    required this.controller,
    required this.label,
    this.ocultable = false,
    this.focusNode,
    this.onSubmitted,
  });

  @override
  State<CampoCodigo> createState() => _CampoCodigoState();
}

class _CampoCodigoState extends State<CampoCodigo> {
  bool _scanHecho = false;

  void _escanear() {
    _scanHecho = false;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ScannerScreen(
        onDetected: (code) {
          if (_scanHecho) return;
          _scanHecho = true;
          widget.controller.text = code;
          Navigator.pop(context);
          widget.onSubmitted?.call(code);
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode:  widget.focusNode,
      obscureText: widget.ocultable,
      style: const TextStyle(color: Colors.white),
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.onSubmitted != null
          ? TextInputAction.done
          : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF42A5F5)),
          onPressed: _escanear,
        ),
      ),
    );
  }
}

// ── Pantalla de escaneo con control de flash ──────────────────────
class _ScannerScreen extends StatefulWidget {
  final void Function(String code) onDetected;
  const _ScannerScreen({required this.onDetected});

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _flashOn = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    await _ctrl.toggleTorch();
    setState(() => _flashOn = !_flashOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear código'),
        backgroundColor: Colors.black,
        actions: [
          // Botón flash en el AppBar
          IconButton(
            icon: Icon(
              _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _flashOn ? const Color(0xFFFFD54F) : Colors.white54,
            ),
            tooltip: _flashOn ? 'Apagar flash' : 'Encender flash',
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Cámara
          MobileScanner(
            controller: _ctrl,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null && code.isNotEmpty) {
                widget.onDetected(code);
              }
            },
          ),

          // Botón flash flotante (también en pantalla, más fácil de tocar)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _toggleFlash,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: _flashOn
                        ? const Color(0xFFFFD54F).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: _flashOn
                          ? const Color(0xFFFFD54F).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _flashOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: _flashOn
                            ? const Color(0xFFFFD54F)
                            : Colors.white54,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _flashOn ? 'Flash encendido' : 'Flash apagado',
                        style: TextStyle(
                          color: _flashOn
                              ? const Color(0xFFFFD54F)
                              : Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}