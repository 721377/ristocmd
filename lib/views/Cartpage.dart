import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ristocmd/services/cartservice.dart';
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/services/inviacomand.dart';
import 'package:ristocmd/serverComun.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/productlist.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:ristocmd/views/Homepage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartPage extends StatefulWidget {
  final Map<String, dynamic> tavolo;
  final void Function(String tableId, String status)? onUpdateTableStatus;
  const CartPage(
      {required this.tavolo, required this.onUpdateTableStatus, Key? key})
      : super(key: key);

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  static const Color primaryColor = Color(0xFFFEBE2B);
  static const Color backgroundColor = Colors.white;
  static const Color textColor = Colors.black;
  final AppLogger _logger = AppLogger();
  List<Map<String, dynamic>> cartItems = [];
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool isLoading = true;
  int _copertiCount = 0;
  final connectionMonitor = WifiConnectionMonitor();
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _initializeCart();
  }

  Future<void> _initializeCart() async {
    await Future.wait([
      _loadCopertiCount(),
      _loadCartItems(),
    ]);
  }

  Future<void> _loadCopertiCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.tavolo['id']}_customers';
    setState(() {
      _copertiCount = prefs.getInt(key) ?? 0;
    });
  }

  Future<void> _updateCopertiCount(int newCount) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.tavolo['id']}_customers';
    await prefs.setInt(key, newCount);
    setState(() {
      _copertiCount = newCount;
    });
    _logger.log('Updated coperti count to $newCount');
  }

