import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  // Base URL with 'http://' already included
  static String? _baseUrl;

  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('baseUrl');
  }

  static String get baseUrl => _baseUrl ?? '';

  // Endpoints without '/v1' part, as you mentioned that the /v1 should be appended dynamically
  static const String getImpostazioniPalm = 'impostazionipalmare/utente/0/pv/001';
  static const String getSalaEndpoint = 'sala/pv';
  static const String getTavoloEndpoint = 'tavolo/id_sala';
  static const String getMovtemEndpoint = 'movventmp/pv';
  static const String gettablebyidEndpoint = 'tavolo/id';
  static const String getGruppiEndpoint = 'gruppi/pv';
  static const String getArtByGruppo = 'articolo/dettagli/cod/0';
  static const String getvariantiByGruppo = 'gruppo_varianti/gruppo';
  static const String inviacomada = 'stampanti/comanda';


  // Function to build full API URL with /v1 endpoint
  static String buildApiUrl(String endpoint) {
    // Ensure baseUrl ends with a '/'
    final formattedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    
    // Ensure endpoint does not start with a '/'
    final formattedEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    
    return '$formattedBaseUrl/v1/$formattedEndpoint';
  }
}
