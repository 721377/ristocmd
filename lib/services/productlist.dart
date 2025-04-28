// product_list_page.dart
import 'package:flutter/material.dart';
import 'package:ristocmd/services/cartservice.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:ristocmd/views/Cartpage.dart';
import 'package:ristocmd/views/widgets/Appbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductList extends StatefulWidget {
  final Map<String, dynamic> category;
  final VoidCallback onBackPressed;
  final Map<String, dynamic> tavolo;
  const ProductList({
    required this.tavolo,
    required this.category,
    required this.onBackPressed,
    Key? key,
  }) : super(key: key);

  @override
  _ProductListState createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  static const Color primaryColor = Color(0xFFFEBE2B);
  static const Color backgroundColor = Colors.white;
  static const Color textColor = Colors.black87;
  static const Color cardColor = Colors.white;
  static const Color borderColor = Color(0xFFEEEEEE);
  static const Color accentColor = Color(0xFF4CAF50);

  final DataRepository dataRepo = DataRepository();
  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> products = [];
  bool isLoading = true;
  String searchQuery = '';
  int _cartItemCount = 0;
  int _copertiCount = 0;
  final connectionMonitor = WifiConnectionMonitor();

  @override
  void initState() {
    super.initState();
    connectionMonitor.startMonitoring();
    _settable();
    _loadProducts();
    _loadCartCount();
    _loadCopertiCount();
    searchController.addListener(() {
      setState(() => searchQuery = searchController.text.toLowerCase());
    });
  }

  Future<void> _loadCopertiCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.tavolo['id']}_customers';
    setState(() {
      _copertiCount = prefs.getInt(key) ?? 0;
    });
    
    if (_copertiCount > 0) {
      await _addCopertoToCart();
    }
  }

  Future<void> _addCopertoToCart() async {
    try {
      final currentTable = await CartService.getCurrentTable();
      if (currentTable == null) throw Exception('No table selected');

      final cartItems = await CartService.getCartItems(tableId: widget.tavolo['id']);
      final hasCoperto = cartItems.any((item) => item['cod'] == 'COPERTO');
      
      if (!hasCoperto) {
        await CartService.addToCart(
          productCode: 'COPERTO',
          productName: 'COPERTO',
          price: 0.0,
          categoryId: widget.category['id'],
          categoryName: widget.category['des'],
          tableId: widget.tavolo['id'],
          userId: 0,
          hallId: widget.tavolo['id_sala'],
          sequence: 1,
          agentId: 1,
          orderNumber: widget.tavolo['num_ordine'] ?? 0,
          variants: [],
          quantity: _copertiCount,
        );
      }
    } catch (e) {
      print('Error adding coperto to cart: $e');
    }
  }

  Future<void> _loadCartCount() async {
    final cartItems = await CartService.getCartItems(tableId: widget.tavolo['id']);
    setState(() {
      _cartItemCount = cartItems.fold(0, (sum, item) => sum + (item['qta'] as int));
    });
  }

  Future<void> _settable() async {
    await CartService.setCurrentTable(widget.tavolo);
  }
  
  Future<void> _loadProducts() async {
    try {
      products = await dataRepo.dbHelper.queryArticoliByCategory(
        widget.category['id'],
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<int> _getProductCountInCart(String productCode) async {
    final cartItems = await CartService.getCartItems(tableId: widget.tavolo['id']);
    return cartItems.where((item) => item['cod'] == productCode).length;
  }

  Future<void> _addProductInstance(Map<String, dynamic> product, {int quantity = 1}) async {
    try {
      // Check if product already exists in cart with no variants
      final cartItems = await CartService.getCartItems(tableId: widget.tavolo['id']);
      final existingItemIndex = cartItems.indexWhere((item) => 
        item['cod'] == product['cod'] && 
        (item['variants'] == null || (item['variants'] as List).isEmpty));

      if (existingItemIndex >= 0 && quantity > 1) {
        // Update quantity of existing item
        await CartService.updateCartItem(
          productCode: product['cod'],
          tableId: widget.tavolo['id'],
          newQuantity: cartItems[existingItemIndex]['qta'] + quantity,
          newVariants: [],
        );
      } else {
        // Add new instances
        for (int i = 0; i < quantity; i++) {
          await CartService.addProductInstance(
            productCode: product['cod'],
            productName: product['des'],
            price: double.tryParse(product['prezzo'].toString()) ?? 0.0,
            categoryId: widget.category['id'],
            categoryName: widget.category['des'],
            tableId: widget.tavolo['id'],
            userId: 0,
            hallId: widget.tavolo['id_sala'],
            sequence: 1,
            agentId: 1,
            orderNumber: widget.tavolo['num_ordine'] ?? 0,
            variants: [], // Start with empty variants
          );
        }
      }

      // Show snackbar only once with total quantity
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${quantity}x ${product['des']} aggiunto al carrello'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: accentColor,
          ),
        );
      }
      
      await _loadCartCount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleLongPress(Map<String, dynamic> product) async {
    final quantity = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuantitySelectionModal(product: product),
    );

    if (quantity != null && quantity > 0) {
      await _addProductInstance(product, quantity: quantity);
    }
  }

  List<Map<String, dynamic>> get filteredProducts {
    if (searchQuery.isEmpty) return products;
    return products
        .where((p) => p['des'].toString().toLowerCase().contains(searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: widget.category['des'],
        showBackButton: true,
        cartItemCount: _cartItemCount,
        onCartPressed: () {
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (_) => CartPage(tavolo: widget.tavolo))
          ).then((_) => _loadCartCount());
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Cerca...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: borderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: primaryColor, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 60, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            const Text('Nessun risultato', style: TextStyle(fontSize: 18, color: Colors.grey)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) => _buildProductCard(filteredProducts[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final double basePrice = double.tryParse(product['prezzo'].toString()) ?? 0;
    final totalPrice = basePrice.toStringAsFixed(2);

    return FutureBuilder<int>(
      future: _getProductCountInCart(product['cod']),
      builder: (context, snapshot) {
        final countInCart = snapshot.data ?? 0;
        
        return GestureDetector(
          onTap: () => _addProductInstance(product),
          onLongPress: () => _handleLongPress(product),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: Text(
                            product['des'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$totalPrice €',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          _buildActionButton(product, countInCart > 0),
                        ],
                      ),
                    ),
                  ],
                ),
                if (countInCart > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$countInCart',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton(Map<String, dynamic> product, bool isInCart) {
    if (isInCart) {
      return InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductInstancesPage(
                product: product,
                tavolo: widget.tavolo,
                categorie: widget.category,
              ),
            ),
          ).then((_) => _loadCartCount());
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.edit,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    } else {
      return InkWell(
        onTap: () => _addProductInstance(product),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.add,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
    }
  }
}

class QuantitySelectionModal extends StatefulWidget {
  final Map<String, dynamic> product;
  
  const QuantitySelectionModal({required this.product, Key? key}) : super(key: key);

  @override
  _QuantitySelectionModalState createState() => _QuantitySelectionModalState();
}

class _QuantitySelectionModalState extends State<QuantitySelectionModal> {
  int quantity = 1;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Quanti ${widget.product['des']} vuoi aggiungere?',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 32),
                onPressed: () {
                  if (quantity > 1) {
                    setState(() => quantity--);
                  }
                },
              ),
              Container(
                width: 80,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFFEBE2B)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  quantity.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 32),
                onPressed: () {
                  if (quantity < 20) {
                    setState(() => quantity++);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, 0),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Colors.grey),
                  ),
                  child: const Text(
                    'ANNULLA',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, quantity),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEBE2B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'AGGIUNGI',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class ProductInstancesPage extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> tavolo;
  final Map<String, dynamic> categorie;
  
  const ProductInstancesPage({
    required this.product,
    required this.tavolo,
    required this.categorie,
    Key? key,
  }) : super(key: key);

  @override
  _ProductInstancesPageState createState() => _ProductInstancesPageState();
}

