// lib/services/table_lock_service.dart
import 'package:ristocmd/serverComun.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:flutter/material.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/wifichecker.dart';

class TableLockService {
  static final TableLockService _instance = TableLockService._internal();
  late TableLockManager _tableLockManager;
  bool _initialized = false;

  factory TableLockService() => _instance;

  TableLockService._internal();

  void initialize({
    required Function(String, bool) onTableOccupiedUpdated,
    required String clientName,
    required DataRepository dataRepository,
    required BuildContext context,
    required WifiConnectionMonitor connectionMonitor,
  }) {
    if (_initialized) return;
    
    final socket = SocketManager().socket;
    
    _tableLockManager = TableLockManager(
      socket: socket,
      onTableOccupiedUpdated: onTableOccupiedUpdated,
      clientName: clientName,
      dataRepository: dataRepository,
      context: context,
      connectionMonitor: connectionMonitor,
    );
    
    _initialized = true;
  }

  TableLockManager get manager {
    if (!_initialized) {
      throw Exception('TableLockService not initialized. Call initialize() first.');
    }
    return _tableLockManager;
  }

  void dispose() {
    if (_initialized) {
      _tableLockManager.dispose();
      _initialized = false;
    }
  }
}