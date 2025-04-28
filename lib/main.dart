import 'package:flutter/material.dart';
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/inviacomand.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/views/Mainscreen.dart';
import 'package:ristocmd/views/login.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  await AppLogger().init();
  await Settings.loadBaseUrl(); // Load shared pref value

  _initializeCommandService();

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('baseUrl');

  runApp(RestaurantApp(initialRoute: savedUrl == null ? '/setup' : '/main'));
}

class RestaurantApp extends StatelessWidget {
  final String initialRoute;

  const RestaurantApp({required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RISTOCMD',
      theme: ThemeData(visualDensity: VisualDensity.adaptivePlatformDensity),
      initialRoute: initialRoute,
      routes: {
        '/main': (context) => MainScreen(),
        '/setup': (context) => SetupScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}


void _initializeCommandService() {
  final commandService = CommandService();
  final wifiMonitor = commandService.connectionMonitor;

  // Start monitoring connection changes
  wifiMonitor.startMonitoring();

  wifiMonitor.addConnectionListener((isConnected) {
    if (isConnected) {
      // Process offline queue when connection is restored
      commandService.processOfflineQueue();
    }
  });

  // Also check connection status immediately at startup
  wifiMonitor.isConnectedToWifi().then((isConnected) {
    if (isConnected) {
      commandService.processOfflineQueue();
    }
  });
}


