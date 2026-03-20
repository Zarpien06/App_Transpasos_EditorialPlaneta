import 'package:flutter/material.dart';

class TraspasoProvider extends ChangeNotifier {
  Map<String, dynamic>? origen;
  Map<String, dynamic>? destino;
  List<Map<String, dynamic>> items = [];
  String? numeroMovimiento; // ← nuevo

  void setOrigen(Map<String, dynamic> data) {
    origen = data;
    notifyListeners();
  }

  void setDestino(Map<String, dynamic> data) {
    destino = data;
    notifyListeners();
  }

  void setNumeroMovimiento(String numero) { // ← nuevo
    numeroMovimiento = numero;
    notifyListeners();
  }

  void agregarProducto(Map<String, dynamic> producto) {
    int idx = items.indexWhere((i) => i['codigo'] == producto['codigo']);
    if (idx != -1) {
      items[idx]['cantidad'] += 1;
    } else {
      items.add({...producto, 'cantidad': 1});
    }
    notifyListeners();
  }
  
  void actualizarCantidad(int index, int cantidad) {
    items[index]['cantidad'] = cantidad;
    notifyListeners();
  }

  void eliminarProducto(int index) {
    items.removeAt(index);
    notifyListeners();
  }

  void limpiar() {
    origen = null;
    destino = null;
    items = [];
    numeroMovimiento = null; // ← limpiar también
    notifyListeners();
  }

  int get total => items.fold(0, (sum, i) => sum + (i['cantidad'] as int));
}