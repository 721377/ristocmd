import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  // Singleton instance
  static final Settings _instance = Settings._internal();
  factory Settings() => _instance;
  Settings._internal();

  // Base URL
  static String? _baseUrl;
  static String get baseUrl => _baseUrl ?? '';

  // WebSocket Port
  static int? _wsPort;
  static int get wsPort => _wsPort ?? 8080;

  // Other settings with default values
  static int _chiusuraPalmare = 0;
  static int _avanzamentoSequenza = 1;
  static int _avanzamentoPalmare = 1;
  static int _pv = 1;
  static int _abilitaSatispay = 1;
  static int _listinoPalmari = 1;
  static int _licenzePalmari = 2;
  static String _ristocomandeVer = "0.6.9.6";
  static int _copertoPalm = 1;

  // Getters for all settings
  static int get chiusuraPalmare => _chiusuraPalmare;
  static int get avanzamentoSequenza => _avanzamentoSequenza;
  static int get avanzamentoPalmare => _avanzamentoPalmare;
  static int get pv => _pv;
  static int get abilitaSatispay => _abilitaSatispay;
  static int get listinoPalmari => _listinoPalmari;
  static int get licenzePalmari => _licenzePalmari;
  static String get ristocomandeVer => _ristocomandeVer;
  static int get copertoPalm => _copertoPalm;

  // Endpoints
  static const String getImpostazioniPalm = 'impostazionipalmare/utente/0/pv/001';
  static const String getSalaEndpoint = 'sala/pv';
  static const String getTavoloEndpoint = 'tavolo/id_sala';
  static const String getMovtemEndpoint = 'movventmp/pv';
  static const String gettablebyidEndpoint = 'tavolo/id';
  static const String getGruppiEndpoint = 'gruppi/pv';
  static const String getArtByGruppo = 'articolo/dettagli/cod/0';
  static const String getvariantiByGruppo = 'gruppo_varianti/gruppo';
  static const String inviacomada = 'stampanti/comanda';

  // Load all settings from SharedPreferences
  static Future<void> loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load base URL
    _baseUrl = prefs.getString('baseUrl');
    
    // Load all other settings
    _wsPort = prefs.getInt('wsport') ?? 8080;
    _chiusuraPalmare = prefs.getInt('chiusura_palmare') ?? 0;
    _avanzamentoSequenza = prefs.getInt('avanzamento_sequenza') ?? 1;
    _avanzamentoPalmare = prefs.getInt('avanzamento_palmare') ?? 1;
    _pv = prefs.getInt('pv') ?? 1;
    _abilitaSatispay = prefs.getInt('abilita_satispay') ?? 1;
    _listinoPalmari = prefs.getInt('listino_palmari') ?? 1;
    _licenzePalmari = prefs.getInt('licenze_palmari') ?? 2;
    _ristocomandeVer = prefs.getString('ristocomande_ver') ?? "0.6.9.6";
    _copertoPalm = prefs.getInt('copertoPalm') ?? 1;
  }

  // Function to build full API URL with /v1 endpoint
  static String buildApiUrl(String endpoint) {
    // Ensure baseUrl ends with a '/'
    final formattedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    
    // Ensure endpoint does not start with a '/'
    final formattedEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    
    return '$formattedBaseUrl/v1/$formattedEndpoint';
  }

  // Function to update a setting value
  static Future<void> updateSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }

    // Update the in-memory value
    switch (key) {
      case 'baseUrl':
        _baseUrl = value as String?;
        break;
      case 'wsport':
        _wsPort = value as int;
        break;
      case 'chiusura_palmare':
        _chiusuraPalmare = value as int;
        break;
      case 'avanzamento_sequenza':
        _avanzamentoSequenza = value as int;
        break;
      case 'avanzamento_palmare':
        _avanzamentoPalmare = value as int;
        break;
      case 'pv':
        _pv = value as int;
        break;
      case 'abilita_satispay':
        _abilitaSatispay = value as int;
        break;
      case 'listino_palmari':
        _listinoPalmari = value as int;
        break;
      case 'licenze_palmari':
        _licenzePalmari = value as int;
        break;
      case 'ristocomande_ver':
        _ristocomandeVer = value as String;
        break;
      case 'copertoPalm':
        _copertoPalm = value as int;
        break;
    }
  }
}