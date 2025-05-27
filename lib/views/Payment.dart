import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/views/satispaywebpage.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentPage extends StatefulWidget {
  final double totalToPay;
  final int tableid;
  final int salaid;
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const PaymentPage({
    Key? key,
    required this.totalToPay,
    required this.tableid,
    required this.onUpdateTableStatus,
    required this.salaid,
  }) : super(key: key);

  @override
  _PaymentPageState createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String _selectedPaymentMethod = '';
  double _amountGiven = 0.0;
  final TextEditingController _amountController = TextEditingController();
  bool _isProcessingSatispay = false;
  late final WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView loading: $progress%');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
              code: ${error.errorCode}
              description: ${error.description}
              errorType: ${error.errorType}
              isForMainFrame: ${error.isForMainFrame}
            ''');
          },
        ),
      );
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
  @override
  void dispose() {
    _amountController.dispose();
    _webViewController.clearCache();
    super.dispose();
  }

  Future<void> _startSatispayPayment() async {
    final int importoCentesimi = (widget.totalToPay * 100).round();

    setState(() {
      _isProcessingSatispay = true;
    });

    try {
      final url =
          '${Settings.buildApiUrl(Settings.satispay)}/$importoCentesimi';
      final creaResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (creaResponse.statusCode != 200) {
        throw Exception(
            'Payment creation error: ${creaResponse.statusCode} - ${creaResponse.body}');
      }

      final creaData = jsonDecode(creaResponse.body);
      final payment = creaData is Map ? creaData : creaData['data'];

      if (payment == null) throw Exception('No payment data received');

      final paymentId = payment['id'] ?? payment['Payment ID'];
      final qrCodeUrl = payment['redirect_url'] ?? payment['redirect_url'];

      if (paymentId == null) throw Exception('Missing payment ID in response');
      if (qrCodeUrl == null) throw Exception('Missing QR code URL in response');
      if (!Uri.tryParse(qrCodeUrl)!.hasAbsolutePath) {
        throw Exception('Invalid QR code URL format: $qrCodeUrl');
      }

      _openSatispayPage(paymentId, qrCodeUrl);
    } catch (e) {
      _showError('Satispay payment failed: ${e.toString()}');
      debugPrint('Satispay payment error: $e');
    } finally {
      setState(() {
        _isProcessingSatispay = false;
      });
    }
  }

void _openSatispayPage(String paymentId, String qrCodeUrl) async {
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => SatispayPaymentPage(
        paymentId: paymentId,
        paymentUrl: qrCodeUrl,
      ),
    ),
  );

  if (result != null) {
  if (result['status'] == 'accepted') {
    print('Successo: ${result['data']}');
    _chiusura(5); // or pass result['data'] to it
  } else {
    print('Errore/Fallimento: ${result['data']}');
    _showError("Pagamento fallito o annullato");
  }
}

}



  void _showError(String message) {
    debugPrint('Payment error: $message');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _chiusura(int tipo) async {
    int codPag = tipo;
    const pv = '001';
    const idUser = '0';
    double importo = widget.totalToPay;
    final modPag = [
      {
        'modalita': codPag,
        'importo': importo.toStringAsFixed(2),
      }
    ];

    final obj = {
      'id_tavolo': widget.tableid.toString(),
      'norc': 0,
      'tipo': 'scontrino',
      'pv': '001',
      'totale_conto': widget.totalToPay,
      'cod_pag': codPag,
      'mod_pag': jsonEncode(modPag),
      'buoni': jsonEncode([]),
      'codice_fiscale_o_lotteria': '',
    };

    final payload = obj;

    Map<String, String> headers = {
      'User': idUser,
      'Content-Type': 'application/json',
    };

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.2),
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(const Color(0xFFFEBE2B)),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Attendere...",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final response = await http
          .post(
            Uri.parse(Settings.buildApiUrl(Settings.salvaTrans)),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        throw Exception('Server returned error: ${response.statusCode}');
      }

      Navigator.of(context).pop(); // Remove loading indicator

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Operazione completata"),
          content: const Text.rich(
            TextSpan(
              text: "Transazione eseguita correttamente.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _redirectToMainScreen();
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );

      _performCleanupOperations();
    } catch (err) {
      Navigator.of(context).pop(); // Remove loading indicator if present
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Attenzione"),
          content: Text(err.toString()),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/main');
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _performCleanupOperations() async {
    try {
      final DatabaseHelper dbHelper = DatabaseHelper.instance;
      final tableLockManager = TableLockService().manager;

      await Future.wait([
        widget.onUpdateTableStatus?.call(widget.tableid.toString(), 'free'),
        tableLockManager.releaseTableLock(
          tableId: widget.tableid.toString(),
          salaId: widget.salaid.toString(),
        ),
        tableLockManager.updateLocalDatabaseWithOccupiedStatus(
            widget.tableid.toString(), false),
        dbHelper.updateTablePendingStatus(widget.tableid, 0),
      ] as Iterable<Future>);
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }

  void _redirectToMainScreen() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 80,
        leading: Center(
          child: Container(
            margin: const EdgeInsets.only(left: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 22,
                color: Colors.black,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Text(
          'Pagamento',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 18),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Totale da pagare',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '€${widget.totalToPay.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Metodo di pagamento',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                _buildPaymentMethodTile(
                  'contanti',
                  'Contanti',
                  'images/ristocmd/moneyicon.png',
                ),
                const SizedBox(height: 12),
                _buildPaymentMethodTile(
                  'elettronico',
                  'Pagamento elettronico',
                  'images/ristocmd/creditcard.png',
                ),
                const SizedBox(height: 12),
                _buildPaymentMethodTile(
                  'satispay',
                  'Satispay',
                  'images/ristocmd/satispay.png',
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // Conto scalare action
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFFFEBE2B)),
                  ),
                  child: const Text(
                    'Conto scalare',
                    style: TextStyle(
                      color: Color(0xFFFEBE2B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _selectedPaymentMethod.isEmpty
                      ? null
                      : () {
                          if (_selectedPaymentMethod == 'satispay') {
                            _startSatispayPayment();
                          } else {
                            int tipo;
                            switch (_selectedPaymentMethod) {
                              case 'contanti':
                                tipo = 0;
                                break;
                              case 'elettronico':
                                tipo = 1;
                                break;
                              default:
                                tipo = 0;
                            }
                            _chiusura(tipo);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEBE2B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isProcessingSatispay
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          'Scontrino',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodTile(String value, String title, String icon) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = value;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedPaymentMethod == value
                ? const Color(0xFFFEBE2B)
                : Colors.grey.shade200,
            width: _selectedPaymentMethod == value ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                icon,
                fit: BoxFit.contain,
                width: 26.5,
                height: 26.5,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (_selectedPaymentMethod == value)
              const Icon(Icons.check_circle, color: Color(0xFFFEBE2B)),
          ],
        ),
      ),
    );
  }
}
