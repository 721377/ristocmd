import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../Settings/settings.dart';

class ApiService {
  static const String pv = '001';
  //for now cause there is just one impostazione in the database
  static const String user = '0';
  // Check for internet connection status
  static Future<bool> hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasConnection = connectivityResult != ConnectivityResult.none;
    print('[ApiService] Internet connection: $hasConnection');
    return hasConnection;
  }

  // Fetch Salas from the server
  static Future<List<Map<String, dynamic>>> fetchSalas() async {
    final url = Settings.buildApiUrl('${Settings.getSalaEndpoint}/$pv');
    print('[ApiService] Fetching Salas from: $url');

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print('[ApiService] Successfully fetched Salas.');
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      } else {
        print('[ApiService] Failed to fetch Salas. Status code: ${response.statusCode}');
        throw Exception('Failed to load salas');
      }
    } catch (e) {
      print('[ApiService] Error fetching Salas: $e');
      throw Exception('Failed to load salas: $e');
    }
  }

  // Fetch Tavolos based on the Sala ID
  static Future<List<Map<String, dynamic>>> fetchTavolos(int salaId) async {
    final url = Settings.buildApiUrl('${Settings.getTavoloEndpoint}/$salaId/pv/$pv');
    print('[ApiService] Fetching Tavolos for salaId=$salaId from: $url');

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print('[ApiService] Successfully fetched Tavolos.');
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      } else {
        print('[ApiService] Failed to fetch Tavolos. Status code: ${response.statusCode}');
        throw Exception('Failed to load tavolos');
      }
    } catch (e) {
      print('[ApiService] Error fetching Tavolos: $e');
      throw Exception('Failed to load tavolos: $e');
    }
  }

  // Fetch Movtable data based on Tavolo ID
  static Future<List<Map<String, dynamic>>> fetchMovtable(int tavoloId) async {
    final url = Settings.buildApiUrl('${Settings.getMovtemEndpoint}/$pv/tavolo/$tavoloId');
    print('[ApiService] Fetching ORDER for tavolo=$tavoloId at URL: $url');

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print('[ApiService] Successfully fetched ORDER.');
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      } else {
        print('[ApiService] Failed to fetch Tavolo ORDER. Status code: ${response.statusCode}');
        throw Exception('Failed to load tavolo order');
      }
    } catch (e) {
      print('[ApiService] Error fetching Tavolo ORDER: $e');
      throw Exception('Failed to load tavolo order: $e');
    }
  }

static Future<Map<String, dynamic>> tableByid(int tavoloId) async {
  final url = Settings.buildApiUrl('${Settings.gettablebyidEndpoint}/$tavoloId');
  print('[ApiService] Fetching table id : $tavoloId');

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      print('[ApiService] Successfully fetched table.');
      // Since the response is a single object, not a list, return it directly as a map
      return json.decode(response.body);
    } else {
      print('[ApiService] Failed to fetch Tavolo with id : $tavoloId.');
      throw Exception('Failed to load tavolo order');
    }
  } catch (e) {
    print('[ApiService] Error fetching Tavolo : $e');
    throw Exception('Failed to load tavolo order: $e');
  }
}

//categori api 
static Future<List<Map<String, dynamic>>> fetchGruppi() async {
    final url = Settings.buildApiUrl('${Settings.getGruppiEndpoint}/$pv/da_palmare/1');
    print('[ApiService] Fetching Gruppi from: $url');
    Map<String, String> headers = {
      'PV': pv,    
      'User': user,    
      'Content-Type': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        print('[ApiService] Successfully fetched Gruppi.');

        // Decode the response and extract only the required fields
        List<Map<String, dynamic>> gruppiData = List<Map<String, dynamic>>.from(json.decode(response.body));
        return gruppiData.map((gruppo) {
          return {
            'id': gruppo['id'],
            'des': gruppo['des'],
            'menu_pranzo': gruppo['menu_pranzo'] ?? 0, 
            'menu_cena': gruppo['menu_cena'] ?? 0,      
          };
        }).toList();
      } else {
        print('[ApiService] Failed to fetch Gruppi. Status code: ${response.statusCode}');
        throw Exception('Failed to load gruppi');
      }
    } catch (e) {
      print('[ApiService] Error fetching Gruppi: $e');
      throw Exception('Failed to load gruppi: $e');
    }
  }

static Future<List<Map<String, dynamic>>> fetchArtByGruppi(id_gruppi,cod_lis) async {
    final url = Settings.buildApiUrl('${Settings.getArtByGruppo}/cod_lis/$cod_lis/id_cat/$id_gruppi/des/0');
    print('[ApiService] Fetching articoli of the groupe : $id_gruppi from: $url');
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print('[ApiService] Successfully fetched articoli.');
        List<Map<String, dynamic>> articoliBygruppi = List<Map<String, dynamic>>.from(json.decode(response.body));
        return articoliBygruppi.map((articolo) {
          return {
            'id': articolo['id'],
            'cod': articolo['cod'],
            'des': articolo['des'],
            'qta': articolo['qta'],
            'prezzo': articolo['prezzo'],
            'id_cat':articolo['id_cat'],
            'cat_des':articolo['cat_des'], 
            'id_ag': articolo['id_ag'],      
            'svincolo_sequenza': articolo['svincolo_sequenza'],
          };
        }).toList();
      } else {
        print('[ApiService] Failed to fetcharticoliGruppo. Status code: ${response.statusCode}');
        throw Exception('Failed to load articoliGruppo');
      }
    } catch (e) {
      print('[ApiService] Error fetching articoliGruppo: $e');
      throw Exception('Failed to load articoliGruppo: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchVarianti(id_gruppi) async{
 final url = Settings.buildApiUrl('${Settings.getvariantiByGruppo}/$id_gruppi/des');
    print('[ApiService] Fetching varianti of the groupe : $id_gruppi from: $url');
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print('[ApiService] Successfully fetched varianti.');
        List<Map<String, dynamic>> variantiBygruppi = List<Map<String, dynamic>>.from(json.decode(response.body));
        return variantiBygruppi.map((varianti) {
          return {
            'id_cat': id_gruppi,
            'cod': varianti['cod'],
            'des': varianti['des'],
            'prezzo': varianti['prezzo'],
          };
        }).toList();
      } else {
        print('[ApiService] Failed to fetchvariantiGruppo. Status code: ${response.statusCode}');
        throw Exception('Failed to load variantiGruppo');
      }
    } catch (e) {
      print('[ApiService] Error fetching variantiGruppo: $e');
      throw Exception('Failed to load variantiGruppo: $e');
    }
  }

}
