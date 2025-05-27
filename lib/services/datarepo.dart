import 'dart:async' show StreamController;
import 'dart:convert';
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

  Stream<List<Map<String, dynamic>>> get tablesStream =>
      _tablesController.stream;

  //categorie managment
  final StreamController<List<Map<String, dynamic>>> _gruppiController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get gruppiStream =>
      _gruppiController.stream;
  String listinopalm = Settings.listinoPalmari.toString().padLeft(2, '0');
  DataRepository();

  final duration = Duration(seconds: 5);

  void dispose() {
    _tablesController.close();
  }

  Future<void> showConnectionSnackbar(
      BuildContext context, bool isConnected) async {
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

  Future<List<Map<String, dynamic>>> getSalas(
      BuildContext context, bool hasInternet) async {
    print("Fetching salas...");
    try {
      List<Map<String, dynamic>> salas;

      if (hasInternet) {
        print("Fetching salas from API");
        salas = await ApiService.fetchSalas();

        final formattedSalas = salas
            .map((sala) => {
                  'id': sala['id'],
                  'des': sala['des'],
                  'listino': sala['listino'],
                })
            .toList();

        await dbHelper.saveAllSalas(formattedSalas);

        await Future.wait(
            salas.map((sala) => _syncTavolosForSala(context, sala['id'])));

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

  Future<List<Map<String, dynamic>>> getTavolos(
      BuildContext context, int salaId, bool hasInternet) async {
    print("Fetching tavolos for sala $salaId...");
    _logger.log('Fetching tavolos for sala $salaId...');
    try {
      List<Map<String, dynamic>> tavolos;

      if (hasInternet) {
        print("Fetching tavolos from API");
        tavolos = await ApiService.fetchTavolos(salaId).timeout(
          duration,
          onTimeout: () async {
            return await dbHelper.queryTavolosBySala(salaId);
          },
        );
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

  List<Map<String, dynamic>> _filterTavolos(
      List<Map<String, dynamic>> tavolos) {
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
        'is_pending': tavolo['is_pending'] ?? '',
        'is_occupied': (tavolo['conti_aperti'] > 0) ? 1 : 0,
      };
    }).toList();
  }

  Future<void> _saveFilteredTavolos(
      int salaId, List<Map<String, dynamic>> tavolos) async {
    await dbHelper.saveAllTavolos(salaId, _filterTavolos(tavolos));
  }

  Future<List<Map<String, dynamic>>> getOrdersForTable(
      BuildContext context, int tavoloId, bool hasInternet) async {
    print("Fetching orders for table $tavoloId...");
    _logger.log('Fetching orders for table $tavoloId...');
    try {
      List<Map<String, dynamic>> orders;

      if (hasInternet) {
        print("Fetching orders from API");
        _logger.log('Fetching orders from API');
        orders = await ApiService.fetchMovtable(tavoloId).timeout(duration,
            onTimeout: () async {
          orders = await dbHelper.getOrdersForTable(tavoloId);
          return orders;
        });
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
        'variantiDesMeno': order['variantiDesMeno'],
        'variantiPrzMeno': order['variantiPrzMeno'],
        'seq': order['seq'],
        'pagato': order['pagato'],
        'created_at': order['created_at'],
        'updated_at': order['updated_at'],
      };
    }).toList();
  }

  //categories managment
  Future<List<Map<String, dynamic>>> getGruppi(
      BuildContext context, bool hasInternet) async {
    print("Fetching gruppi...");
    _logger.log('Fetching gruppi...');
    try {
      List<Map<String, dynamic>> gruppi;

      if (hasInternet) {
        print("Fetching gruppi from API");
        _logger.log('Fetching gruppi from API');
        gruppi = await ApiService.fetchGruppi().timeout(
          duration,
          onTimeout: () async {
            return await dbHelper.queryAllGruppi();
          },
        );
        await dbHelper.saveAllGruppi(gruppi);

        // Fetch and save articoli per gruppo
        // await Future.wait(
        //   gruppi.expand((gruppo) => [
        //     _syncArticoliForGruppo(context, gruppo['id']),
        //     _syncVariantForGruppo(context, gruppo['id']),
        //   ]),
        // );

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
  Future<void> _syncArticoliForGruppo(
      BuildContext context, int gruppoId) async {
    try {
      final articoli = await ApiService.fetchArtByGruppi(gruppoId, listinopalm).timeout(
          duration,
          onTimeout: () async {
            return await dbHelper.queryArticoliByCategory(gruppoId);
          },
        );
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
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'articoli_gruppo_$gruppoId';

    if (hasInternet) {
      List<Map<String, dynamic>> articoli = await ApiService
          .fetchArtByGruppi(gruppoId, listinopalm)
          .timeout(duration, onTimeout: () async {
        return await dbHelper.queryArticoliByCategory(gruppoId);
      });

      print('listino palmare $listinopalm');
      await dbHelper.saveAllArticoli(articoli);

      // Save to SharedPreferences
      final encoded = jsonEncode(articoli);
      await prefs.setString(cacheKey, encoded);

      if (context.mounted) {
        await showConnectionSnackbar(context, true);
      }

      return articoli;
    } else {
      print("No internet. Checking SharedPreferences...");
      _logger.log('No internet. Checking SharedPreferences...');

      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }

      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null && cachedData.isNotEmpty) {
        print("Loading articoli from SharedPreferences cache.");
        final decoded = jsonDecode(cachedData);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }

      print("No valid SharedPreferences cache. Loading from local DB.");
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
        varianti = await ApiService.fetchVarianti(gruppoId).timeout(
          duration,
          onTimeout: () async {
            return await dbHelper.queryvariantByCategory(gruppoId);
          },
        );
        print('datarepo vari: $varianti');
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
      _logger.log('Error fetching varianti for gruppo $gruppoId', error: '$e');
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
        impostazioni = await ApiService.fetchImpostazionipalm().timeout(
          duration,
          onTimeout: () async {
            return await dbHelper.queryImpostazioniPalm();
          },
        );
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

  Future<List<Map<String, dynamic>>> getOperatore(
      BuildContext context, bool hasInternet) async {
    print("Fetching operatore palmari...");
    _logger.log('Fetching operatore  palmari...');

    try {
      List<Map<String, dynamic>> operatore;

      if (hasInternet) {
        operatore = await ApiService.fetchOperatore().timeout(
          duration,
          onTimeout: () async {
            return await dbHelper.queryOperatore();
          },
        );
        await dbHelper.saveOperatore(operatore);
        if (context.mounted) {
          await showConnectionSnackbar(context, true);
        }
        return operatore;
      } else {
        print("No internet. Fetching operatore  from local database.");
        _logger.log('No internet. Fetching operatore  from local database.');
        if (context.mounted) {
          await showConnectionSnackbar(context, false);
        }
        operatore = await dbHelper.queryOperatore();
        return operatore;
      }
    } catch (e) {
      print("Error Fetching operatore  palmari: $e");
      _logger.log('Error Fetching operatore  palmari', error: '$e');
      if (context.mounted) {
        await showConnectionSnackbar(context, false);
      }
      final localData = await dbHelper.queryOperatore();
      print('Loaded local  operatore : $localData');
      return localData;
    }
  }

  Future<double> getCopertoPrice(BuildContext context, bool hasInternet) async {
  const String copertoKey = 'copertoprice';
  double price = 0.0;

  try {
    final prefs = await SharedPreferences.getInstance();

    if (hasInternet) {
      _logger.log('Fetching coperto price from API...');
      final result = await ApiService.getcopertoprice(listinopalm).timeout(duration);
      
      if (result is num) {
        price = result.toDouble();

        // Save to SharedPreferences
        await prefs.setDouble(copertoKey, price);
        _logger.log('Coperto price saved: $price');
      } else {
        _logger.log('Unexpected API result type: $result');
      }
    } else {
      // Load from SharedPreferences
      price = prefs.getDouble(copertoKey) ?? 0.0;
      _logger.log('Loaded coperto price from local: $price');
    }
  } catch (e) {
    _logger.log('Error fetching coperto price: $e');

    // On error, attempt to load from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    price = prefs.getDouble(copertoKey) ?? 0.0;
    _logger.log('Fallback to local coperto price: $price');
  }

  return price;
}
}
