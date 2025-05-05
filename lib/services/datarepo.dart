import 'dart:async' show StreamController;
import 'package:path/path.dart';
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/services/api.dart';
import 'package:ristocmd/services/database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ristocmd/services/logger.dart';

class DataRepository {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  final AppLogger _logger = AppLogger();
  final StreamController<List<Map<String, dynamic>>> _tablesController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  
  Stream<List<Map<String, dynamic>>> get tablesStream => _tablesController.stream;

  //categorie managment 
  final StreamController<List<Map<String, dynamic>>> _gruppiController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  
  Stream<List<Map<String, dynamic>>> get gruppiStream => _gruppiController.stream;
  String listinopalm = Settings.listinoPalmari.toString().padLeft(2, '0');
  DataRepository();

  void dispose() {
    _tablesController.close();
  }

  Future<void> showConnectionSnackbar(BuildContext context, bool isConnected) async {
    if (!context.mounted) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      bool? lastStatus = prefs.getBool('lastConnectionStatus');

      if (lastStatus == null || lastStatus != isConnected) {
        await prefs.setBool('lastConnectionStatus', isConnected);

      }
    } catch (e) {
      print("Error showing connection snackbar: $e");
      _logger.log('Error showing connection snackbar', error: '$e');
    }
  }

  Future<List<Map<String, dynamic>>> getSalas(BuildContext context, bool hasInternet) async {
    print("Fetching salas...");
    try {
      List<Map<String, dynamic>> salas;
      
      if (hasInternet) {
        print("Fetching salas from API");
        salas = await ApiService.fetchSalas();
        
        final formattedSalas = salas.map((sala) => {
          'id': sala['id'],
          'des': sala['des'],
          'listino': sala['listino'],
        }).toList();
        
        await dbHelper.saveAllSalas(formattedSalas);
        
        await Future.wait(
          salas.map((sala) => _syncTavolosForSala(context, sala['id']))
        );
        
        return formattedSalas;
      } else {
        print("Fetching salas from local database");
        _logger.log('Fetching salas from local database');
        salas = await dbHelper.queryAllSalas();
        if (context.mounted) {
          await showConnectionSnackbar(context, false);
        }
      }

      return salas;
    } catch (e) {
      print("Error in getSalas: $e");
      _logger.log('Error in getSalas', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      return await dbHelper.queryAllSalas();
    }
  }

  Future<void> _syncTavolosForSala(BuildContext context, int salaId) async {
    try {
      final tavolos = await ApiService.fetchTavolos(salaId);
      await _saveFilteredTavolos(salaId, tavolos);
      if (context.mounted) {
        await showConnectionSnackbar(context, true);
      }
    } catch (e) {
      print("Error syncing tavolos for sala $salaId: $e");
      _logger.log('Error syncing tavolos for sala $salaId', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getTavolos(BuildContext context, int salaId, bool hasInternet) async {
    print("Fetching tavolos for sala $salaId...");
    _logger.log('Fetching tavolos for sala $salaId...');
    try {
      List<Map<String, dynamic>> tavolos;

      if (hasInternet) {
        print("Fetching tavolos from API");
        tavolos = await ApiService.fetchTavolos(salaId);
        final filteredTavolos = _filterTavolos(tavolos);
        await _saveFilteredTavolos(salaId, filteredTavolos);
        if (context.mounted) {
          await showConnectionSnackbar(context, true);
        }
        return filteredTavolos;
      }

      print("Fetching tavolos from local database");
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      return await dbHelper.queryTavolosBySala(salaId);
    } catch (e) {
      print("Error in getTavolos: $e");
      _logger.log('Error in getTavolos', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      return await dbHelper.queryTavolosBySala(salaId);
    }
  }

  List<Map<String, dynamic>> _filterTavolos(List<Map<String, dynamic>> tavolos) {
    return tavolos.map((tavolo) {
      return {
        'id': tavolo['id'],
        'id_sala': tavolo['id_sala'],
        'des': tavolo['des'],
        'pos_left': tavolo['pos_left'],
        'pos_top': tavolo['pos_top'],
        'mod_banco': tavolo['mod_banco'] ?? 0,
        'coperti': tavolo['coperti'] ?? 0,
        'conti_aperti': tavolo['conti_aperti'] ?? 0,
        'num_ordine': tavolo['num_ordine'],
        'stato_avanzamento': tavolo['stato_avanzamento'],
        'des_sala': tavolo['des_sala'],
      };
    }).toList();
  }

  Future<void> _saveFilteredTavolos(int salaId, List<Map<String, dynamic>> tavolos) async {
    await dbHelper.saveAllTavolos(salaId, _filterTavolos(tavolos));
  }

  Future<List<Map<String, dynamic>>> getOrdersForTable(BuildContext context, int tavoloId, bool hasInternet) async {
    print("Fetching orders for table $tavoloId...");
    _logger.log('Fetching orders for table $tavoloId...');
    try {
      List<Map<String, dynamic>> orders;

      if (hasInternet) {
        print("Fetching orders from API");
        _logger.log('Fetching orders from API');
        orders = await ApiService.fetchMovtable(tavoloId);
        final filteredOrders = _filterOrders(orders);
        
        try {
          await dbHelper.upsertAllOrdersForTable(tavoloId, filteredOrders);
        } catch (e) {
          print("Error saving orders to local DB: $e");
          _logger.log('Error saving orders to local DB:', error: '$e');
          return filteredOrders;
        }
        
        if (context.mounted) {
          await showConnectionSnackbar(context, true);
        }
        return filteredOrders;
      }

      print("Fetching orders from local database");
      _logger.log('Fetching orders from local database');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      
      try {
        orders = await dbHelper.getOrdersForTable(tavoloId);
        return _filterOrders(orders);
      } catch (e) {
        print("Error fetching orders from local DB: $e");
        _logger.log('Error fetching orders from local DB', error: '$e');
        orders = await dbHelper.getOrdersForTable(tavoloId);
        return _filterOrders(orders);
      }
    } catch (e) {
      print("Error in getOrdersForTable: $e");
      _logger.log('"Error in getOrdersForTable:', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      final orders = await dbHelper.getOrdersForTable(tavoloId);
      return _filterOrders(orders);
    }
  }

  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    return orders.map((order) {
      final isCoperto = order['mov_cod'] == 'COPERTO';
      
      return {
        'id': order['id'],
        'mov_cod': order['mov_cod'],
        'mov_descr': order['mov_descr_alt'] ?? order['mov_descr'],
        'mov_prz': order['mov_prz'],
        'mov_qta': order['mov_qta'],
        'mov_aliiva': order['mov_aliiva'],
        'tavolo': order['tavolo'],
        'sala': order['sala'],
        'is_coperto': isCoperto ? 1 : 0,
        'timer_start': order['timer_start'],
        'timer_stop': order['timer_stop'],
        'variantiDes': order['variantiDes'],
        'variantiPrz': order['variantiPrz'],
        'seq': order['seq'],
        'pagato': order['pagato'],
        'created_at': order['created_at'],
        'updated_at': order['updated_at'],
      };
    }).toList();
  }

  //categories managment 
  Future<List<Map<String, dynamic>>> getGruppi(BuildContext context, bool hasInternet) async {
    print("Fetching gruppi...");
    _logger.log('Fetching gruppi...');
    try {
      List<Map<String, dynamic>> gruppi;

      if (hasInternet) {
        print("Fetching gruppi from API");
        _logger.log('Fetching gruppi from API');
        gruppi = await ApiService.fetchGruppi();

        await dbHelper.saveAllGruppi(gruppi);

        // Fetch and save articoli per gruppo
        await Future.wait(
          gruppi.expand((gruppo) => [
            _syncArticoliForGruppo(context, gruppo['id']),
            _syncVariantForGruppo(context, gruppo['id']),
          ]),
        );

        return gruppi;
      } else {
        print("Fetching gruppi from local database");
        _logger.log('Fetching gruppi from local database');
        if (context.mounted) {
          await showConnectionSnackbar(context, false);
        }
        gruppi = await dbHelper.queryAllGruppi();
        return gruppi;
      }
    } catch (e) {
      print("Error in getGruppi: $e");
      _logger.log('"Error in getGruppi', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      return await dbHelper.queryAllGruppi();
    }
  }

  //articoles managment 
  Future<void> _syncArticoliForGruppo(BuildContext context, int gruppoId) async {
    try {
      final articoli = await ApiService.fetchArtByGruppi(gruppoId, listinopalm);
      await dbHelper.saveAllArticoli(articoli);
      if (context.mounted) {
        await showConnectionSnackbar(context, true);
      }
    } catch (e) {
      print("Error syncing articoli for gruppo $gruppoId: $e");
      _logger.log('"Error syncing articoli for gruppo $gruppoId', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getArticoliByGruppo(
      BuildContext context, int gruppoId, bool hasInternet) async {
    print("Fetching articoli for gruppo $gruppoId...");
    _logger.log('Fetching articoli for gruppo $gruppoId');

    try {
      List<Map<String, dynamic>> articoli;

      if (hasInternet) {
        articoli = await ApiService.fetchArtByGruppi(gruppoId, listinopalm);
        print('listino palmare $listinopalm');
        await dbHelper.saveAllArticoli(articoli);
        if (context.mounted) {
          await showConnectionSnackbar(context, true);
        }
        return articoli;
      } else {
        print("No internet. Fetching articoli from local database."); 
        _logger.log('No internet. Fetching articoli from local database.');
        if (context.mounted) {
          await showConnectionSnackbar(context, false);
        }
        return await dbHelper.queryArticoliByCategory(gruppoId);
      }
    } catch (e) {
      print("Error fetching articoli for gruppo $gruppoId: $e");
      _logger.log('Error fetching articoli for gruppo $gruppoId', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      return await dbHelper.queryArticoliByCategory(gruppoId);
    }
  }

  Future<void> _syncVariantForGruppo(BuildContext context, int gruppoId) async {
    try {
      final varianti = await ApiService.fetchVarianti(gruppoId);
      await dbHelper.saveAllvarianti(varianti);
      if (context.mounted) {
        await showConnectionSnackbar(context, true);
      }
    } catch (e) {
      print("Error syncing varianti for gruppo $gruppoId: $e");
      _logger.log('Error syncing varianti for gruppo $gruppoId', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getvariantiByGruppo(
      BuildContext context, int gruppoId, bool hasInternet) async {
    print("Fetching varianti for gruppo $gruppoId...");
    _logger.log('Fetching varianti for gruppo $gruppoId...');
    try {
      List<Map<String, dynamic>> varianti;

      if (hasInternet) {
        varianti = await ApiService.fetchVarianti(gruppoId);
        await dbHelper.saveAllvarianti(varianti);
        if (context.mounted) {
          await showConnectionSnackbar(context, true);
        }
        return varianti;
      } else {
        print("No internet. Fetching varianti from local database.");
        _logger.log('No internet. Fetching varianti from local database.');
        if (context.mounted) {
          await showConnectionSnackbar(context, false);
        }
        varianti = await dbHelper.queryvariantByCategory(gruppoId);
        return varianti;
        // ignore: avoid_print
      }
    } catch (e) {
       List<Map<String, dynamic>> variant;
      print("Error fetching varianti for gruppo $gruppoId: $e");
      _logger.log('Error fetching varianti for gruppo $gruppoId',error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
        variant = await dbHelper.queryvariantByCategory(gruppoId);
      print('loading locale varianti $variant');
      return await dbHelper.queryvariantByCategory(gruppoId);
    }
  }
  //impostazioni
  Future<List<Map<String, dynamic>>> getImpostazioniPalmari(
    BuildContext context, bool hasInternet) async {
  print("Fetching impostazioni palmari...");
  _logger.log('Fetching impostazioni palmari...');

  try {
    List<Map<String, dynamic>> impostazioni;

    if (hasInternet) {
      impostazioni = await ApiService.fetchImpostazionipalm();
      await dbHelper.saveImpostazioniPalm(impostazioni);
      if (context.mounted) {
        await showConnectionSnackbar(context, true);
      }
      return impostazioni;
    } else {
      print("No internet. Fetching impostazioni from local database.");
      _logger.log('No internet. Fetching impostazioni from local database.');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      impostazioni = await dbHelper.queryImpostazioniPalm();
      return impostazioni;
    }
  } catch (e) {
    print("Error fetching impostazioni palmari: $e");
    _logger.log('Error fetching impostazioni palmari', error: '$e');
    if (context.mounted) {
      await showConnectionSnackbar(context, false);
    }
    final localData = await dbHelper.queryImpostazioniPalm();
    print('Loaded local impostazioni: $localData');
    return localData;
  }
}

}
