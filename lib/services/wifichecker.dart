import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class WifiConnectionMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Function(bool isConnected)? onStatusChanged;

  final List<Function(bool)> _connectionListeners = [];

  void addConnectionListener(Function(bool) listener) {
    _connectionListeners.add(listener);
  }

  void removeConnectionListener(Function(bool) listener) {
    _connectionListeners.remove(listener);
  }
  
void startMonitoring() {
    _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isWifiConnected = results.contains(ConnectivityResult.wifi);
      
      // Notify all listeners
      for (final listener in _connectionListeners) {
        listener(isWifiConnected);
      }

      if (onStatusChanged != null) {
        onStatusChanged!(isWifiConnected);
      }

      if (isWifiConnected) {
        print('Connected to Wi-Fi');
      } else {
        print('Not connected to Wi-Fi (or no connection)');
      }
    });
  }
  void stopMonitoring() {
    _subscription?.cancel();
  }


  Future<bool> isConnectedToWifi() async {
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  // Helper method to check if we're specifically NOT connected to WiFi
  // (but might have mobile data or other connections)
  Future<bool> isNotConnectedToWifi() async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.wifi);
  }

  
}