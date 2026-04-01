// ───────────────────────────────────────────────────────────────────────────── 
// Detecta si el dispositivo tiene conexión a internet o no. 
// Expone un Stream para que cualquier widget de la app pueda reaccionar 
// en tiempo real al cambio online ↔ offline. 
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();

  Stream<bool> get onlineStream => _onlineController.stream;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  StreamSubscription? _subscription;

  Future<void> init() async {
    _isOnline = await _checkOnline();
    _onlineController.add(_isOnline);

    _subscription =
        _connectivity.onConnectivityChanged.listen((results) async {
      final online = _resultsToOnline(results);

      if (online != _isOnline) {
        _isOnline = online;
        _onlineController.add(_isOnline);
      }
    });
  }

  Future<bool> _checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _resultsToOnline(results);
  }

  
  bool _resultsToOnline(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.mobile) ||
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  void dispose() {
    _subscription?.cancel();
    _onlineController.close();
  }
}