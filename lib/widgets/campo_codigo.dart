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
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Escanear código'),
            backgroundColor: Colors.black,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              if (_scanHecho) return;

              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null && code.isNotEmpty) {
                  _scanHecho = true;
                  widget.controller.text = code;
                  Navigator.pop(context);

                  // Si hay onSubmitted, dispara automáticamente
                  if (widget.onSubmitted != null) {
                    widget.onSubmitted!(code);
                  }
                }
              }
            },
          ),
        ),
      ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF42A5F5)),
          onPressed: _escanear,
        ),
      ),
    );
  }
}