// lib/services/table_lock_manager.dart
import 'dart:async';

import 'package:ristocmd/services/soketmang.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:flutter/material.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/wifichecker.dart';

class TableLockManager {
  final IO.Socket socket;
  final Function(String, bool) onTableOccupiedUpdated;
  final String clientName;
  final DataRepository dataRepository;
  final BuildContext context;
  final AppLogger _logger = AppLogger();
  final WifiConnectionMonitor connectionMonitor;

  bool _disposed = false;
  List<Map<String, dynamic>> _pendingTableUpdates = [];

  TableLockManager({
    required this.socket,
    required this.onTableOccupiedUpdated,
    required this.clientName,
    required this.dataRepository,
    required this.context,
    required this.connectionMonitor,
  }) {
    _initialize();
  }

  void _initialize() {
    _logger.log('TableLockManager initialized');
    _initializeSocketListeners();
  }

  void _initializeSocketListeners() {
    // Listen to socket connection events
    socket.on('connect', (_) {
      if (_disposed) return;
      _logger.log('✅ Connected to server');
      _processPendingTableUpdates();
    });

    socket.on('disconnect', (_) {
      if (_disposed) return;
      _logger.log('Disconnected from server');
    });

    socket.on('connect_error', (error) {
      if (_disposed) return;
      _logger.log('Connection error', error: error.toString());
    });

    // Handle table update events
     socket.on('movventmp_update', (data) async {
    if (_disposed) return;
    
    try {
      final updateData = Map<String, dynamic>.from(data);
      final tableId = updateData['tavolo']?.toString();
      final msg = updateData['msg']?.toString();
      final isOccupied = msg == 'articolo aggiunto';

      if (tableId == null || msg == null) return;

      _logger.log('Received table update for table $tableId: $msg');

      // Update local database first
      await _updateLocalDatabaseWithOccupiedStatus(tableId, isOccupied);
      
      // Then notify UI
      onTableOccupiedUpdated(tableId, isOccupied);
      
    } catch (e) {
      _logger.log('Error processing movventmp_update', error: e.toString());
    }
  });

  }

  
Future<bool> tableUpdatefromserver() async {
  if (_disposed) return false; // Avoid setting up the listener if disposed

  // Set up the socket listener if not disposed
  socket.on('movventmp_update', (data) async {   
    try {
      final updateData = Map<String, dynamic>.from(data);
      final tableId = updateData['tavolo']?.toString();
      final msg = updateData['msg']?.toString();
      final isOccupied = msg == 'articolo aggiunto';

      _logger.log('Received table update for table $tableId: $msg');

      await _updateLocalDatabaseWithOccupiedStatus(tableId!, isOccupied);
      

      onTableOccupiedUpdated(tableId, isOccupied);

      return isOccupied;
    } catch (e) {
      // Log the error and return false
      _logger.log('Error processing movventmp_update', error: e.toString());
      return false;
    }
  });

  return true; 
}


  // Method to emit table updates
 Future<bool> emitTableUpdate({required String tavoloid, required String salaid}) async {
  if (_disposed) return false;
  
  final completer = Completer<bool>();
  final emitTime = DateTime.now();

  socket.emitWithAck('update_movventmp', {
    'msg': 'comanda inviata',
    'tavolo': tavoloid,
    'sala': salaid,
    'timestamp': emitTime.millisecondsSinceEpoch,
  }, ack: (response) {
    if (_disposed) return;
    
    if (response is Map && response['status'] == 'ok') {
      completer.complete(true);
    } else {
      completer.complete(false);
    }
  });

  // Timeout after 3 seconds
  Future.delayed(Duration(seconds: 3), () {
    if (!completer.isCompleted) {
      completer.complete(false);
    }
  });

  return completer.future;
}

  // Optimized table update handler


  void _processPendingTableUpdates() async {
    if (_pendingTableUpdates.isEmpty || _disposed) return;
    
    _logger.log('Processing ${_pendingTableUpdates.length} pending table updates');
    
    for (var update in _pendingTableUpdates) {
      final tableId = update['tableId'];
      final isOccupied = update['isOccupied'];
      
      onTableOccupiedUpdated(tableId, isOccupied);
      await _updateLocalDatabaseWithOccupiedStatus(tableId, isOccupied);
    }
    
    _pendingTableUpdates.clear();
  }

  Future<void> _updateLocalDatabaseWithOccupiedStatus(String tableId, bool isOccupied) async {
    if (_disposed) return;
    
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'tavolo',
        {'is_occupied': isOccupied ? 1 : 0},
        where: 'id = ?',
        whereArgs: [tableId],
      );
      _logger.log('Updated local DB for table $tableId: ${isOccupied ? "occupied" : "vacant"}');
    } catch (e) {
      _logger.log('Error updating local DB', error: e.toString());
    }
  }

  void dispose() {
    _disposed = true;
    _logger.log('TableLockManager disposed');
    socket.clearListeners();
  }
}