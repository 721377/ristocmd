import 'package:flutter/material.dart';
import 'package:ristocmd/services/cartservice.dart';
import 'package:ristocmd/services/inviacomand.dart';
import 'package:ristocmd/serverComun.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartPage extends StatefulWidget {
  final Map<String, dynamic> tavolo;

  const CartPage({required this.tavolo, Key? key}) : super(key: key);

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  static const Color primaryColor = Color(0xFFFEBE2B);
  static const Color backgroundColor = Colors.white;
  static const Color textColor = Colors.black;
  List<Map<String, dynamic>> cartItems = [];
  bool isLoading = true;
  int _copertiCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCartItems();
    _loadCopertiCount();
  }

  Future<void> _loadCopertiCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.tavolo['id']}_customers';
    setState(() {
      _copertiCount = prefs.getInt(key) ?? 0;
    });
  }

  Future<void> _loadCartItems() async {
    try {
      final items = await CartService.getCartItems(
        tableId: widget.tavolo['id'],
      );
      setState(() {
        cartItems = items;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeItem(String instanceId) async {
    try {
      await CartService.removeInstance(
        instanceId: instanceId,
        tableId: widget.tavolo['id'],
      );
      await _loadCartItems();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateQuantity(int index, int newQuantity) async {
    if (newQuantity < 1) return;

    try {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante l\'aggiornamento: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateVariants(
      int index, List<Map<String, dynamic>> newVariants) async {
    try {
      final item = cartItems[index];
      await CartService.updateProductInstance(
        instanceId: item['instance_id'],
        newVariants: newVariants,
        tableId: widget.tavolo['id'],
      );
      await _loadCartItems();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante l\'aggiornamento delle varianti: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

List<Map<String, dynamic>> _formatCartForCommand() {
  final Map<String, Map<String, dynamic>> groupedItems = {};

  for (final item in cartItems) {
    final variants = (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final key = '${item['cod']}_${item['mov_id']}_'
        '${variants.map((v) => v['cod']).join(',')}_'
        '${variants.where((v) => v['type'] == 'minus').map((v) => v['cod']).join(',')}_'
        '${item['nota']}_${item['seq']}';

    final variantsPrice = variants.fold<double>(
      0.0,
      (sum, v) => sum + ((v['prz'] ?? 0) as num).toDouble(),
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
        'variantiCod': variants.map((v) => v['cod']).join(','),
        'variantiDes': variants.map((v) => v['des']).join(','),
        'variantiPrz': variantsPrice,
        'variantiCodMeno': variants
            .where((v) => v['type'] == 'minus')
            .map((v) => v['cod'])
            .join(','),
        'variantiDesMeno': variants
            .where((v) => v['type'] == 'minus')
            .map((v) => v['des'])
            .join(','),
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


  Future<void> _confirmOrder() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Conferma Ordine'),
          content: const Text('Sei sicuro di voler inviare questo ordine?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Invia'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        final comanda = _formatCartForCommand();

        final response = await CommandService().sendCompleteOrder(
          tableId: widget.tavolo['id'].toString(),
          salaId: widget.tavolo['id_sala'].toString(),
          pv: '001',
          userId: '0',
          orderItems: comanda,
          context: context,
        );

        if (response['success'] == true) {
          if (response['offline'] != true) {
            await CartService.clearCart(tableId: widget.tavolo['id']);
          }

          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response['message'] ?? 'Ordine inviato con successo'),
              backgroundColor:
                  response['offline'] == true ? Colors.orange : Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Invio ordine fallito'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  double get totalPrice {
    return cartItems.fold(0.0, (sum, item) {
      final basePrice = (item['prz'] as num).toDouble();
      final variantsPrice = _calculateVariantsPrice(item['variants'] ?? []);
      final quantity = (item['qta'] as num).toInt();
      return sum + (basePrice + variantsPrice) * quantity;
    });
  }

double _calculateVariantsPrice(List<dynamic> variants) {
  if (variants.isEmpty) return 0.0;
  
  try {
    return variants.fold(0.0, (sum, variant) {
      if (variant is Map) {
        // Try multiple possible keys for price
        final price = variant['prezzo'] ?? variant['prz'] ?? variant['price'] ?? 0.0;
        return sum + (price as num).toDouble();
      }
      return sum;
    });
  } catch (e) {
    return 0.0;
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('Carrello - ${widget.tavolo['des']}'),
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
                          'Tavolo ${widget.tavolo['des']}',
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
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_copertiCount coperti',
                        style: TextStyle(
                          fontSize: 12,
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
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
                    child: CircularProgressIndicator(color: primaryColor),
                  )
                : cartItems.isEmpty
                    ? Center(
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
                              'Il carrello è vuoto',
                              style:
                                  TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCartItems,
                        color: primaryColor,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: cartItems.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = cartItems[index];
                            final variants = (item['variants'] as List?)
                                    ?.cast<Map<String, dynamic>>() ??
                                [];
                            final basePrice = (item['prz'] as num).toDouble();
                            final variantsPrice = _calculateVariantsPrice(
                                variants); // Use helper method
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
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (direction) async {
                                return await showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Rimuovere articolo'),
                                    content: const Text(
                                      'Sei sicuro di voler rimuovere questo articolo dal carrello?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Annulla'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text(
                                          'Rimuovi',
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
                                          children: variants
                                              .map((variant) => Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                              0xFFFEBE2B)
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                      border: Border.all(
                                                        color: const Color(
                                                            0xFFFEBE2B),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      variant['des'] ?? '',
                                                      style: const TextStyle(
                                                        color:
                                                            Color(0xFFFEBE2B),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Quantity selector
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove,
                                                      size: 18),
                                                  onPressed: () =>
                                                      _updateQuantity(
                                                          index, quantity - 1),
                                                  padding: EdgeInsets.zero,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                Text(
                                                  quantity.toString(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add,
                                                      size: 18),
                                                  onPressed: () =>
                                                      _updateQuantity(
                                                          index, quantity + 1),
                                                  padding: EdgeInsets.zero,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '€ ${(basePrice + variantsPrice).toStringAsFixed(2)} cad.',
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
                        'Totale:',
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
