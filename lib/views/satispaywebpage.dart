import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ristocmd/Settings/settings.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SatispayPaymentPage extends StatefulWidget {
  final String paymentId;
  final String paymentUrl;

  const SatispayPaymentPage({
    required this.paymentId,
    required this.paymentUrl,
    Key? key,
  }) : super(key: key);

  @override
  State<SatispayPaymentPage> createState() => _SatispayPaymentPageState();
}

class _SatispayPaymentPageState extends State<SatispayPaymentPage> {
  late final WebViewController _controller;
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  Timer? pollTimer;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => isLoading = false),
          onWebResourceError: (error) {
            setState(() {
              hasError = true;
              errorMessage = error.description;
            });
          },
        ),
      )
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36',
      )
      ..loadRequest(Uri.parse('${widget.paymentUrl}?mode=iframe'));

    startPolling();
    _setSystemUIOverlayStyle();
  }

  void _setSystemUIOverlayStyle() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color.fromARGB(255, 255, 255, 255),
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color.fromARGB(255, 255, 255, 255),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  void startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final response = await http.get(
          Uri.parse(
              '${Settings.buildApiUrl(Settings.getPagamento)}/${widget.paymentId}'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 8));
        print('dataresponse ${jsonDecode(response.body)}');
        if (response.statusCode != 200) throw Exception("Status error");

        final statusData = jsonDecode(response.body);
        final status = statusData['status']?.toString().toUpperCase();

        if (status == "ACCEPTED") {
          print('Pagamento accettato: $statusData');
          stopPolling();
          Navigator.pop(context, {'status': 'accepted', 'data': statusData});
        } else if (status == "CANCELED" || status == "FAILURE") {
          print('Pagamento fallito o annullato: $statusData');
          stopPolling();
          Navigator.pop(context, {'status': 'failed', 'data': statusData});
        }
      } catch (e) {
        debugPrint("Polling error: $e");
      }
    });
  }

  void stopPolling() {
    pollTimer?.cancel();
    pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.chevron_left, size: 32), // Bigger icon
                  onPressed: () => Navigator.of(context).pop(),
                  splashRadius: 26,
                ),
              ),
            ),
            title: const Text(
              "Satispay",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh, size: 24),
                    onPressed: () {
                      setState(() {
                        hasError = false;
                        isLoading = true;
                      });
                      _controller.reload();
                    },
                    splashRadius: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red[50],
                    ),
                    child: const Icon(Icons.error_outline,
                        color: Colors.red, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage ?? 'Errore durante il caricamento',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        hasError = false;
                        isLoading = true;
                      });
                      _controller.reload();
                    },
                    child: const Text("Riprova"),
                  )
                ],
              ),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (isLoading)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
