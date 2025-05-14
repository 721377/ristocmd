import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
// import 'package:ristocmd/main.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/offlinecomand.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const String _storageKey = 'pending_commands';

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
        'Notifiche Ordini',
        channelDescription: 'Notifiche sullo stato degli ordini',
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
        payload: 'notifica_ordine',
      );

      _logger.log('Notifica mostrata: $title - $body');

      Future.delayed(const Duration(seconds: 3), () async {
        await _notificationsPlugin.cancel(notificationId);
        _logger.log('Notifica $notificationId cancellata automaticamente');
      });
    } catch (e) {
      _logger.log('Errore nella visualizzazione notifica', error: e.toString());
    }
  }

// Future<void> processOfflineQueue() async {
//   if (_isProcessingQueue) return;
//   _isProcessingQueue = true;

//   try {
//     final rawCommands = await getRawPendingCommands(); // new method needed
//     final now = DateTime.now();

//     for (final encoded in rawCommands) {
//       final decoded = jsonDecode(encoded) as Map<String, dynamic>;

//       final timestamp = DateTime.tryParse(decoded['timestamp'] ?? '');
//       final command = decoded['data'] as Map<String, dynamic>;

//       if (timestamp == null || now.difference(timestamp).inHours >= 1) {
//         await removeRawCommand(encoded); // removes by raw string
//         _logger.log('Comanda scaduta eliminata senza invio');
//         continue;
//       }

//       final isConnected = await connectionMonitor.isConnectedToWifi();
//       if (!isConnected) return;

//       try {
//         final response = await http.post(
//           Uri.parse(Settings.buildApiUrl(Settings.inviacomada)),
//           headers: {'Content-Type': 'application/json'},
//           body: jsonEncode({'data': jsonEncode(command)}),
//         ).timeout(const Duration(seconds: 10));

//         if (response.statusCode == 200) {
//           await removeRawCommand(encoded);
//           _logger.log('Comanda offline inviata con successo');

//           await showNotification(
//             'Comanda Sincronizzata',
//             'Ordine del tavolo ${command['tavolo']} inviato al server',
//           );

//           if (command['sala'] != null && command['tavolo'] != null) {
//             _emitTableUpdate(command['sala'].toString(), command['tavolo'].toString());
//           }
//         }
//       } catch (e) {
//         _logger.log('Errore nell\'invio della comanda offline', error: e.toString());
//         break;
//       }
//     }
//   } finally {
//     _isProcessingQueue = false;
//   }
// }

Future<void> processOfflineQueue() async {
  _logger.log('Processing offline commands');
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
              _logger.log('comanda stata inviata ');
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
        _logger.log('Processing end Processing');
    }
  }

Future<List<String>> getRawPendingCommands() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_storageKey) ?? [];
}

Future<void> removeRawCommand(String encodedCommand) async {
  final prefs = await SharedPreferences.getInstance();
  final commands = prefs.getStringList(_storageKey) ?? [];
  commands.remove(encodedCommand);
  await prefs.setStringList(_storageKey, commands);
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
      return _errorResponse('Servizio terminato', 'CommandService è stato terminato');
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
          'Ordine Salvato Offline',
          'L\'ordine del tavolo $tableId sarà inviato quando ci sarà connessione',
        );

        return {
          'success': true,
          'message': 'Ordine salvato offline. Sarà inviato appena possibile.',
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
      _logger.log('Richiesta HTTP completata in ${stopwatch.elapsedMilliseconds}ms');

      if (response.statusCode != 200) {
        throw Exception('Errore API: ${response.statusCode} - ${response.body}');
      }

      final responseBody = jsonDecode(response.body);
      if (responseBody is! Map<String, dynamic>) {
        return {'success': true, 'message': 'Ordine elaborato', 'data': {}};
      }

      if (responseBody['status'] == 'ko') {
        final errorMsg = responseBody['msg'] ?? 'Errore sconosciuto del server';
        return _errorResponse(errorMsg, 'Il server ha rifiutato l\'ordine');
      }

      _emitTableUpdate(salaId, tableId);
      await showNotification(
        'Ordine Inviato',
        'L\'ordine del tavolo $tableId è stato ricevuto dal server',
      );

      unawaited(processOfflineQueue());

      return {
        'success': true,
        'message': responseBody['msg'] ?? 'Ordine inviato con successo',
        'data': responseBody,
      };
    } catch (e) {
      _logger.log('Errore durante l\'invio della comanda', error: e.toString());
      await showNotification(
        'Errore Ordine',
        'Invio ordine tavolo $tableId fallito: ${e.toString().replaceAll(RegExp(r'^Exception: '), '')}',
      );
      return _errorResponse('Errore nell\'invio dell\'ordine', e.toString());
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
      await tableLockManager.updateLocalDatabaseWithOccupiedStatus(tableId, true);
      tableLockManager.onTableOccupiedUpdated(tableId, true);

      final success = await tableLockManager.emitTableUpdate(
        tavoloid: tableId,
        salaid: salaId,
      );

      if (!success) {
        _logger.log('Fallita l\'emissione aggiornamento tavolo $tableId');
      }
    } catch (e) {
      _logger.log('Errore aggiornamento tavolo', error: e.toString());
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
    _logger.log('CommandService terminato');
  }
}
