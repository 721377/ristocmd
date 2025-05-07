import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:ristocmd/main.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/offlinecomand.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import '../Settings/settings.dart';

class CommandService {
  final AppLogger _logger;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _disposed = false;

  static const String _idPalmare = '343536';
  static const String _aliasPalmare = 'test';

  final WifiConnectionMonitor connectionMonitor = WifiConnectionMonitor();
  final OfflineCommandStorage _offlineStorage = OfflineCommandStorage();
  bool _isProcessingQueue = false;

  CommandService({
    AppLogger? logger,
    required FlutterLocalNotificationsPlugin notificationsPlugin,
  }) : _logger = logger ?? AppLogger(),
       _notificationsPlugin = notificationsPlugin;
Future<void> showNotification(String title, String body) async {
  try {
    final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'order_channel',
      'Order Notifications',
      channelDescription: 'Notifications about order status',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
      enableVibration: true,
      color: Colors.green,
      ledColor: Colors.green,
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      platformDetails,
      payload: 'order_notification',
    );

    _logger.log('Notification shown: $title - $body');

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () async {
      await _notificationsPlugin.cancel(notificationId);
      _logger.log('Notification $notificationId auto-cancelled');
    });

  } catch (e) {
    _logger.log('Failed to show notification', error: e.toString());
  }
}


  Future<void> processOfflineQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final commands = await _offlineStorage.getPendingCommands();
      if (commands.isEmpty) return;

      final isConnected = await connectionMonitor.isConnectedToWifi();
      if (!isConnected) return;

      _logger.log('Processing ${commands.length} offline commands');

      for (final command in commands) {
        try {
          final response = await http.post(
            Uri.parse(Settings.buildApiUrl(Settings.inviacomada)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'data': jsonEncode(command)}),
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            await _offlineStorage.removeCommand(command);
            _logger.log('Successfully sent offline command');
            
            await showNotification(
              'Command Synchronized',
              'Table ${command['tavolo']} order was sent to the server',
            );

            if (command['sala'] != null && command['tavolo'] != null) {
              _emitTableUpdate(command['sala'].toString(), command['tavolo'].toString());
            }
          }
        } catch (e) {
          _logger.log('Failed to send offline command', error: e.toString());
          break;
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<Map<String, dynamic>> sendCompleteOrder({
    required String tableId,
    required String salaId,
    required String pv,
    required String userId,
    required List<Map<String, dynamic>> orderItems,
    String operationType = 'Comanda',
    bool noPrint = false,
    bool printClientOrder = true,
    required BuildContext context,
  }) async {
    if (_disposed) {
      return _errorResponse('Service disposed', 'CommandService has been disposed');
    }

    connectionMonitor.startMonitoring();
    SocketManager().initialize(
      connectionMonitor: connectionMonitor,
      context: context,
      onStatusChanged: (_) {},
    );

    try {
      final isConnected = await connectionMonitor.isConnectedToWifi();
      
      if (!isConnected) {
        final payload = _buildOrderPayload(
          sala: salaId,
          tavolo: tableId,
          pv: pv,
          idUtente: userId,
          comanda: orderItems,
          tipoOperazione: operationType,
          noStampa: noPrint,
          stampaCliComanda: printClientOrder,
        );

        await _offlineStorage.saveCommand(payload);
        
        await showNotification(
          'Order Saved Offline',
          'Table $tableId order will be sent when connection is available',
        );
        
        return {
          'success': true,
          'message': 'Command saved offline. Will be sent when connection is restored.',
          'offline': true,
        };
      }

      final stopwatch = Stopwatch()..start();
      final payload = _buildOrderPayload(
        sala: salaId,
        tavolo: tableId,
        pv: pv,
        idUtente: userId,
        comanda: orderItems,
        tipoOperazione: operationType,
        noStampa: noPrint,
        stampaCliComanda: printClientOrder,
      );

      final response = await http.post(
        Uri.parse(Settings.buildApiUrl(Settings.inviacomada)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': jsonEncode(payload)}),
      ).timeout(const Duration(seconds: 15));

      stopwatch.stop();
      _logger.log('HTTP request completed in ${stopwatch.elapsedMilliseconds}ms');

      if (response.statusCode != 200) {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }

      final responseBody = jsonDecode(response.body);
      if (responseBody is! Map<String, dynamic>) {
        return {'success': true, 'message': 'Order processed', 'data': {}};
      }

      if (responseBody['status'] == 'ko') {
        final errorMsg = responseBody['msg'] ?? 'Unknown server error';
        return _errorResponse(errorMsg, 'Server rejected the order');
      }

      _emitTableUpdate(salaId, tableId);
      await showNotification(
        'Order Sent Successfully',
        'Table $tableId order was received by the server',
      );

      unawaited(processOfflineQueue());

      return {
        'success': true,
        'message': responseBody['msg'] ?? 'Order sent successfully',
        'data': responseBody,
      };
    } catch (e) {
      _logger.log('Error sending complete order', error: e.toString());
      await showNotification(
        'Order Failed',
        'Failed to send table $tableId order: ${e.toString().replaceAll(RegExp(r'^Exception: '), '')}',
      );
      return _errorResponse('Failed to send order', e.toString());
    }
  }

  Map<String, dynamic> _buildOrderPayload({
    required String sala,
    required String tavolo,
    required String pv,
    required String idUtente,
    required List<Map<String, dynamic>> comanda,
    required String tipoOperazione,
    required bool noStampa,
    required bool stampaCliComanda,
  }) {
    return {
      'sala': sala,
      'tavolo': tavolo,
      'pv': pv,
      'id_utente': idUtente,
      'comanda': comanda,
      'tipo_operazione': tipoOperazione,
      'no_stampa': noStampa,
      'timer_start': DateTime.now().toIso8601String(),
      'identita': 'palmare',
      'reject_no_identify': false,
      'id_palmare': _idPalmare,
      'alias_palmare': _aliasPalmare,
      'stampa_cli_comanda': stampaCliComanda,
    };
  }

  void _emitTableUpdate(String salaId, String tableId) async {
    try {
      final tableLockManager = TableLockService().manager;
      final success = await tableLockManager.emitTableUpdate(
        tavoloid: tableId,
        salaid: salaId,
      );

      if (!success) {
        _logger.log('Failed to emit table update for table $tableId');
      }
    } catch (e) {
      _logger.log('Emit table update failed', error: e.toString());
    }
  }

  Map<String, dynamic> _errorResponse(String message, String error) {
    return {
      'success': false,
      'message': message,
      'error': error,
    };
  }

  void dispose() {
    _disposed = true;
    _logger.log('CommandService disposed');
  }
}