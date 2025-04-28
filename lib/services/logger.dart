// logger.dart
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

  Future<void> sendLogsToServer(String apiEndpoint) async {
    try {
      final logs = await getLogs();
      // Upload logic goes here
      await log('Logs sent to server');
    } catch (e) {
      await log('Failed to send logs to server', error: e.toString());
    }
  }
}
