import 'dart:io';

void main() async {
  // Configuration
  final ipCassa = "192.168.16.80";          // Replace with your real printer IP
  final portaCassa = "9100";               // Replace with your real printer port
  final server = "ws://localhost:8855/";

  final portaCOM = "ethernet";
  final baudrate = "9600";
  final cassaProtocollo = "epsonxml";
  final matricolaECR = "TEST123456";        // Simulated printer ID
  final directoryAlenia = "";   // Simulated config path

  final ipCassaFormatted = ";$ipCassa;$portaCassa;";
  final message = "comsettings;$portaCOM;$baudrate;$cassaProtocollo;;$directoryAlenia;$ipCassa;;3;;;;;";

  try {
    print("Connecting to $server...");
    final socket = await WebSocket.connect(server);

    socket.listen(
      (data) {
        print("Received: $data");
      },
      onDone: () {
        print("Connection closed");
      },
      onError: (error) {
        print("Error: $error");
      },
    );

    print("Sending config: $message");
    socket.add(message);

    // Optional: send a print job (mimicking the JS logic)
    final testPrint = '|===|Hello from Dart!\n';
    print("Sending test print...");
    socket.add(testPrint);

    // Close after short delay (or keep open for further messages)
    await Future.delayed(Duration(seconds: 2));
    await socket.close();
    print("Socket closed.");
  } catch (e) {
    print("Failed to connect: $e");
  }
}
