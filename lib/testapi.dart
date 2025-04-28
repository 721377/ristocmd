import 'package:socket_io_client/socket_io_client.dart' as IO;

void main(List<String> arguments) {
  if (arguments.length != 2) {
    print('Usage: dart main.dart <host> <port>');
    return;
  }

  final host = arguments[0];
  final port = arguments[1];

  final socket = IO.io('http://$host:$port', <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': false,
  });

  socket.connect();

  socket.onConnect((_) {
    print('✅ Connected to $host:$port');

    socket.emit('update_movventmp', {
      'msg': 'comanda inviata',
      'tavolo': 309,
      'sala': 1,
    });
  });

  socket.onConnectError((error) {
    print('❌ Connection error: $error');
  });

  socket.onDisconnect((_) {
    print('🔌 Disconnected from server');
  });
}
// import 'dart:convert';
// import 'package:http/http.dart' as http;

// void main(List<String> arguments) async {
//   // Ensure the program is run with the correct number of arguments
//   if (arguments.length != 2) {
//     print('Usage: dart fetch_data.dart <PV> <User>');
//     return;
//   }

//   // Read PV and User from the command-line arguments
//   String pv = arguments[0];
//   String user = arguments[1];

//   // URL of the API with dynamic parameters for PV and User
//   final String url = 'http://proristosimo.proristo.it/v1/gruppi/pv/$pv/da_palmare/1';

//   // Set headers with PV and User
//   Map<String, String> headers = {
//     'PV': pv,           // The point of sale (pv)
//     'User': user,       // The user id
//     'Content-Type': 'application/json',
//   };

//   try {
//     // Make the GET request
//     final response = await http.get(Uri.parse(url), headers: headers);

//     // Check the response status
//     if (response.statusCode == 200) {
//       // If the server returns a successful response
//       // Decode the JSON response
//       var data = json.decode(response.body);

//       // Print the response data to the terminal
//       print('Response data:\n$data');
//     } else {
//       // If the server did not return a successful response
//       print('Request failed with status: ${response.statusCode}');
//     }
//   } catch (e) {
//     // If there was an error with the request
//     print('Error: $e');
//   }

