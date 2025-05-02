import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:ristocmd/services/cartservice.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/services/inviacomand.dart';
import 'package:ristocmd/serverComun.dart';
import 'package:ristocmd/services/logger.dart';
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
}


  Future<void> _loadCartItems() async {
    try {
      setState(() => isLoading = true);
      _logger.log('Loading cart items for table ${widget.tavolo['id']}');

      // Load cart items and orders in parallel
      final results = await Future.wait([
        CartService.getCartItems(tableId: widget.tavolo['id']),
        DataRepository().getOrdersForTable(
          context,
          widget.tavolo['id'],
          await connectionMonitor.isConnectedToWifi(),
        ),
      ]);

      final items = results[0] as List<Map<String, dynamic>>;
      final orders = results[1] as List<Map<String, dynamic>>;

      // Process coperto items
      final copertoOrder = orders.firstWhere(
        (order) => order['mov_descr'] == 'COPERTO',
        orElse: () => {},
      );

      if (copertoOrder.isNotEmpty) {
        final copertoOrderQty = copertoOrder['mov_qta'] ?? 0;
        for (var item in items) {
          if (item['des'] == 'COPERTO') {
            final copertoCartQty = item['qta'];
            if (copertoCartQty > copertoOrderQty) {
              item['qta'] = copertoOrderQty;
              _updateCopertiCount(copertoOrderQty);
              await CartService.updateCartItem(
                productCode: 'COPERTO',
                tableId: widget.tavolo['id'],
                newQuantity: copertoOrderQty,
                newVariants: (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
              );
              _logger.log('Updated coperto quantity in cart');
            }
            break;
          }
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
        newVariants: (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
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

  Future<void> _updateVariants(int index, List<Map<String, dynamic>> newVariants) async {
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
      final variants = (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final plusVariants = variants.where((v) => v['type'] != 'minus').toList();
      final minusVariants = variants.where((v) => v['type'] == 'minus').toList();

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
          'id_ag': item['id_ag'],
          'mov_codcli': item['cpc'] ?? '',
          'seq': item['seq_modificata'] == 1 ? -1 : item['seq'],
          'mov_prog_t': item['mov_prog_t'],
          'id_tavolo': item['id_tavolo'],
          'id_sala': item['id_sala'],
        };
      }
    }

    final List<Map<String, dynamic>> comanda = groupedItems.values.toList();
    comanda.sort((a, b) {
      final seqCompare = (a['seq'] as int).compareTo(b['seq'] as int);
      if (seqCompare != 0) return seqCompare;
      final catCompare = (a['cat_des'] as String).compareTo(b['cat_des'] as String);
      if (catCompare != 0) return catCompare;
      return (a['mov_descr'] as String).compareTo(b['mov_descr'] as String);
    });

    return comanda;
  }

  double _calculateVariantsPrice(List<dynamic> variants) {
    if (variants.isEmpty) return 0.0;
    return variants.fold(0.0, (sum, variant) {
      if (variant is Map) {
        final price = variant['prezzo'] ?? variant['prz'] ?? variant['price'] ?? 0.0;
        final isMinus = variant['type'] == 'minus';
        return isMinus ? sum - (price as num).toDouble() : sum + (price as num).toDouble();
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
        builder: (context) => AlertDialog(
          title: const Text('Confirm Order'),
          content: const Text('Are you sure you want to send this order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => isLoading = true);
      final comanda = _formatCartForCommand();
      final isOnline = await connectionMonitor.isConnectedToWifi();

      final response = await CommandService(
              notificationsPlugin: flutterLocalNotificationsPlugin)
          .sendCompleteOrder(
        tableId: widget.tavolo['id'].toString(),
        salaId: widget.tavolo['id_sala'].toString(),
        pv: '001',
        userId: '0',
        orderItems: comanda,
        context: context,
      );

      if (response['success'] == true) {
        await CartService.clearCart(tableId: widget.tavolo['id']);
        final newStatus = isOnline ? 'occupied' : 'pending';

        if (widget.onUpdateTableStatus != null) {
          widget.onUpdateTableStatus!(widget.tavolo['id'].toString(), newStatus);
        } else if (homePageKey.currentState != null) {
          homePageKey.currentState!.updateTableStatus(
              widget.tavolo['id'].toString(), newStatus);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Order sent successfully'),
            backgroundColor: response['offline'] == true ? Colors.orange : Colors.green,
          ),
        );
        
        if (Navigator.canPop(context)) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to send order'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
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
        title: Text('Cart - ${widget.tavolo['des']}'),
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
                    title: const Text('Clear Cart?'),
                    content: const Text('All items will be removed.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Clear'),
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
                          'Table ${widget.tavolo['des']}',
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
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : Builder(
                    builder: (context) {
                      final visibleCartItems = cartItems
                          .where((item) => item['des'] != 'COPERTO')
                          .toList();

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
                                style: TextStyle(fontSize: 18, color: Colors.grey),
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
                            final variantsPrice = _calculateVariantsPrice(variants);
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
                                child: const Icon(Icons.delete, color: Colors.white),
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
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true),
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          Text(
                                            '€ ${totalItemPrice.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (variants.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: variants.map((variant) {
                                            final isDeleted = variant['type'] == 'minus';
                                            return Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDeleted
                                                    ? Colors.red.withOpacity(0.1)
                                                    : primaryColor.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isDeleted
                                                      ? Colors.red
                                                      : primaryColor,
                                                ),
                                              ),
                                              child: Text(
                                                variant['des'] ?? '',
                                                style: TextStyle(
                                                  color: isDeleted ? Colors.red : primaryColor,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 13,
                                                  decoration: isDeleted
                                                      ? TextDecoration.lineThrough
                                                      : null,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Quantity selector
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove, size: 18),
                                                  onPressed: () =>
                                                      _updateQuantity(index, quantity - 1),
                                                  padding: EdgeInsets.zero,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                Text(
                                                  quantity.toString(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add, size: 18),
                                                  onPressed: () =>
                                                      _updateQuantity(index, quantity + 1),
                                                  padding: EdgeInsets.zero,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '€ ${(basePrice + variantsPrice).toStringAsFixed(2)} each',
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
                              'SEND ORDER',
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