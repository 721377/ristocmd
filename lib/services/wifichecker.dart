import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class WifiConnectionMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Function(bool isConnected)? onStatusChanged;
  Timer? _recheckTimer;
  
  // Interval for automatic rechecking (default 30 seconds)
  Duration recheckInterval = const Duration(seconds: 30);

  final List<Function(bool)> _connectionListeners = [];

  void addConnectionListener(Function(bool) listener) {
    _connectionListeners.add(listener);
  }

  void removeConnectionListener(Function(bool) listener) {
    _connectionListeners.remove(listener);
  }
  
  void startMonitoring() {
    // Initial check
    _checkConnection();
    
    // Listen for connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _updateConnectionStatus(results);
    });
    
    // Setup periodic rechecking
    _startRecheckTimer();
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _recheckTimer?.cancel();
  }

  void _startRecheckTimer() {
    _recheckTimer?.cancel(); // Cancel existing timer if any
    _recheckTimer = Timer.periodic(recheckInterval, (timer) async {
      await _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      print('Error checking connection: $e');
      // Notify listeners of potential disconnection
      _updateConnectionStatus([ConnectivityResult.none]);
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
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
  }

  Future<bool> isConnectedToWifi() async {
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  Future<bool> isNotConnectedToWifi() async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.wifi);
  }
}