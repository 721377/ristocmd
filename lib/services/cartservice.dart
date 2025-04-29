// cart_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CartService {
  static const String _cartKey = 'cart_items';
  static const String _tableKey = 'current_table';

  static Future<void> addProductInstance({
    required String productCode,
    required String productName,
    required double price,
    required int categoryId,
    required String categoryName,
    required int tableId,
    required int userId,
    required int hallId,
    required int sequence,
    required int agentId,
    required int orderNumber,
    List<Map<String, dynamic>> variants = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cartItems = await getCartItems(tableId: tableId);

    final instanceId = DateTime.now().millisecondsSinceEpoch.toString();
    final parsedVariants = variants.map((variant) {
      return {
        ...variant,
        'prezzo': double.tryParse(variant['prezzo'].toString()) ?? 0.0,  // Parsing prezzo into double
        'variant_type': variant['type'],  // Add the variant type (plus/minus)
      };
    }).toList();

    // Calculate variants price sum with safely parsed 'prezzo' values
    final variantsPrice = parsedVariants.fold(0.0, (sum, v) {
      if (v['variant_type'] == 'plus') {
        return sum + (v['prezzo'] ?? 0.0);
      } else if (v['variant_type'] == 'minus') {
        return sum - (v['prezzo'] ?? 0.0);
      }
      return sum;
    });

    cartItems.add({
      'cod': productCode,
      'des': productName,
      'qta': 1,
      'prz': price,
      'id_tavolo': tableId,
      'id_utente': userId,
      'id_sala': hallId,
      'seq': sequence,
      'id_cat': categoryId,
      'cat_des': categoryName,
      'id_ag': agentId,
      'num_ordine': orderNumber,
      'variants': parsedVariants,
      'variants_prz': variantsPrice,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'instance_id': instanceId,
    });

    await prefs.setString(_cartKey, json.encode(cartItems));
  }

  static Future<void> updateProductInstance({
    required String instanceId,
    required List<Map<String, dynamic>> newVariants,
    required int tableId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cartItems = await getCartItems(tableId: tableId);

    final instanceIndex = cartItems.indexWhere(
        (item) => item['instance_id'] == instanceId);

    if (instanceIndex >= 0) {
      // Safely parse the 'prezzo' field for each new variant into double
      final parsedVariants = newVariants.map((variant) {
        return {
          ...variant,
          'prezzo': double.tryParse(variant['prezzo'].toString()) ?? 0.0,  // Parsing prezzo into double
          'variant_type': variant['type'],  // Add the variant type (plus/minus)
        };
      }).toList();

      // Calculate variants price sum with safely parsed 'prezzo' values
      final variantsPrice = parsedVariants.fold(0.0, (sum, v) {
        if (v['variant_type'] == 'plus') {
          return sum + (v['prezzo'] ?? 0.0);
        } else if (v['variant_type'] == 'minus') {
          return sum - (v['prezzo'] ?? 0.0);
        }
        return sum;
      });

      cartItems[instanceIndex]['variants'] = parsedVariants;
      cartItems[instanceIndex]['variants_prz'] = variantsPrice;  // Update the price sum
      cartItems[instanceIndex]['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    }

    await prefs.setString(_cartKey, json.encode(cartItems));
  }
  
  static Future<void> removeInstance({
    required String instanceId,
    required int tableId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cartItems = await getCartItems(tableId: tableId);
    
    cartItems.removeWhere((item) => item['instance_id'] == instanceId);
    
    await prefs.setString(_cartKey, json.encode(cartItems));
  }

  static Future<void> updateCartItem({
    required String productCode,
    required int tableId,
    required int newQuantity,
    required List<Map<String, dynamic>> newVariants,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cartItems = await getCartItems(tableId: tableId);
    
    final existingItemIndex = cartItems.indexWhere((item) => 
      item['cod'] == productCode && 
      _areVariantsEqual(item['variants'] ?? [], newVariants));
    
    if (existingItemIndex >= 0) {
      cartItems[existingItemIndex]['qta'] = newQuantity;
      cartItems[existingItemIndex]['variants'] = newVariants;
      cartItems[existingItemIndex]['variants_prz'] = 
        newVariants.fold(0.0, (sum, v) => sum + (v['prezzo'] ?? 0.0));
      cartItems[existingItemIndex]['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    }
    
    await prefs.setString(_cartKey, json.encode(cartItems));
  }


  static Future<List<Map<String, dynamic>>> getProductInstances({
    required String productCode,
    required int tableId,
  }) async {
    final cartItems = await getCartItems(tableId: tableId);
    return cartItems.where((item) => item['cod'] == productCode).toList();
  }

  static Future<void> addToCart({
    required String productCode,
    required String productName,
    required double price,
    required int categoryId,
    required String categoryName,
    required int tableId,
    required int userId,
    required int hallId,
    required int sequence,
    required int agentId,
    required int orderNumber,
    List<Map<String, dynamic>> variants = const [],
    int quantity = 1,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cartItems = await getCartItems(tableId: tableId);

    final existingItemIndex = cartItems.indexWhere((item) =>
        item['cod'] == productCode &&
        _areVariantsEqual(item['variants'] ?? [], variants));

    // Safely parse the 'prezzo' field for each variant into double
    final parsedVariants = variants.map((variant) {
      return {
        ...variant,
        'prezzo': double.tryParse(variant['prezzo'].toString()) ?? 0.0,  // Parsing prezzo into double
        'variant_type': variant['type'],  // Add the variant type (plus/minus)
      };
    }).toList();

    // Calculate variants price sum with safely parsed 'prezzo' values
    final variantsPrice = parsedVariants.fold(0.0, (sum, v) {
      if (v['variant_type'] == 'plus') {
        return sum + (v['prezzo'] ?? 0.0);
      } else if (v['variant_type'] == 'minus') {
        return sum - (v['prezzo'] ?? 0.0);
      }
      return sum;
    });

    if (existingItemIndex >= 0) {
      cartItems[existingItemIndex]['qta'] =
          (cartItems[existingItemIndex]['qta'] as int) + quantity;
    } else {
      cartItems.add({
        'cod': productCode,
        'des': productName,
        'qta': quantity,
        'prz': price,
        'id_tavolo': tableId,
        'id_utente': userId,
        'id_sala': hallId,
        'seq': sequence,
        'id_cat': categoryId,
        'cat_des': categoryName,
        'id_ag': agentId,
        'num_ordine': orderNumber,
        'variants': parsedVariants,  // Store parsed variants
        'variants_prz': variantsPrice,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'instance_id': DateTime.now().millisecondsSinceEpoch.toString(),
      });
    }

    await prefs.setString(_cartKey, json.encode(cartItems));
  }

  static Future<void> removeFromCart({
    required String productCode,
    required int tableId,
    List<Map<String, dynamic>> variants = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cartItems = await getCartItems(tableId: tableId);

    cartItems.removeWhere((item) =>
        item['cod'] == productCode &&
        _areVariantsEqual(item['variants'] ?? [], variants));

    await prefs.setString(_cartKey, json.encode(cartItems));
  }

  static Future<List<Map<String, dynamic>>> getCartItems({required int tableId}) async {
    final prefs = await SharedPreferences.getInstance();
    final cartJson = prefs.getString(_cartKey);

    if (cartJson == null) return [];

    try {
      final allItems = (json.decode(cartJson) as List).cast<Map<String, dynamic>>();
      return allItems.where((item) => item['id_tavolo'] == tableId).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> clearCart({required int tableId}) async {
    final prefs = await SharedPreferences.getInstance();
    final allItems = (json.decode(prefs.getString(_cartKey) ?? '[]') as List)
        .cast<Map<String, dynamic>>()
        .where((item) => item['id_tavolo'] != tableId)
        .toList();

    await prefs.setString(_cartKey, json.encode(allItems));
  }

  static Future<void> setCurrentTable(Map<String, dynamic> table) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tableKey, json.encode(table));
  }

  static Future<Map<String, dynamic>?> getCurrentTable() async {
    final prefs = await SharedPreferences.getInstance();
    final tableJson = prefs.getString(_tableKey);
    return tableJson != null ? Map<String, dynamic>.from(json.decode(tableJson)) : null;
  }

  static bool _areVariantsEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;

    final aSorted = List.from(a)..sort((x, y) => x['id'].compareTo(y['id']));
    final bSorted = List.from(b)..sort((x, y) => x['id'].compareTo(y['id']));

    for (int i = 0; i < aSorted.length; i++) {
      if (aSorted[i]['id'] != bSorted[i]['id']) return false;
    }

    return true;
  }
}