class _ProductInstancesPageState extends State<ProductInstancesPage> {
  List<Map<String, dynamic>> instances = [];
  bool isLoading = true;
  final DataRepository dataRepo = DataRepository();
  final connectionMonitor = WifiConnectionMonitor();

  @override
  void initState() {
    super.initState();
    _loadInstances();
  }

  Future<void> _loadInstances() async {
    final loadedInstances = await CartService.getProductInstances(
      productCode: widget.product['cod'],
      tableId: widget.tavolo['id'],
    );
    setState(() {
      instances = loadedInstances;
      isLoading = false;
    });
  }

  Future<void> _updateInstanceVariants(int index) async {
    final instance = instances[index];
    final isOnline = await connectionMonitor.isConnectedToWifi();
    final variants = await dataRepo.getvariantiByGruppo(
      context, 
      widget.categorie['id'], 
      isOnline
    );

    final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => VariantSelectionModal(
        variants: variants,
        initialSelection: List.from(instance['variants'] ?? []),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await CartService.updateProductInstance(
        instanceId: instance['instance_id'],
        newVariants: result,
        tableId: widget.tavolo['id'],
      );
      await _loadInstances();
    }
  }

  Future<void> _removeInstance(int index) async {
    final instance = instances[index];
    await CartService.removeInstance(
      instanceId: instance['instance_id'],
      tableId: widget.tavolo['id'],
    );
    await _loadInstances();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product['des']),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : instances.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Nessun articolo nel carrello'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Torna indietro'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: instances.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final instance = instances[index];
                          final variants = instance['variants'] ?? [];
                          final variantText = variants.isEmpty
                              ? 'Nessuna variante'
                              : variants.map((v) => v['des']).join(', ');

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                              title: Text(
                                'Articolo #${index + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(variantText),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${instance['prz']} €',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFEBE2B),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _updateInstanceVariants(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _removeInstance(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEBE2B),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'FATTO',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class VariantSelectionModal extends StatefulWidget {
  final List<Map<String, dynamic>> variants;
  final List<Map<String, dynamic>> initialSelection;
  
  const VariantSelectionModal({
    required this.variants,
    required this.initialSelection,
    Key? key,
  }) : super(key: key);

  @override
  _VariantSelectionModalState createState() => _VariantSelectionModalState();
}

class _VariantSelectionModalState extends State<VariantSelectionModal> {
  late List<Map<String, dynamic>> selectedVariants;

  @override
  void initState() {
    super.initState();
    selectedVariants = List.from(widget.initialSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Seleziona varianti',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: widget.variants.length,
              itemBuilder: (context, index) {
                final variant = widget.variants[index];
                final isSelected = selectedVariants.any(
                  (v) => v['id'] == variant['id']);

                return CheckboxListTile(
                  title: Text(variant['des']),
                  subtitle: Text('+${variant['prezzo']} €'),
                  value: isSelected,
                  activeColor: const Color(0xFFFEBE2B),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        selectedVariants.add(variant);
                      } else {
                        selectedVariants.removeWhere(
                          (v) => v['id'] == variant['id']);
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, selectedVariants),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFEBE2B),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'CONFERMA',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}