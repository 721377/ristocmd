import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/inviacomand.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/views/Mainscreen.dart';
import 'package:ristocmd/views/login.dart';
import 'package:ristocmd/views/Homepage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global key to access HomePage state
final GlobalKey<HomePageState> homePageKey = GlobalKey<HomePageState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications
  await _initializeNotifications();

  // Initialize other services
  await DatabaseHelper.instance.database;
  await AppLogger().init();
  await Settings.loadAllSettings();

  _initializeCommandService();

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('baseUrl');

  runApp(RestaurantApp(initialRoute: savedUrl == null ? '/setup' : '/main'));
}

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // Handle notification tap if needed
    },
  );

  // Define a more noticeable vibration pattern
  final vibrationPattern = Int64List.fromList([
    0, 500, 300, 500, 300, 500  // wait, vibrate, wait, vibrate...
  ]);

  // Create a high-importance notification channel with strong vibration
  AndroidNotificationChannel channel = AndroidNotificationChannel(
    'order_channel',
    'Order Notifications',
    description: 'Notifications for order status',
    importance: Importance.high,
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('notification'),
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 500, 300, 500, 300, 500]),
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

class RestaurantApp extends StatelessWidget {
  final String initialRoute;

  const RestaurantApp({required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RISTOCMD',
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 255, 255, 255))),
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
  final commandService = CommandService(
    notificationsPlugin: flutterLocalNotificationsPlugin,
  );
  final wifiMonitor = commandService.connectionMonitor;

  wifiMonitor.startMonitoring();

  wifiMonitor.addConnectionListener((isConnected) {
    if (isConnected) {
      commandService.processOfflineQueue();
    }
  });

  wifiMonitor.isConnectedToWifi().then((isConnected) {
    if (isConnected) {
      commandService.processOfflineQueue();
    }
  });
}