import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/offlinecomand.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import '../Settings/settings.dart';

class CommandService {
  final AppLogger _logger;
  bool _disposed = false;

  static const String _idPalmare = '343536';
  static const String _aliasPalmare = 'test';

  final WifiConnectionMonitor connectionMonitor = WifiConnectionMonitor();

  CommandService({AppLogger? logger}) : _logger = logger ?? AppLogger();

 final OfflineCommandStorage _offlineStorage = OfflineCommandStorage();
  bool _isProcessingQueue = false;

  // Add this method to process the offline queue
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
          );

          if (response.statusCode == 200) {
            await _offlineStorage.removeCommand(command);
            _logger.log('Successfully sent offline command');
            
            // Emit table update if the command contains table info
            if (command['sala'] != null && command['tavolo'] != null) {
              _emitTableUpdate(command['sala'].toString(), command['tavolo'].toString());
            }
          }
        } catch (e) {
          _logger.log('Failed to send offline command', error: e.toString());
          // Stop processing if we encounter an error to prevent infinite retries
          break;
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // Modify the sendCompleteOrder method
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
        // Save command offline
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
        
        return {
          'success': true,
          'message': 'Command saved offline. Will be sent when connection is restored.',
          'offline': true,
        };
      }

      // Original online sending logic
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

      final encodedPayload = jsonEncode({'data': jsonEncode(payload)});
      final apiUrl = Settings.buildApiUrl(Settings.inviacomada);

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: encodedPayload,
      );

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
      _logger.log('Order successfully sent for table $tableId');
      
      // Process any pending offline commands
      unawaited(processOfflineQueue());

      return {
        'success': true,
        'message': responseBody['msg'] ?? 'Order sent successfully',
        'data': responseBody,
      };
    } catch (e) {
      _logger.log('Error sending complete order', error: e.toString());
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