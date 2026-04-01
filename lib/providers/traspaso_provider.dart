// lib/providers/traspaso_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// ESTADO GLOBAL DEL TRASPASO CON RIVERPOD
//
// Responsabilidades:
//   1. Mantener estado de: origen, destino, items, total, numeroMovimiento
//   2. Métodos: agregarProducto, eliminarProducto, actualizarCantidad, limpiar
//   3. Accesible desde cualquier pantalla via ref.read/ref.watch
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart'; // kMaxTotal

// ─────────────────────────────────────────────────────────────────────────────
// RESULTADO DE agregarProducto
// ─────────────────────────────────────────────────────────────────────────────

enum AgregarResultado { ok, actualizado, excedeLimite }

// ─────────────────────────────────────────────────────────────────────────────
// MODELO DE ESTADO
// ─────────────────────────────────────────────────────────────────────────────

class TraspasoState {
  final Map<String, dynamic>? origen;
  final Map<String, dynamic>? destino;
  final List<Map<String, dynamic>> items;
  final String? numeroMovimiento;
  final bool confirmado;

  const TraspasoState({
    this.origen,
    this.destino,
    this.items = const [],
    this.numeroMovimiento,
    this.confirmado = false,
  });

  /// Suma de todas las cantidades de los items.
  int get total =>
      items.fold(0, (sum, item) => sum + ((item['cantidad'] as int?) ?? 0));

  /// Unidades que aún se pueden agregar sin superar kMaxTotal.
  int get disponibles => kMaxTotal - total;

