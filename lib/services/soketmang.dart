import 'dart:async';
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
  int? _wsPort;
  WifiConnectionMonitor? _connectionMonitor;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  final BuildContext? _context;

  factory SocketManager() => _instance;

  SocketManager._internal() : _context = null;

  SocketManager.forTest(this._context);

  Future<void> _ensureBaseUrlAndPort() async {
    await Settings.loadAllSettings();
    _baseUrl = Settings.baseUrl;
    _wsPort = Settings.wsPort;

    if (_baseUrl != null && _baseUrl!.isNotEmpty) {
      _baseUrl = _baseUrl!.replaceAll(RegExp(r'/+$'), '');
      if (!_baseUrl!.startsWith('http://') && !_baseUrl!.startsWith('https://')) {
        _baseUrl = 'http://$_baseUrl';
      }
    }
  }

  Future<void> initialize({
    required WifiConnectionMonitor connectionMonitor,
    required BuildContext context,
    required void Function(bool) onStatusChanged,
  }) async {
    if (_initialized) return;

    _connectionMonitor = connectionMonitor;
    _onStatusChanged = onStatusChanged;

    try {
      await _ensureBaseUrlAndPort();

      if (_baseUrl == null || _baseUrl!.isEmpty) {
        throw Exception('Base URL is not set. Please configure it first.');
      }

      _setupSocket();
      _connectionMonitor!.addConnectionListener(_handleConnectionChange);
      _connectionMonitor!.startMonitoring();

      final isConnected = await _connectionMonitor!.isConnectedToWifi();
      if (isConnected) {
        await _attemptConnection();
      }

      _initialized = true;
    } catch (e) {
      _handleInitializationError(e);
      rethrow;
    }
  }

  void _setupSocket() {
    final uri = Uri.parse(_baseUrl!);
    final host = uri.host;
    final port = _wsPort ?? uri.port;
    final scheme = uri.scheme;

    final url = '$scheme://$host:$port';

    _socket = IO.io(
      url,
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/socket.io')
        .disableAutoConnect()
        .setTimeout(10000)
        .setReconnectionDelay(1000)
        .setReconnectionAttempts(_maxReconnectAttempts)
        .enableForceNewConnection()
        .build(),
    );

    _socket.onConnect((_) {
      _reconnectAttempts = 0;
      _isOnline = true;
      _cancelReconnectTimer();
      _onStatusChanged?.call(true);
      _showConnectionMessage('Connected to server');
    });

    _socket.onDisconnect((_) => _handleDisconnect());
    _socket.onError((_) => _handleDisconnect());
    _socket.onConnectError((_) => _handleDisconnect());
    _socket.onReconnectAttempt((attempt) {
      _showConnectionMessage('Reconnecting... Attempt ${attempt + 1}/$_maxReconnectAttempts');
    });
  }

  void _handleDisconnect() {
    _isOnline = false;
    _onStatusChanged?.call(false);
    if (!_manualDisconnect) {
      _reconnectAttempts++;
      if (_reconnectAttempts <= _maxReconnectAttempts) {
        _scheduleReconnection();
      } else {
        _showConnectionMessage('Max reconnection attempts reached');
        _cancelReconnectTimer();
      }
    }
  }
void closeConnection() {
  _manualDisconnect = true;
  _cancelReconnectTimer();
  _socket.disconnect();
  _isOnline = false;
  _onStatusChanged?.call(false);
}


  void _handleConnectionChange(bool isConnected) async {
    if (isConnected) {
      await _attemptConnection();
    } else {
      _manualDisconnect = true;
      _socket.disconnect();
      _manualDisconnect = false;
    }
  }

  Future<void> _attemptConnection() async {
    try {
      await _ensureBaseUrlAndPort();
      if (!_socket.connected) {
        _socket.connect();
        // Wait for connection with a Future completer
        final completer = Completer<void>();
        late void Function(dynamic) handler;

        handler = (_) {
          _socket.off('connect', handler);
          completer.complete();
        };

        _socket.on('connect', handler);

        await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _socket.off('connect', handler);
            throw TimeoutException('Connection timeout');
          },
        );
      }
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  void _scheduleReconnection() {
    _cancelReconnectTimer();
    if (!_manualDisconnect) {
      _reconnectTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
        if (await _connectionMonitor?.isConnectedToWifi() ?? false) {
          await _attemptConnection();
          if (_socket.connected) {
            timer.cancel();
          }
        }
      });
    }
  }

  void _handleInitializationError(dynamic error) {
    _isOnline = false;
    _onStatusChanged?.call(false);
    _showConnectionMessage('Initialization error: ${error.toString()}');
  }

  void _handleConnectionError(dynamic error) {
    _isOnline = false;
    _onStatusChanged?.call(false);
    _showConnectionMessage('Connection error: ${error.toString()}');
    _scheduleReconnection();
  }

  void _showConnectionMessage(String message) {
    if (_context != null && _isContextMounted(_context!)) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: 2),
        ),
      );
    }
    print('SocketManager: $message');
  }

  // Safely check if context is mounted
  bool _isContextMounted(BuildContext context) {
    return context is Element && context.mounted;
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void emitFast(String event, dynamic data) {
    if (_isOnline) {
      try {
        _socket.emitWithAck(event, data, ack: (response) {
          if (response != null && response['status'] != 'ok') {
            // Optional: handle error response
          }
        });
      } catch (_) {
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
    _manualDisconnect = true;
    _socket.disconnect();
    _socket.clearListeners();
    _connectionMonitor?.removeConnectionListener(_handleConnectionChange);
    _connectionMonitor?.stopMonitoring();
    _cancelReconnectTimer();
    _initialized = false;
  }

  Future<void> updateBaseUrl(String newUrl) async {
    _baseUrl = newUrl;
    if (_initialized) {
      dispose();
    }
  }

  Future<void> updatePort(int newPort) async {
    _wsPort = newPort;
    await Settings.updateSetting('wsport', newPort);

    if (_initialized) {
      dispose();
    }
  }
}
