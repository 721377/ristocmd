import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SetupScreen extends StatefulWidget {
  @override
  _SetupScreenState createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

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
          Navigator.pushReplacementNamed(context, '/main');
        } else {
          setState(() => _error = 'Il server ha risposto in modo errato.');
        }
      } else {
        setState(() => _error = 'Errore nella risposta dal server.');
      }
    } catch (_) {
      setState(() => _error = 'Impossibile connettersi all\'indirizzo fornito.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color buttonColor = Color(0xFFfdc735);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Welcome Message
              const Text(
                'Benvenuto!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 8),

              // Logo
              Container(
                width: 100,
                height: 100,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: buttonColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.restaurant_menu, size: 50, color: buttonColor),
              ),

              // Title
              Text(
                'Risto Comande',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Roboto',
                  color: buttonColor,
                ),
              ),

              const SizedBox(height: 32),

              // Input Field
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'Inserisci indirizzo server',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 24),

              // Confirm Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verifyAndSaveUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Conferma',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Roboto',
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 8),

              // App Version
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'v1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
