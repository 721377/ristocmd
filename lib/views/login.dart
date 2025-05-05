import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ristocmd/Settings/settings.dart';
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
  late Animation<Offset> _slideAnimation;

  final connectionMonitor = WifiConnectionMonitor();

  @override
  void initState() {
    super.initState();
    
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Color(0xFFFEBE2B),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0, 0.5, curve: Curves.easeInOut),
        ),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 1, curve: Curves.elasticOut),
      ),
    );

_slideAnimation = Tween<Offset>(
  begin: Offset(0, 1),
  end: Offset(0, 0),
).animate(
  CurvedAnimation(
    parent: _animationController,
    curve: const Interval(0.5, 1, curve: Curves.easeOut),
  ),
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
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: granted ? const Color(0xFFE6F4EA): const Color(0xFFFFF3E0),
            shape: BoxShape.circle,
          ),
          child: Icon(
            granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: granted ? const Color(0xFF28A745): Color(0xFFFFA000),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          granted
              ? 'Notifiche abilitate con successo'
              : 'Permesso per le notifiche negato',
          style: GoogleFonts.quicksand(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color:  granted ? const Color(0xFF28A745) : Color(0xFFFFA000),
          ),
        ),
      ],
    ),
    backgroundColor: granted ? const Color(0xFFE6F4EA) : const Color(0xFFFFEFE7),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: granted ? const Color(0xFF28A745) : Color(0xFFFFA000),
        width: 1,
      ),
    ),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    elevation: 2,
    duration: const Duration(seconds: 3),
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
      await Settings.loadAllSettings();
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
      // i have added a timeout here to prevent the app from hanging indefinitely
      final response = await http.get(Uri.parse(pingUrl))
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw TimeoutException('Il server non ha risposto');
    });

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'ok') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('baseUrl', input);
          await _loadAndSaveImpostazioni();
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
  final size = MediaQuery.of(context).size;

  return Scaffold(
    resizeToAvoidBottomInset: true, // Allow body to resize when keyboard appears
    backgroundColor: Color(0xFFFEBE2B),
    body: SafeArea(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Stack(
            children: [
              // Background elements
              Positioned(
                top: -size.width * 0.2,
                right: -size.width * 0.2,
                child: Container(
                  width: size.width * 0.6,
                  height: size.width * 0.6,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -size.width * 0.3,
                left: -size.width * 0.3,
                child: Container(
                  width: size.width * 0.8,
                  height: size.width * 0.8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // Main scrollable content
              SingleChildScrollView(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.only(top: size.height * 0.05),
                      child: Column(
                        children: [
                          Icon(
                            Icons.restaurant_menu,
                            size: 50,
                            color: Colors.white,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'RistoComande',
                            style: GoogleFonts.quicksand(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 28,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Gestione comande ristorante',
                            style: GoogleFonts.quicksand(
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24),

                    // Main content container
                    SlideTransition(
                      position: _slideAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Transform.translate(
                          offset: Offset.zero,
                          child: Container(
                      // Use minimum height instead of fixed height
                      constraints: BoxConstraints(minHeight: size.height * 0.75),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Color(0xFFfcfcfc),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 30,
                            spreadRadius: 5,
                            offset: Offset(0, -10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Configurazione iniziale',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.quicksand(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                fontSize: 22,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Inserisci l\'indirizzo del tuo server per iniziare',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.quicksand(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 38),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    blurRadius: 15,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _controller,
                                style: GoogleFonts.quicksand(
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'es. 192.168.1.100',
                                  contentPadding: EdgeInsets.symmetric(
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
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Color(0xFFFEBE2B),
                                      width: 1.5,
                                    ),
                                  ),
                                  hintStyle: GoogleFonts.quicksand(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              SizedBox(height: 16),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.redAccent),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: GoogleFonts.quicksand(color: Colors.redAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _verifyAndSaveUrl,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFFEBE2B),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  elevation: 3,
                                  shadowColor: Color(0xFFFEBE2B).withOpacity(0.4),
                                ),
                                child: _loading
                                    ? SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        'CONNETTI',
                                        style: GoogleFonts.quicksand(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(height: 24),
                            Text(
                              'Assicurati di essere connesso alla stessa rete del server',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.quicksand(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Versione 1.0.5',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.quicksand(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                        ),
                      ),
                    ),
                  ],
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