Future<void> _loadCartItems() async {
  try {
    setState(() => isLoading = true);
    _logger.log('Loading cart items for table ${widget.tavolo['id']}');

    final results = await Future.wait([
      CartService.getCartItems(tableId: widget.tavolo['id']),
      dbHelper.getOrdersForTable(widget.tavolo['id']),
    ]);

    List<Map<String, dynamic>> items =
        results[0] as List<Map<String, dynamic>>;
    final orders = results[1] as List<Map<String, dynamic>>;

    _logger.log('Found ${items.length} cart items and ${orders.length} orders');

    final copertoOrder = orders.firstWhere(
      (order) => order['mov_descr'] == 'COPERTO',
      orElse: () => {},
    );

    _logger.log(copertoOrder.isNotEmpty
        ? 'Found COPERTO order with qty: ${copertoOrder['mov_qta']}'
        : 'No COPERTO order found');

    if (copertoOrder.isNotEmpty) {
      final copertoOrderQty = copertoOrder['mov_qta'] ?? 0;
      _logger.log('Current coperto order quantity: $copertoOrderQty');

      final copertoItem = items.firstWhere(
        (item) => item['des'] == 'COPERTO',
        orElse: () => {},
      );

      _logger.log(copertoItem.isNotEmpty
          ? 'Found COPERTO item in cart with qty: ${copertoItem['qta']}'
          : 'No COPERTO item found in cart');

      if (copertoItem.isNotEmpty) {
        final copertoCartQty = copertoItem['qta'] ?? 0;
        _logger.log(
            'Current state: _copertiCount=$_copertiCount, copertoOrderQty=$copertoOrderQty, copertoCartQty=$copertoCartQty');

        int? copertoOrderQtyInt = int.tryParse(copertoOrderQty.toString());

        if (copertoOrderQtyInt != null &&
            _copertiCount != copertoOrderQtyInt && _copertiCount > copertoOrderQtyInt) {
          final updatedQty = (copertoOrderQty - _copertiCount).abs();
          _logger.log('Calculated updated quantity: $updatedQty');

          // First update the local count
          await _updateCopertiCount(copertoOrderQty);

          // Then update the cart item
          final updatedItems = await CartService.updateCartItem(
            productCode: 'COPERTO',
            tableId: widget.tavolo['id'],
            newQuantity: updatedQty, // Use the order quantity directly
            newVariants: (copertoItem['variants'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
          );

          _logger.log('Updated coperto quantity in cart to $copertoOrderQty');

          setState(() {
            items = updatedItems;
          });
        } else {
          // Condition not met: remove the COPERTO item from cart
          _logger.log('Quantities match or invalid copertoOrderQtyInt, removing COPERTO item from cart');
          await CartService.removeInstance(
            instanceId: copertoItem['instance_id'],
            tableId: widget.tavolo['id'],
          );

          // Also remove it from local items list immediately
          items.removeWhere(
              (item) => item['instance_id'] == copertoItem['instance_id']);
        }
      } else {
        _logger.log('No COPERTO item found in cart to update or remove');
      }
    }

    setState(() {
      cartItems = items;
      isLoading = false;
    });
    _logger.log('Successfully loaded ${items.length} cart items');
  } catch (e) {
    _logger.log('Error loading cart items', error: e.toString());
    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error loading cart: ${e.toString()}'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  Future<void> _removeItem(String instanceId) async {
    try {
      setState(() => isLoading = true);
      await CartService.removeInstance(
        instanceId: instanceId,
        tableId: widget.tavolo['id'],
      );
      await _loadCartItems();
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing item: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateQuantity(int index, int newQuantity) async {
    if (newQuantity < 1) return;

    try {
      setState(() => isLoading = true);
      final item = cartItems[index];
      await CartService.updateCartItem(
        productCode: item['cod'],
        tableId: widget.tavolo['id'],
        newQuantity: newQuantity,
        newVariants:
            (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );
      await _loadCartItems();
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating quantity: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateVariants(
      int index, List<Map<String, dynamic>> newVariants) async {
    try {
      setState(() => isLoading = true);
      final item = cartItems[index];
      await CartService.updateProductInstance(
        instanceId: item['instance_id'],
        newVariants: newVariants,
        tableId: widget.tavolo['id'],
      );
      await _loadCartItems();
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating variants: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _formatCartForCommand() {
    final Map<String, Map<String, dynamic>> groupedItems = {};

    for (final item in cartItems) {
      final variants =
          (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final plusVariants = variants.where((v) => v['type'] != 'minus').toList();
      final minusVariants =
          variants.where((v) => v['type'] == 'minus').toList();

      final key = '${item['cod']}_${item['mov_id']}_'
          '${plusVariants.map((v) => v['cod']).join(',')}_'
          '${item['nota']}_${item['seq']}';

      final plusVariantsPrice = plusVariants.fold<double>(
        0.0,
        (sum, v) => sum + (double.tryParse(v['prezzo'].toString()) ?? 0.0),
      );

      final minusVariantsPrice = minusVariants.fold<double>(
        0.0,
        (sum, v) => sum + (double.tryParse(v['prezzo'].toString()) ?? 0.0),
      );

      if (groupedItems.containsKey(key)) {
        groupedItems[key]!['mov_qta'] += item['qta'];
      } else {
      
        groupedItems[key] = {
          'num_ordine': item['num_ordine'],
          'mov_cod': item['cod'],
          'mov_descr': item['des'],
          'mov_qta': item['qta'],
          'mov_prz': item['prz'],
          'mov_id': item['mov_id'],
          'variantiCod': plusVariants.map((v) => v['cod']).join(','),
          'variantiDes': plusVariants.map((v) => v['des']).join(','),
          'variantiPrz': plusVariantsPrice,
          'variantiCodMeno': minusVariants.map((v) => v['cod']).join(','),
          'variantiDesMeno': minusVariants.map((v) => v['des']).join(','),
          'variantiPrzMeno': minusVariantsPrice,
          'mov_com': item['id_utente'],
          'mov_note1': item['nota'] ?? '',
          'id_cat': item['id_cat'],
          'cat_des': item['cat_des'],
          'id_ag':item['id_ag'],
          'mov_codcli': item['cpc'] ?? '',
          'seq': item['seq_modificata'] == 1 ? -1 : item['seq'],
          'mov_prog_t': item['mov_prog_t'],
          'id_tavolo': item['id_tavolo'],
          'id_sala': item['id_sala'],
        };
      }
      print('the idAG = ${item['id_ag']}');
    }

    final List<Map<String, dynamic>> comanda = groupedItems.values.toList();
    comanda.sort((a, b) {
      final seqCompare = (a['seq'] as int).compareTo(b['seq'] as int);
      if (seqCompare != 0) return seqCompare;
      final catCompare =
          (a['cat_des'] as String).compareTo(b['cat_des'] as String);
      if (catCompare != 0) return catCompare;
      return (a['mov_descr'] as String).compareTo(b['mov_descr'] as String);
    });

    return comanda;
  }

  double _calculateVariantsPrice(List<dynamic> variants) {
    if (variants.isEmpty) return 0.0;
    return variants.fold(0.0, (sum, variant) {
      if (variant is Map) {
        final price =
            variant['prezzo'] ?? variant['prz'] ?? variant['price'] ?? 0.0;
        final isMinus = variant['type'] == 'minus';
        return isMinus
            ? sum - (price as num).toDouble()
            : sum + (price as num).toDouble();
      }
      return sum;
    });
  }

  double get totalPrice {
    return cartItems.fold(0.0, (sum, item) {
      final basePrice = (item['prz'] as num).toDouble();
      final variantsPrice = _calculateVariantsPrice(item['variants'] ?? []);
      final quantity = (item['qta'] as num).toInt();
      return sum + (basePrice + variantsPrice) * quantity;
    });
  }

  Future<void> _confirmOrder() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text(
            'Conferma Ordine',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          content: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Sei sicuro di voler inviare questo ordine?',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 16),
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Annulla'),
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: const Color.fromARGB(255, 168, 168, 168),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Invia'),
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF28A745),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => isLoading = true);

      final comanda = _formatCartForCommand();
      final isOnline = await connectionMonitor.isConnectedToWifi();
      final tableId = widget.tavolo['id'].toString();
      final salaId = widget.tavolo['id_sala'].toString();

      final response = await CommandService(
        notificationsPlugin: flutterLocalNotificationsPlugin,
      ).sendCompleteOrder(
        tableId: tableId,
        salaId: salaId,
        pv: '001',
        userId: '0',
        orderItems: comanda,
        context: context,
      );

      final bool isOffline = response['offline'] == true;

      await CartService.clearCart(tableId: widget.tavolo['id']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isOffline ? Icons.cloud_off : Icons.check_circle,
                color: isOffline ? Color(0xFFFFA000) : const Color(0xFF28A745),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isOffline
                      ? 'Ordine salvato in locale (offline)'
                      : 'Ordine inviato con successo',
                  style: TextStyle(
                    color:
                        isOffline ? Color(0xFFFFA000) : const Color(0xFF28A745),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor:
              isOffline ? const Color(0xFFFFF3E0) : const Color(0xFFE6F4EA),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isOffline ? Color(0xFFFFA000) : const Color(0xFF28A745),
              width: 1.1,
            ),
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      widget.onUpdateTableStatus
          ?.call(tableId, isOffline ? 'pending' : 'occupied');

      final tableLockManager = TableLockService().manager;
      await tableLockManager.updateLocalDatabaseWithOccupiedStatus(
          tableId, !isOffline);
      await dbHelper.updateTablePendingStatus(
          int.parse(tableId), isOffline ? 1 : 0);

      if (Navigator.canPop(context)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Errore: ${e.toString()}',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red[50],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Colors.red[400]!,
              width: 1.5,
            ),
          ),
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('Carrello- ${widget.tavolo['des']}'),
        centerTitle: true,
        backgroundColor: backgroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: textColor),
        actions: [
          if (!isLoading && cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Svuotare il carrello?'),
                    content: const Text('Tutti gli articoli verranno rimossi.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Annulla'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Svuota'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await CartService.clearCart(tableId: widget.tavolo['id']);
                  await _loadCartItems();
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Table info
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.table_restaurant, color: primaryColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TAVOLO ${widget.tavolo['des']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.tavolo['des_sala'] != null)
                          Text(
                            widget.tavolo['des_sala'],
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_copertiCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 18,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$_copertiCount',
                            style: TextStyle(
                              fontSize: 15,
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Cart items
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryColor))
                : Builder(
                    builder: (context) {
                      final visibleCartItems = cartItems;
                          // .where((item) => item['des'] != 'COPERTO')
                          // .toList();

                      if (visibleCartItems.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Cart is empty',
                                style:
                                    TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _loadCartItems,
                        color: primaryColor,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: visibleCartItems.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = visibleCartItems[index];
                            final variants = (item['variants'] as List?)
                                    ?.cast<Map<String, dynamic>>() ??
                                [];
                            final basePrice = (item['prz'] as num).toDouble();
                            final variantsPrice =
                                _calculateVariantsPrice(variants);
                            final totalItemPrice = (basePrice + variantsPrice) *
                                (item['qta'] as num).toInt();
                            final quantity = (item['qta'] as num).toInt();

                            return Dismissible(
                              key: Key(item['instance_id']),
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (direction) async {
                                return await showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Remove item'),
                                    content: const Text(
                                      'Are you sure you want to remove this item?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text(
                                          'Remove',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (direction) =>
                                  _removeItem(item['instance_id']),
                              child: GestureDetector(
                                onTap: () async {
                                  print(item);
                                  final shouldRefresh = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProductInstancesPage(
                                        product: item,
                                        tavolo: widget.tavolo,
                                        categorie: item['id_cat'],
                                      ),
                                    ),
                                  );
                                  if (shouldRefresh == true) {
                                    _loadCartItems(); // or whatever your cart refresh method is
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item['des'],
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: primaryColor
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    border: Border.all(
                                                        color: primaryColor),
                                                  ),
                                                  child: Text(
                                                    'x$quantity',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: primaryColor,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '€ ${totalItemPrice.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (variants.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: variants.map((variant) {
                                              final isDeleted =
                                                  variant['type'] == 'minus';
                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isDeleted
                                                      ? Colors.red
                                                          .withOpacity(0.1)
                                                      : primaryColor
                                                          .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: isDeleted
                                                        ? Colors.red
                                                        : primaryColor,
                                                  ),
                                                ),
                                                child: Text(
                                                  variant['des'] ?? '',
                                                  style: TextStyle(
                                                    color: isDeleted
                                                        ? Colors.red
                                                        : primaryColor,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                    decoration: isDeleted
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : null,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '€ ${(basePrice + variantsPrice).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),

          // Total and checkout button
          if (!isLoading && cartItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '€ ${totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _confirmOrder,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.send),
                            label: const Text(
                              'INVIA ORDINE',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
