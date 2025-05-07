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

    if (!await _logFile.exists()) {
      await _logFile.create();
      await _logFile.writeAsString('Date,Time,Device,DeviceID,Action,Error\n'); // CSV Header
    }

    // Get device info
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _deviceName = androidInfo.model;
      _deviceId = androidInfo.id; // or androidInfo.androidId
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _deviceName = iosInfo.name;
      _deviceId = iosInfo.identifierForVendor;
    } else {
      _deviceName = 'Unknown Device';
      _deviceId = 'Unknown ID';
    }
  }

  Future<void> log(String action, {String? error}) async {
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);
    final time = DateFormat('HH:mm:ss').format(now);
    final device = _deviceName ?? 'Unknown';
    final id = _deviceId ?? 'Unknown';

    // Escape commas for CSV
    final safeAction = action.replaceAll(',', ';');
    final safeError = (error ?? '').replaceAll(',', ';');

    final entry = '$date,$time,$device,$id,$safeAction,$safeError\n';

    await _logFile.writeAsString(entry, mode: FileMode.append);
    print(entry);
  }

  Future<String> getLogs() async => await _logFile.readAsString();

    Future<void> clearLogs() async {
    await _logFile.writeAsString('Date,Time,Device,DeviceID,Action,Error\n');
  }

 Future<bool> sendLogsToServer() async {
    try {
      final logs = await getLogs();
      
      final response = await http.post(
        Uri.parse(Settings.buildApiUrl('${Settings.sendinglog}')),
        headers: {
          'Content-Type': 'application/json',
        },
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
        await log('Failed to send logs to server', error: 'Status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      await log('Failed to send logs to server', error: e.toString());
      return false;
    }
  }
}
