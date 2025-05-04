// lib/services/socket_manager.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:ristocmd/services/wifichecker.dart';
import 'package:flutter/material.dart';
import 'package:ristocmd/Settings/settings.dart';

class SocketManager {
  static final SocketManager _instance = SocketManager._internal();
  late IO.Socket _socket;
  bool _initialized = false;
  Function(bool)? _onStatusChanged;
  bool _isOnline = false;
  String? _baseUrl;

  factory SocketManager() => _instance;

  SocketManager._internal();

  Future<void> _ensureBaseUrl() async {
    if (_baseUrl == null) {
      await Settings.loadBaseUrl();
      _baseUrl = Settings.baseUrl;
      
      // Validate the base URL format
      if (_baseUrl != null && _baseUrl!.isNotEmpty) {
        // Ensure URL has proper protocol and no trailing slashes
        _baseUrl = _baseUrl!.replaceAll(RegExp(r'/+$'), '');
        if (!_baseUrl!.startsWith('http://') && !_baseUrl!.startsWith('https://')) {
          _baseUrl = 'http://$_baseUrl';
        }
      }
    }
  }

  Future<void> initialize({
    required WifiConnectionMonitor connectionMonitor,
    required BuildContext context,
    required void Function(bool) onStatusChanged,
  }) async {
    if (_initialized) return;

    await _ensureBaseUrl();
    
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      throw Exception('Base URL is not set. Please configure it first.');
    }

    _onStatusChanged = onStatusChanged;
    
    final socketUrl = '$_baseUrl:8080';
    
    _socket = IO.io(socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false, // Changed to false to prevent auto-connect before URL validation
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 3,
      'reconnectionDelay': 500,
      'reconnectionDelayMax': 2000,
      'timeout': 5000,
      'pingTimeout': 5000,
      'pingInterval': 25000,
    });

    // Setup socket event listeners
    _socket.onConnect((_) {
      _isOnline = true;
      _onStatusChanged?.call(true);
    });

    _socket.onDisconnect((_) {
      _isOnline = false;
      _onStatusChanged?.call(false);
    });

    _socket.onError((data) {
      _isOnline = false;
      _onStatusChanged?.call(false);
    });

    connectionMonitor.onStatusChanged = (isConnected) async {
      if (isConnected) {
        try {
          await _ensureBaseUrl(); // Re-check URL in case it changed
          if (_baseUrl != null && _baseUrl!.isNotEmpty) {
            _socket.connect();
          }
        } catch (e) {
          _isOnline = false;
          _onStatusChanged?.call(false);
        }
      } else {
        _socket.disconnect();
      }
      _isOnline = isConnected;
      _onStatusChanged?.call(isConnected);
    };

    // Initial connection check
    connectionMonitor.isConnectedToWifi().then((isConnected) async {
      if (isConnected && _baseUrl != null && _baseUrl!.isNotEmpty) {
        try {
          _socket.connect();
        } catch (e) {
          _isOnline = false;
          _onStatusChanged?.call(false);
        }
      }
      _isOnline = isConnected;
      _onStatusChanged?.call(isConnected);
    });

    _initialized = true;
  }

  void emitFast(String event, dynamic data) {
    if (_isOnline) {
      try {
        _socket.emitWithAck(event, data, ack: (response) {
          if (response != null && response['status'] != 'ok') {
            // _logger.log('Server ack error: ${response['error']}');
          }
        });
      } catch (e) {
        _isOnline = false;
        _onStatusChanged?.call(false);
      }
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

  // Add a method to update base URL if it changes
  Future<void> updateBaseUrl(String newUrl) async {
    _baseUrl = newUrl;
    if (_initialized) {
      dispose();
      _initialized = false;
    }
  }
}
