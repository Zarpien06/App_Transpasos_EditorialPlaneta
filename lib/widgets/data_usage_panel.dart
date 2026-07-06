// lib/widgets/data_usage_panel.dart
// ─────────────────────────────────────────────────────────────
// Panel visual de monitoreo de consumo de datos.
// Rediseño: dark glassmorphism + paleta variada (no solo azul).
//
// USO:
//   import '../widgets/data_usage_panel.dart';
//   const DataUsagePanel(),
// ─────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/data_usage_service.dart';

class DataUsagePanel extends StatefulWidget {
  const DataUsagePanel({super.key});

  @override
  State<DataUsagePanel> createState() => _DataUsagePanelState();
}

class _DataUsagePanelState extends State<DataUsagePanel>
    with SingleTickerProviderStateMixin {
  final _svc = DataUsageService();

  late TabController _tabs;
  UsagePeriodo      _periodo  = UsagePeriodo.hoy;
  DataUsageResumen? _resumen;
  bool              _cargando = true;

  // ── Paleta ────────────────────────────────────────────────────────────────
  static const _glassBlanco    = Color(0x0DFFFFFF);
  static const _glassBorde     = Color(0x1AFFFFFF);
  static const _textoPrincipal = Color(0xFFF1F5F9);
  static const _textoSecun     = Color(0xFF94A3B8);
  static const _textoTenue     = Color(0xFF475569);

  static const _azul    = Color(0xFF60A5FA);
  static const _verde   = Color(0xFF34D399);
  static const _violeta = Color(0xFFA78BFA);
  static const _amber   = Color(0xFFFBBF24);
  static const _rosa    = Color(0xFFF472B6);
  static const _cyan    = Color(0xFF22D3EE);
  static const _gris    = Color(0xFF64748B);

  static const _gradHoy    = [Color(0x2660A5FA), Color(0x1A34D399)];
  static const _gradSemana = [Color(0x26A78BFA), Color(0x1A60A5FA)];
  static const _gradMes    = [Color(0x26FBBF24), Color(0x1AF472B6)];
  static const _gradTotal  = [Color(0x2622D3EE), Color(0x26A78BFA)];

  List<List<Color>> get _gradientes =>
      [_gradHoy, _gradSemana, _gradMes, _gradTotal];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() => _periodo = UsagePeriodo.values[_tabs.index]);
        _cargar();
      }
    });
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final r = await _svc.getResumen(periodo: _periodo);
    if (mounted) setState(() { _resumen = r; _cargando = false; });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _encabezado(),
        _tabBar(),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(
                color: _azul,
                strokeWidth: 2,
              ),
            ),
          )
        else if (_resumen != null) ...[
          const SizedBox(height: 12),
          _tarjetasResumen(_resumen!),
          const SizedBox(height: 12),
          _tablaProcesos(_resumen!),
          const SizedBox(height: 12),
          if (_resumen!.porDia.isNotEmpty) _graficaDias(_resumen!),
          const SizedBox(height: 12),
          _botonLimpiar(),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  // ── ENCABEZADO GLASS ──────────────────────────────────────────────────────

  Widget _encabezado() {
    final grad = _gradientes[_tabs.index];
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: grad),
            border: const Border(
              bottom: BorderSide(color: _glassBorde),
            ),
          ),
          child: Row(
            children: [
              _glassIcon(Icons.data_usage_rounded, _azul),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Monitoreo de Consumo',
                      style: TextStyle(
                        color: _textoPrincipal,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Bytes enviados y recibidos por proceso',
                      style: TextStyle(
                        color: _textoSecun,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _liveBadge(),
              const SizedBox(width: 8),
              _iconBtn(Icons.refresh_rounded, _cargar),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassIcon(IconData icon, Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _verde.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _verde.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: _verde,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'EN VIVO',
            style: TextStyle(
              color: _verde,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _glassBlanco,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _glassBorde, width: 1),
        ),
        child: Icon(icon, color: _textoSecun, size: 17),
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────────────────────────────────────

  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _glassBorde)),
      ),
      child: TabBar(
        controller: _tabs,
        indicatorColor: _azul,
        indicatorWeight: 1.5,
        labelColor: _textoPrincipal,
        unselectedLabelColor: _textoTenue,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'Hoy'),
          Tab(text: 'Semana'),
          Tab(text: 'Mes'),
          Tab(text: 'Total'),
        ],
      ),
    );
  }

  // ── TARJETAS RESUMEN ──────────────────────────────────────────────────────

  Widget _tarjetasResumen(DataUsageResumen r) {
    final errColor = r.totalErrores > 0 ? _rosa : _gris;
    final items = [
      _CardData('Total consumido', r.formatoLegible,
          Icons.cloud_download_rounded, _azul),
      _CardData('Solicitudes', r.totalSolicitudes.toString(),
          Icons.bolt_rounded, _verde),
      _CardData('Errores', r.totalErrores.toString(),
          Icons.warning_amber_rounded, errColor),
      _CardData(
        'Red usada',
        _labelRed(r.tipoRedPredominante),
        _iconoRed(r.tipoRedPredominante),
        _amber,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.35,
        children: items.map(_buildCard).toList(),
      ),
    );
  }

  Widget _buildCard(_CardData d) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: d.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: d.color.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: d.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(d.icono, color: d.color, size: 17),
              ),
              const SizedBox(width: 10),
              // ── FIX: FittedBox evita el overflow en cualquier tamaño ──────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.label,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: _textoSecun,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        d.valor,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: d.color,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ─────────────────────────────────────────────────────────────
            ],
          ),
        ),
      ),
    );
  }

  // ── TABLA PROCESOS ────────────────────────────────────────────────────────

  Widget _tablaProcesos(DataUsageResumen r) {
    if (r.porProceso.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Sin datos para el período seleccionado.',
            style: const TextStyle(color: _textoSecun, fontSize: 13),
          ),
        ),
      );
    }

    final totalBytes = r.totalBytes > 0 ? r.totalBytes : 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: _glassBlanco,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _glassBorde, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header de sección
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Row(
                    children: const [
                      Icon(Icons.bar_chart_rounded,
                          color: _textoSecun, size: 14),
                      SizedBox(width: 7),
                      Text(
                        'CONSUMO POR PROCESO',
                        style: TextStyle(
                          color: _textoSecun,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                // Cabecera tabla
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Row(
                    children: const [
                      Expanded(flex: 5, child: _ThCell('Proceso')),
                      Expanded(flex: 3, child: _ThCell('Consumo', right: true)),
                      Expanded(flex: 2, child: _ThCell('Req.', right: true)),
                      Expanded(flex: 2, child: _ThCell('%', right: true)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _glassBorde),
                // Filas
                ...r.porProceso.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
                  final pct = s.bytesTotal / totalBytes;
                  final color = _colorProceso(s.proceso);
                  return Column(
                    children: [
                      Container(
                        color: i.isOdd
                            ? Colors.white.withValues(alpha: 0.02)
                            : Colors.transparent,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin:
                                            const EdgeInsets.only(right: 7),
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          s.proceso.etiqueta,
                                          style: const TextStyle(
                                            color: _textoPrincipal,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    _fmtBytes(s.bytesTotal),
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    s.solicitudes.toString(),
                                    style: const TextStyle(
                                      color: _textoSecun,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${(pct * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      color: _textoTenue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct.clamp(0.0, 1.0),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.05),
                                valueColor: AlwaysStoppedAnimation(color),
                                minHeight: 3,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      if (i < r.porProceso.length - 1)
                        const Divider(height: 1, color: _glassBorde),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── GRÁFICA DÍAS ──────────────────────────────────────────────────────────

  Widget _graficaDias(DataUsageResumen r) {
    final dias = r.porDia.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxB = dias.isEmpty
        ? 1
        : dias.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: _glassBlanco,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _glassBorde),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    Icon(Icons.calendar_today_rounded,
                        color: _textoSecun, size: 13),
                    SizedBox(width: 7),
                    Text(
                      'CONSUMO DIARIO',
                      style: TextStyle(
                        color: _textoSecun,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...dias.map((e) {
                  final frac = (e.value / maxB).clamp(0.01, 1.0);
                  final label =
                      e.key.length > 5 ? e.key.substring(5) : e.key;

                  final barColor = frac > 0.75
                      ? _rosa
                      : frac > 0.45
                          ? _amber
                          : _cyan;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textoSecun,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: frac,
                                child: Container(
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: barColor.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: barColor.withValues(alpha: 0.4),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 62,
                          child: Text(
                            _fmtBytes(e.value),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: barColor,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── BOTÓN LIMPIAR ─────────────────────────────────────────────────────────

  Widget _botonLimpiar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextButton.icon(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Limpiar historial',
                  style: TextStyle(color: _textoPrincipal, fontSize: 16)),
              content: const Text(
                '¿Eliminar todos los registros de consumo de datos?',
                style: TextStyle(color: _textoSecun, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar',
                      style: TextStyle(color: _textoSecun)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Limpiar',
                      style: TextStyle(color: _rosa)),
                ),
              ],
            ),
          );
          if (ok == true) {
            await _svc.limpiarHistorial();
            _cargar();
          }
        },
        icon: const Icon(Icons.delete_outline_rounded,
            color: _textoTenue, size: 15),
        label: const Text(
          'Limpiar historial de consumo',
          style: TextStyle(color: _textoTenue, fontSize: 12),
        ),
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  String _fmtBytes(int bytes) {
    if (bytes < 1024)       return '$bytes B';
    if (bytes < 1048576)    return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  String _labelRed(String tipo) {
    switch (tipo) {
      case 'wifi':     return 'Wi-Fi';
      case 'mobile':   return 'Datos móviles';
      case 'ethernet': return 'Ethernet';
      default:         return 'Desconocido';
    }
  }

  IconData _iconoRed(String tipo) {
    switch (tipo) {
      case 'wifi':     return Icons.wifi_rounded;
      case 'mobile':   return Icons.signal_cellular_alt_rounded;
      case 'ethernet': return Icons.cable_rounded;
      default:         return Icons.device_unknown_rounded;
    }
  }

  Color _colorProceso(UsageProceso p) {
    switch (p) {
      case UsageProceso.syncSubida:   return _verde;
      case UsageProceso.syncDescarga: return _azul;
      case UsageProceso.login:        return _violeta;
      case UsageProceso.buscarLibro:  return _amber;
      case UsageProceso.ping:         return _cyan;
      case UsageProceso.producto:     return _rosa;
      case UsageProceso.otro:         return _gris;
    }
  }
}

// ── Widget auxiliar para cabecera de tabla ────────────────────────────────

class _ThCell extends StatelessWidget {
  final String text;
  final bool right;
  const _ThCell(this.text, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
        letterSpacing: 0.3,
      ),
      textAlign: right ? TextAlign.right : TextAlign.left,
    );
  }
}

// ── DTO interno ───────────────────────────────────────────────────────────

class _CardData {
  final String   label;
  final String   valor;
  final IconData icono;
  final Color    color;
  const _CardData(this.label, this.valor, this.icono, this.color);
}