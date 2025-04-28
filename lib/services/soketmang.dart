// lib/services/socket_manager.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:ristocmd/services/wifichecker.dart';
import 'package:flutter/material.dart';

class SocketManager {
  static final SocketManager _instance = SocketManager._internal();
  late IO.Socket _socket;
  bool _initialized = false;
  Function(bool)? _onStatusChanged;
  bool _isOnline = false;

  factory SocketManager() => _instance;

  SocketManager._internal();

  void initialize({
    required WifiConnectionMonitor connectionMonitor,
    required BuildContext context,
    required void Function(bool) onStatusChanged,
  }) {
    if (_initialized) return;

    _onStatusChanged = onStatusChanged;
    
 _socket = IO.io('http://proristosimo.proristo.it:8080', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 3,  // Reduced from 5
      'reconnectionDelay': 500,   // Reduced from 1000ms
      'reconnectionDelayMax': 2000, // Reduced from 5000ms
      'timeout': 5000,            // Added timeout
      'pingTimeout': 5000,        // Added ping timeout
      'pingInterval': 25000,      
    });

    connectionMonitor.onStatusChanged = (isConnected) {
      if (isConnected) {
        _socket.connect();
      } else {
        _socket.disconnect();
      }
      _isOnline = isConnected;
      _onStatusChanged?.call(isConnected);
    };

    // Initial connection check
    connectionMonitor.isConnectedToWifi().then((isConnected) {
      if (isConnected) {
        _socket.connect();
      }
      _isOnline = isConnected;
      _onStatusChanged?.call(isConnected);
    });

    _initialized = true;
  }
 void emitFast(String event, dynamic data) {
    if (_isOnline) {
      _socket.emitWithAck(event, data, ack: (response) {
        if (response != null && response['status'] != 'ok') {
          // _logger.log('Server ack error: ${response['error']}');
        }
      });
    }
  }
  IO.Socket get socket {
    if (!_initialized) {
      throw Exception('SocketManager not initialized. Call initialize() first.');
    }
    return _socket;
  }

  bool get isOnline => _isOnline;

  void dispose() {
    _socket.disconnect();
    _socket.clearListeners();
    _initialized = false;
  }
}