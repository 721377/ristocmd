// logger.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ristocmd/Settings/settings.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  late File _logFile;
  String? _deviceName;
  String? _deviceId;

  factory AppLogger() => _instance;

  AppLogger._internal();

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/app_logs.csv');

    // Create CSV with BOM for Excel compatibility
    if (!await _logFile.exists()) {
      await _logFile.create();
      final header = 'Timestamp,Level,Device,DeviceID,Action,Error\n';
      await _logFile.writeAsBytes([0xEF, 0xBB, 0xBF] + utf8.encode(header)); // UTF-8 BOM + Header
    }

    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _deviceName = androidInfo.model;
      _deviceId = androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _deviceName = iosInfo.name;
      _deviceId = iosInfo.identifierForVendor;
    } else {
      _deviceName = 'Unknown Device';
      _deviceId = 'Unknown ID';
    }
  }

  String _escapeForCSV(String input) {
    final sanitized = input.replaceAll('"', '""'); // Escape quotes
    return '"$sanitized"'; // Wrap in quotes for Excel
  }

  Future<void> log(String action, {String level = 'INFO', String? error}) async {
    final now = DateTime.now();
    final timestamp = DateFormat("yyyy-MM-dd HH:mm:ss").format(now);
    final device = _deviceName ?? 'Unknown';
    final id = _deviceId ?? 'Unknown';

    final row = [
      timestamp,
      level,
      device,
      id,
      _escapeForCSV(action),
      error != null ? _escapeForCSV(error) : ''
    ].join(',') + '\n';

    await _logFile.writeAsString(row, mode: FileMode.append, flush: true);
    print('[LOG][$level] $action ${error != null ? "- $error" : ""}');
  }

  Future<String> getLogs() async => await _logFile.readAsString();

  Future<void> clearLogs() async {
    final header = 'Timestamp,Level,Device,DeviceID,Action,Error\n';
    await _logFile.writeAsBytes([0xEF, 0xBB, 0xBF] + utf8.encode(header)); // Re-add BOM + Header
  }

  Future<bool> sendLogsToServer() async {
    try {
      final logs = await getLogs();
      final response = await http.post(
        Uri.parse(Settings.buildApiUrl('${Settings.sendinglog}')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_name': _deviceName,
          'device_id': _deviceId,
          'logs': logs,
        }),
      );

      if (response.statusCode == 200) {
        await log('Logs sent successfully to server');
        await clearLogs();
        return true;
      } else {
        await log('Failed to send logs to server', level: 'ERROR', error: 'Status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      await log('Exception while sending logs to server', level: 'ERROR', error: e.toString());
      return false;
    }
  }
}
