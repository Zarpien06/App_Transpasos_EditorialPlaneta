// lib/widgets/sync_log_panel.dart
//
// Panel de logs de sincronización en tiempo real.
// Sustituye el botón de sync del admin dashboard.
// Se suscribe al Stream de SyncLogService y muestra cada evento
// con su estado real: OK · OMITIDO · ERROR · EN PROCESO.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sync_log_service.dart';

class SyncLogPanel extends StatefulWidget {
  /// Altura máxima del panel (por defecto ocupa lo que necesite hasta 420 px).
  final double maxHeight;
  const SyncLogPanel({super.key, this.maxHeight = 420});

  @override
  State<SyncLogPanel> createState() => _SyncLogPanelState();
}

class _SyncLogPanelState extends State<SyncLogPanel> {
  final _logService    = SyncLogService();
  final _scrollCtrl    = ScrollController();
  StreamSubscription<List<SyncLogEntry>>? _sub;
  List<SyncLogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _entries = _logService.entries;          // carga inicial desde caché
    _sub = _logService.stream.listen((list) {
      if (!mounted) return;
      setState(() => _entries = list);
      // Auto-scroll al tope (más reciente primero)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            0,
            duration : const Duration(milliseconds: 300),
            curve    : Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Paleta de estados ───────────────────────────────────────────────────

  Color _colorEstado(SyncLogEstado e, ColorScheme cs) {
    switch (e) {
      case SyncLogEstado.ok:        return const Color(0xFF22C55E); // green-500
      case SyncLogEstado.omitido:   return const Color(0xFFF59E0B); // amber-500
      case SyncLogEstado.fallido:   return const Color(0xFFEF4444); // red-500
      case SyncLogEstado.enProceso: return cs.primary;
    }
  }

  IconData _iconEstado(SyncLogEstado e) {
    switch (e) {
      case SyncLogEstado.ok:        return Icons.check_circle_rounded;
      case SyncLogEstado.omitido:   return Icons.remove_circle_rounded;
      case SyncLogEstado.fallido:   return Icons.cancel_rounded;
      case SyncLogEstado.enProceso: return Icons.sync_rounded;
    }
  }

  Color _colorTipo(SyncLogTipo t) {
    switch (t) {
      case SyncLogTipo.descarga: return const Color(0xFF38BDF8); // sky-400
      case SyncLogTipo.subida:   return const Color(0xFFA78BFA); // violet-400
      case SyncLogTipo.sistema:  return const Color(0xFF94A3B8); // slate-400
      case SyncLogTipo.producto: return const Color(0xFF34D399); // emerald-400
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final surf  = cs.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Cabecera ──────────────────────────────────────────────────────
        _Header(entries: _entries, onClear: _confirmarLimpiar),

        const SizedBox(height: 8),

        // ── Lista de logs ─────────────────────────────────────────────────
        Container(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          decoration: BoxDecoration(
            color        : surf.withValues(alpha:0.45),
            borderRadius : BorderRadius.circular(12),
            border       : Border.all(color: cs.outlineVariant.withValues(alpha:0.4)),
          ),
          child: _entries.isEmpty
              ? _EmptyState()
              : ListView.separated(
                  controller    : _scrollCtrl,
                  padding       : const EdgeInsets.symmetric(vertical: 6),
                  itemCount     : _entries.length,
                  separatorBuilder: (_, __) => Divider(
                    height  : 1,
                    indent  : 52,
                    color   : cs.outlineVariant.withValues(alpha:0.25),
                  ),
                  itemBuilder: (context, i) {
                    final entry = _entries[i];
                    return _LogTile(
                      entry      : entry,
                      colorEstado: _colorEstado(entry.estado, cs),
                      iconEstado : _iconEstado(entry.estado),
                      colorTipo  : _colorTipo(entry.tipo),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Limpiar logs con confirmación ────────────────────────────────────────

  Future<void> _confirmarLimpiar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title   : const Text('Limpiar historial'),
        content : const Text('¿Eliminar todos los logs de sincronización?'),
        actions : [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child    : const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child    : const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok == true) await _logService.limpiar();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBWIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final List<SyncLogEntry> entries;
  final VoidCallback onClear;
  const _Header({required this.entries, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final oks      = entries.where((e) => e.estado == SyncLogEstado.ok).length;
    final omitidos = entries.where((e) => e.estado == SyncLogEstado.omitido).length;
    final errores  = entries.where((e) => e.estado == SyncLogEstado.fallido).length;

    return Row(
      children: [
       Icon(Icons.terminal_rounded, size: 18, color: cs.primary),
       const SizedBox(width: 8),
       Flexible(
         child: Text(
           'Log de sincronización',
           style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
           overflow: TextOverflow.ellipsis,
         ),
       ),
       const SizedBox(width: 8),
        // Chips de resumen
        if (entries.isNotEmpty) ...[
          _Chip(label: '$oks OK',          color: const Color(0xFF22C55E)),
          const SizedBox(width: 4),
          _Chip(label: '$omitidos omit.',  color: const Color(0xFFF59E0B)),
          const SizedBox(width: 4),
          _Chip(label: '$errores err.',    color: const Color(0xFFEF4444)),
          const SizedBox(width: 8),
        ],
        // Botón limpiar
        IconButton(
          icon      : const Icon(Icons.delete_sweep_rounded, size: 18),
          tooltip   : 'Limpiar log',
          onPressed : entries.isEmpty ? null : onClear,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color        : color.withValues(alpha: 0.12),
        borderRadius : BorderRadius.circular(6),
        border       : Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _LogTile extends StatelessWidget {
  final SyncLogEntry entry;
  final Color        colorEstado;
  final IconData     iconEstado;
  final Color        colorTipo;

  const _LogTile({
    required this.entry,
    required this.colorEstado,
    required this.iconEstado,
    required this.colorTipo,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final spinning = entry.estado == SyncLogEstado.enProceso;

    return ExpansionTile(
      tilePadding     : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      childrenPadding : const EdgeInsets.fromLTRB(52, 0, 16, 10),
      leading: _AnimatedIcon(
        icon    : iconEstado,
        color   : colorEstado,
        spin    : spinning,
      ),
      title: Text(
        entry.mensaje,
        style: tt.bodySmall?.copyWith(
          fontWeight : FontWeight.w500,
          color      : spinning
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
      subtitle: Row(
        children: [
          Container(
            padding   : const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color        : colorTipo.withValues(alpha: 0.12),
              borderRadius : BorderRadius.circular(4),
            ),
            child: Text(
              entry.tipoLabel,
              style: TextStyle(fontSize: 9, color: colorTipo, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatTimestamp(entry.timestamp),
            style: tt.labelSmall?.copyWith(
              color   : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),

      // Si no hay nada que expandir, deshabilitamos la expansión
      onExpansionChanged: (entry.detalle == null &&
              entry.uuid == null &&
              entry.manuca == null)
          ? (_) {}
          : null,

      // Detalle expandible (solo si hay detalle o uuid)
      children: [
        if (entry.detalle != null)
          _DetalleRow(label: 'Detalle', value: entry.detalle!),
        if (entry.uuid != null)
          _DetalleRow(label: 'UUID', value: entry.uuid!),
        if (entry.manuca != null)
          _DetalleRow(label: 'Manuca', value: entry.manuca!),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month} $h:$m:$s';
  }
}

class _DetalleRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetalleRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text('$label:',
                style: TextStyle(
                    fontSize        : 10,
                    fontWeight      : FontWeight.w700,
                    color           : cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize  : 10,
                    fontFamily: 'monospace',
                    color     : cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded,
                size  : 36,
                color : Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Text('Sin eventos de sincronización',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    )),
          ],
        ),
      ),
    );
  }
}

// Ícono que gira cuando está en proceso
class _AnimatedIcon extends StatefulWidget {
  final IconData icon;
  final Color    color;
  final bool     spin;
  const _AnimatedIcon({
    required this.icon,
    required this.color,
    this.spin = false,
  });
  @override
  State<_AnimatedIcon> createState() => _AnimatedIconState();
}

class _AnimatedIconState extends State<_AnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(seconds: 1),
    );
    if (widget.spin) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_AnimatedIcon old) {
    super.didUpdateWidget(old);
    if (widget.spin && !_ctrl.isAnimating) _ctrl.repeat();
    if (!widget.spin && _ctrl.isAnimating) _ctrl.stop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.spin) {
      return Icon(widget.icon, color: widget.color, size: 20);
    }
    return RotationTransition(
      turns: _ctrl,
      child: Icon(widget.icon, color: widget.color, size: 20),
    );
  }
}