  TraspasoState copyWith({
    Map<String, dynamic>? origen,
    Map<String, dynamic>? destino,
    List<Map<String, dynamic>>? items,
    String? numeroMovimiento,
    bool? confirmado,
  }) {
    return TraspasoState(
      origen:           origen           ?? this.origen,
      destino:          destino          ?? this.destino,
      items:            items            ?? this.items,
      numeroMovimiento: numeroMovimiento ?? this.numeroMovimiento,
      confirmado:       confirmado       ?? this.confirmado,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class TraspasoNotifier extends StateNotifier<TraspasoState> {
  TraspasoNotifier() : super(const TraspasoState());

  // ── Getters de conveniencia (delegados al estado) ─────────────────────────

  Map<String, dynamic>?      get origen           => state.origen;
  Map<String, dynamic>?      get destino          => state.destino;
  List<Map<String, dynamic>> get items            => state.items;
  int                        get total            => state.total;
  int                        get disponibles      => state.disponibles;
  String?                    get numeroMovimiento => state.numeroMovimiento;

  // ── Búsqueda ──────────────────────────────────────────────────────────────

  /// Devuelve true si ya existe un item con ese código.
  bool existe(String codigo) =>
      state.items.any((e) => e['codigo'] == codigo);

  /// Devuelve el índice del item con ese código, o -1 si no existe.
  int indexOf(String codigo) =>
      state.items.indexWhere((e) => e['codigo'] == codigo);

  // ── Setters ───────────────────────────────────────────────────────────────

  void setOrigen(Map<String, dynamic> origen) =>
      state = state.copyWith(origen: origen);

  void setDestino(Map<String, dynamic> destino) =>
      state = state.copyWith(destino: destino);

  void setNumeroMovimiento(String numero) =>
      state = state.copyWith(numeroMovimiento: numero);

  void confirmar() => state = state.copyWith(confirmado: true);

  void limpiar() => state = const TraspasoState();

  // ── Lógica de items ───────────────────────────────────────────────────────

  /// Agrega [cantidad] unidades del [libro].
  ///
  /// - Si el libro ya está en la lista, suma la cantidad → [AgregarResultado.actualizado].
  /// - Si al sumar se supera kMaxTotal → [AgregarResultado.excedeLimite].
  /// - Si es nuevo y cabe → [AgregarResultado.ok].
  AgregarResultado agregarProducto(
      Map<String, dynamic> libro, int cantidad) {
    final codigo = libro['codigo'] as String? ?? '';
    final idx    = indexOf(codigo);
    final nuevosItems = List<Map<String, dynamic>>.from(state.items);

    if (idx != -1) {
      // Ya existe → sumar cantidad
      final nuevaCantidad =
          (nuevosItems[idx]['cantidad'] as int) + cantidad;
      if (state.total + cantidad > kMaxTotal) {
        return AgregarResultado.excedeLimite;
      }
      nuevosItems[idx] = {
        ...nuevosItems[idx],
        'cantidad': nuevaCantidad,
      };
      state = state.copyWith(items: nuevosItems);
      return AgregarResultado.actualizado;
    } else {
      // No existe → insertar
      if (state.total + cantidad > kMaxTotal) {
        return AgregarResultado.excedeLimite;
      }
      nuevosItems.add({
        'codigo':      codigo,
        'descripcion': libro['descripcion'] ?? '',
        'cantidad':    cantidad,
        'manual':      libro['manual'] ?? false,
      });
      state = state.copyWith(items: nuevosItems);
      return AgregarResultado.ok;
    }
  }

  /// Actualiza la cantidad del item en [index].
  /// Devuelve false si la nueva cantidad excede kMaxTotal.
  bool actualizarCantidad(int index, int cantidad) {
    if (index < 0 || index >= state.items.length) return false;

    final cantidadActual =
        (state.items[index]['cantidad'] as int?) ?? 0;
    final diferencia = cantidad - cantidadActual;

    if (state.total + diferencia > kMaxTotal) return false;

    final nuevosItems = List<Map<String, dynamic>>.from(state.items);
    nuevosItems[index] = {
      ...nuevosItems[index],
      'cantidad': cantidad,
    };
    state = state.copyWith(items: nuevosItems);
    return true;
  }

  /// Elimina el item en [index].
  void eliminarProducto(int index) {
    if (index < 0 || index >= state.items.length) return;
    final nuevosItems =
        List<Map<String, dynamic>>.from(state.items)..removeAt(index);
    state = state.copyWith(items: nuevosItems);
  }

  // ── Aliases para compatibilidad ───────────────────────────────────────────

  void addItem(Map<String, dynamic> item) =>
      agregarProducto(item, (item['cantidad'] as int?) ?? 1);

  void removeItem(int index) => eliminarProducto(index);
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

final traspasoProvider =
    StateNotifierProvider<TraspasoNotifier, TraspasoState>((ref) {
  return TraspasoNotifier();
});

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS DERIVADOS
// ─────────────────────────────────────────────────────────────────────────────

final traspasoItemsProvider =
    Provider<List<Map<String, dynamic>>>(
        (ref) => ref.watch(traspasoProvider).items);

final traspasoTotalProvider =
    Provider<int>((ref) => ref.watch(traspasoProvider).total);

final traspasoDisponiblesProvider =
    Provider<int>((ref) => ref.watch(traspasoProvider).disponibles);

final traspasoOrigenProvider = Provider<Map<String, dynamic>?>(
    (ref) => ref.watch(traspasoProvider).origen);

final traspasoDestinoProvider = Provider<Map<String, dynamic>?>(
    (ref) => ref.watch(traspasoProvider).destino);

final traspasoNumeroMovimientoProvider =
    Provider<String?>((ref) => ref.watch(traspasoProvider).numeroMovimiento);

final traspasoConfirmadoProvider =
    Provider<bool>((ref) => ref.watch(traspasoProvider).confirmado);

final traspasoListoParaConfirmarProvider = Provider<bool>((ref) {
  final s = ref.watch(traspasoProvider);
  return s.origen != null && s.destino != null && s.items.isNotEmpty;
});

final traspasoItemsCountProvider =
    Provider<int>((ref) => ref.watch(traspasoProvider).items.length);