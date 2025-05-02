import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/animation.dart';
import 'package:google_fonts/google_fonts.dart';


class SetupScreen extends StatefulWidget {
  @override
  _SetupScreenState createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _notificationPermissionAsked = false;
  bool _notificationPermissionGranted = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  final connectionMonitor = WifiConnectionMonitor();
  @override
  void initState() {
    super.initState();
    
  SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Color(0xFFFEBE2B),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor:
            Color.fromARGB(255, 255, 255, 255), // Set navigation bar color
        systemNavigationBarIconBrightness: Brightness.dark, // Set icon color
      ),
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0, 0.5, curve: Curves.easeInOut)),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(
      CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.5, 1, curve: Curves.elasticOut)),
    );

    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
    _requestNotificationPermission();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestNotificationPermission() async {
    if (_notificationPermissionAsked) return;

    bool granted = true;

    if (Theme.of(context).platform == TargetPlatform.android) {
      final status = await Permission.notification.request();
      granted = status.isGranted;
    }

    setState(() {
      _notificationPermissionAsked = true;
      _notificationPermissionGranted = granted;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              granted ? Icons.check_circle : Icons.info_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              granted
                  ? 'Notifiche abilitate con successo'
                  : 'Permesso per le notifiche negato',
            ),
          ],
        ),
        backgroundColor: granted ? Colors.green : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        elevation: 2,
      ),
    );
  }
  Future<void> _loadAndSaveImpostazioni() async {
    final isOnline = await connectionMonitor.isConnectedToWifi();
    try {
      final impostazioni = await DataRepository().getImpostazioniPalmari(context, isOnline);
      final prefs = await SharedPreferences.getInstance();

      for (var setting in impostazioni) {
        setting.forEach((key, value) async {
          if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          }
        });
      }

      print("Impostazioni saved to SharedPreferences: $impostazioni");
    } catch (e) {
      print("Failed to load/save impostazioni: $e");
    }
  }

  Future<void> _verifyAndSaveUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    String input = _controller.text.trim();
    if (!input.startsWith('http')) {
      input = 'http://$input';
    }
    input = input.endsWith('/') ? input.substring(0, input.length - 1) : input;

    final pingUrl = '$input/v1';

    try {
      final response = await http.get(Uri.parse(pingUrl));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'ok') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('baseUrl', input);
          await _loadAndSaveImpostazioni() ;
          if (!_notificationPermissionGranted) {
            await _requestNotificationPermission();
          }

          Navigator.pushReplacementNamed(context, '/main');
        } else {
          setState(() => _error = 'Il server ha risposto con un errore');
        }
      } else {
        setState(() => _error = 'Errore nella risposta del server');
      }
    } catch (_) {
      setState(() => _error = 'Impossibile connettersi all\'indirizzo fornito');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                // Top rounded half-circle header
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEBE2B),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(95),
                      bottomRight: Radius.circular(95),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'Benvenuto',
                           style: GoogleFonts.quicksand(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 32, 
                          ),
                        ),
                        Text(
                          'RistoComande',
                          style: GoogleFonts.quicksand(
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            fontSize: 25, 
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 45),
                        // App icon
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.restaurant_menu,
                            size: 60,
                            color: Color(0xFFFEBE2B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Configurazione iniziale',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Inserisci l\'indirizzo del tuo server per iniziare',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Input field
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _controller,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: 'es. 192.168.1.100',
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 18,
                                horizontal: 20,
                              ),
                              prefixIcon: Icon(
                                Icons.dns_rounded,
                                color: Colors.grey.shade500,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFFEBE2B),
                                  width: 1.5,
                                ),
                              ),
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _verifyAndSaveUrl,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEBE2B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 3,
                              shadowColor: const Color(0xFFFEBE2B).withOpacity(0.4),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'ENTRA',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Version text
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'v1.0.5',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}