import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final importo = 500;  // amount in cents
  final url = 'http://proristosimo.proristo.it/v1/satispay/pagamento/$importo';

  print('Calling Satispay API POST $url');

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},  // optional, body is empty
      // no body needed because amount is in URL path
    );

    print('\n--- Response Summary ---');
    print('Status Code: ${response.statusCode}');
    print('Content Length: ${response.contentLength} bytes');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      print('\n--- Response Data ---');
      print('Status: ${data['status']}');
      if (data['status'] == 'PENDING') {
        print('Payment ID: $data');
        print('QR Code URL: ${data['qrcode']}');
        print('Amount: ${data['data']['amount']} cents');
      } else {
        print('Error Message: ${data['message']}');
      }
    } else {
      print('\n--- Error Details ---');
      print(response.body);
    }
  } catch (e) {
    print('\n--- Exception Occurred ---');
    print('Type: ${e.runtimeType}');
    print('Message: $e');
  }
}
