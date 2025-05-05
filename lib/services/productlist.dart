import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ristocmd/Settings/settings.dart';
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
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const ProductList({
    required this.tavolo,
    required this.category,
    required this.onBackPressed,
    required this.onUpdateTableStatus,
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
  bool _compactView = false; // New state for compact view
  final connectionMonitor = WifiConnectionMonitor();

  @override
  void initState() {
    super.initState();
    connectionMonitor.startMonitoring();
    Settings.loadAllSettings();
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

      final cartItems =
          await CartService.getCartItems(tableId: widget.tavolo['id']);
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
    final cartItems =
        await CartService.getCartItems(tableId: widget.tavolo['id']);
    final filteredItems = cartItems.where((item) => item['des'] != 'COPERTO');

    setState(() {
      _cartItemCount =
          filteredItems.fold(0, (sum, item) => sum + (item['qta'] as int));
    });
  }

  Future<void> _settable() async {
    await CartService.setCurrentTable(widget.tavolo);
  }

  Future<void> _loadProducts() async {
    try {
      final _isOnline = await connectionMonitor.isConnectedToWifi();
      products = await DataRepository()
          .getArticoliByGruppo(context, widget.category['id'], _isOnline);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<int> _getProductCountInCart(String productCode) async {
    final cartItems =
        await CartService.getCartItems(tableId: widget.tavolo['id']);
    return cartItems.where((item) => item['cod'] == productCode).length;
  }

  Future<void> _addProductInstance(Map<String, dynamic> product,
      {int quantity = 1}) async {
    try {
      // Check if product already exists in cart with no variants
      final cartItems =
          await CartService.getCartItems(tableId: widget.tavolo['id']);
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
            content:
                Text('${quantity}x ${product['des']} aggiunto al carrello'),
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

  // New method to toggle compact view
  void _toggleCompactView() {
    setState(() {
      _compactView = !_compactView;
    });
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
              MaterialPageRoute(
                  builder: (_) => CartPage(
                        tavolo: widget.tavolo,
                        onUpdateTableStatus: widget.onUpdateTableStatus,
                      ))).then((_) => _loadCartCount());
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Cerca...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide:
                            const BorderSide(color: borderColor, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide:
                            const BorderSide(color: primaryColor, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Compact view toggle button
                InkWell(
                  onTap: _toggleCompactView,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _compactView ? primaryColor : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _compactView ? Icons.grid_view : Icons.view_list,
                      color: _compactView ? Colors.white : Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryColor))
                : filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 60, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            const Text('Nessun risultato',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.grey)),
                          ],
                        ),
                      )
                    : _compactView
                        ? _buildCompactProductList()
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) =>
                                _buildProductCard(filteredProducts[index]),
                          ),
          ),
        ],
      ),
    );
  }

  // New method for compact product list
  Widget _buildCompactProductList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        return _buildCompactProductItem(product);
      },
    );
  }

  // New method for compact product item
  Widget _buildCompactProductItem(Map<String, dynamic> product) {
    return FutureBuilder<int>(
      future: _getProductCountInCart(product['cod']),
      builder: (context, snapshot) {
        final countInCart = snapshot.data ?? 0;

        return GestureDetector(
          onTap: () => _addProductInstance(product),
          child: Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              children: [
                if (countInCart > 0)
                  Container(
                    width: 30,
                    alignment: Alignment.center,
                    child: Text(
                      'x$countInCart',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      product['des'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _buildCompactActionButton(product, countInCart > 0),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // New method for compact action button
  Widget _buildCompactActionButton(
      Map<String, dynamic> product, bool isInCart) {
    return InkWell(
      onTap: () {
        if (isInCart) {
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
        } else {
          _addProductInstance(product);
        }
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isInCart ? Colors.black : primaryColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isInCart ? Icons.edit : Icons.add,
          color: Colors.white,
          size: 18,
        ),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                    color: const Color.fromARGB(255, 246, 246, 246),
                    width: 1.2)),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Product name
                      Expanded(
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

                      const SizedBox(height: 12),

                      // Price & Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$totalPrice €',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          _buildActionButton(product, countInCart > 0),
                        ],
                      ),
                    ],
                  ),
                ),

                // Cart count badge
                if (countInCart > 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'x$countInCart',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
    return InkWell(
      onTap: () {
        if (isInCart) {
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
        } else {
          _addProductInstance(product);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color:
              isInCart ? const Color.fromARGB(255, 23, 23, 23) : primaryColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (isInCart
                      ? const Color.fromARGB(255, 23, 23, 23)
                      : primaryColor)
                  .withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isInCart ? Icons.edit : Icons.add,
              color: Colors.white,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class QuantitySelectionModal extends StatefulWidget {
  final Map<String, dynamic> product;

  const QuantitySelectionModal({required this.product, Key? key})
      : super(key: key);

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
  final dynamic categorie;

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

  Future<void> _showDeleteConfirmation(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Conferma eliminazione'),
        content: Text('Vuoi rimuovere questo articolo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeInstance(index);
    }
  }

  Future<void> _updateQuantity(int index, int newQuantity) async {
    if (newQuantity < 1) {
      await _removeInstance(index);
      return;
    }

    final instance = instances[index];
    try {
      await CartService.updateCartItem(
        productCode: widget.product['cod'],
        tableId: widget.tavolo['id'],
        newQuantity: newQuantity,
        newVariants: List.from(instance['variants'] ?? []),
      );
      await _loadInstances();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: ${e.toString()}')),
      );
    }
  }

  Future<void> _updateInstanceVariants(int index) async {
    final instance = instances[index];
    final isOnline = await connectionMonitor.isConnectedToWifi();

    int? categoryId;
    if (widget.categorie is Map<String, dynamic>) {
      categoryId = widget.categorie['id'];
    } else{
       categoryId = widget.categorie;
    }

    if (categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nessuna categoria valida trovata $categoryId')),
      );
      return;
    }

    try {
      final variants =
          await dataRepo.getvariantiByGruppo(context, categoryId, isOnline);

      final formattedVariants = variants.asMap().entries.map((entry) {
        final index = entry.key;
        final variant = entry.value;
        final id = variant['id'] ?? -(index + 1);

        return {
          ...variant,
          'id': id,
          'prezzo': (double.tryParse(variant['prezzo'].toString()) ?? 0.0)
              .toStringAsFixed(2),
        };
      }).toList();

      final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: context,
        isScrollControlled: true,
        builder: (context) => VariantSelectionModal(
          variants: formattedVariants,
          initialSelection: List.from(instance['variants'] ?? []),
        ),
      );

      if (result != null) {
        await CartService.updateProductInstance(
          instanceId: instance['instance_id'],
          newVariants: result,
          tableId: widget.tavolo['id'],
        );
        await _loadInstances();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: ${e.toString()}')),
      );
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.product['des'],
          style: GoogleFonts.quicksand(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context,true),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFFFEBE2B)))
          : instances.isEmpty
              ? Center(child: _buildEmptyState())
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListView.separated(
                    physics: BouncingScrollPhysics(),
                    itemCount: instances.length,
                    separatorBuilder: (context, index) => SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final instance = instances[index];
                      final variants = instance['variants'] ?? [];
                      final variantText =
                          variants.map((v) => v['des']).join(', ');
                      final quantity = instance['qta'] ?? 1;

                      return Dismissible(
                        key: Key(instance['instance_id'].toString()),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (direction) async {
                          await _showDeleteConfirmation(index);
                          return false;
                        },
                        background: _buildDeleteBackground(),
                        child: GestureDetector(
                          onTap: () => _updateInstanceVariants(index),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Articolo #${index + 1}',
                                              style: GoogleFonts.quicksand(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (variantText.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4),
                                                child: Text(
                                                  variantText,
                                                  style: GoogleFonts.quicksand(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${instance['prz']} €',
                                        style: GoogleFonts.quicksand(
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFFEBE2B),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove,
                                                  size: 18),
                                              onPressed: () => _updateQuantity(
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
                                              onPressed: () => _updateQuantity(
                                                  index, quantity + 1),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400,
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
                ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shopping_cart_outlined,
            size: 48, color: Colors.grey.shade400),
        SizedBox(height: 16),
        Text(
          'Nessun articolo nel carrello',
          style: GoogleFonts.quicksand(
            fontSize: 16,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFFEBE2B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            'Torna indietro',
            style: GoogleFonts.quicksand(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: EdgeInsets.only(right: 24),
      child: Icon(
        Icons.delete_outline,
        color: Colors.red.shade400,
        size: 28,
      ),
    );
  }
}

// Update the VariantSelectionModal clas
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
  final Map<int, String> _variantTypes = {};
  List<Map<String, dynamic>> deletedVariants = [];
  int?
      _currentlyInteractingId; // Track which variant is currently being interacted with

  @override
  void initState() {
    super.initState();
    selectedVariants = List.from(widget.initialSelection);
    for (var variant in selectedVariants) {
      _variantTypes[variant['id']] = variant['type'] ?? 'plus';
    }
    deletedVariants =
        selectedVariants.where((v) => v['type'] == 'minus').toList();
  }

  void _toggleVariant(Map<String, dynamic> variant) {
    final variantId = variant['id'];
    setState(() {
      if (selectedVariants.any((v) => v['id'] == variantId)) {
        final removedVariant =
            selectedVariants.firstWhere((v) => v['id'] == variantId);
        selectedVariants.removeWhere((v) => v['id'] == variantId);
        _variantTypes.remove(variantId);

        if (removedVariant['type'] == 'minus') {
          deletedVariants.removeWhere((v) => v['id'] == variantId);
        }
      } else {
        selectedVariants.add({...variant, 'type': 'plus'});
        _variantTypes[variantId] = 'plus';
      }
      _currentlyInteractingId = null; // Reset interaction tracking
    });
  }

  void _setVariantType(int variantId, String type) {
    if (!_variantTypes.containsKey(variantId)) return;

    setState(() {
      _variantTypes[variantId] = type;
      final index = selectedVariants.indexWhere((v) => v['id'] == variantId);
      if (index >= 0) {
        selectedVariants[index]['type'] = type;

        if (type == 'minus') {
          if (!deletedVariants.any((v) => v['id'] == variantId)) {
            deletedVariants.add(selectedVariants[index]);
          }
        } else {
          deletedVariants.removeWhere((v) => v['id'] == variantId);
        }
      }
      _currentlyInteractingId =
          variantId; // Track which variant was interacted with
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                final variantId = variant['id'];
                final isSelected =
                    selectedVariants.any((v) => v['id'] == variantId);
                final isDeleted =
                    deletedVariants.any((v) => v['id'] == variantId);
                final price =
                    double.tryParse(variant['prezzo'].toString()) ?? 0.0;
                final formattedPrice = price.toStringAsFixed(2);
                final variantType = _variantTypes[variantId] ?? 'plus';

                // Only show visual feedback for the currently interacting item
                final isInteracting = _currentlyInteractingId == variantId;

                Color tileColor = Colors.white;
                Color borderColor = Colors.grey[300]!;
                Color textColor = Colors.black;
                IconData icon = Icons.add;

                if (isSelected) {
                  if (variantType == 'plus') {
                    tileColor = isInteracting
                        ? Colors.green[100]!
                        : const Color(0xFFE8F5E9);
                    borderColor = Colors.green;
                    textColor = Colors.green;
                    icon = Icons.add;
                  } else {
                    tileColor = isInteracting
                        ? Colors.red[100]!
                        : const Color(0xFFFFEBEE);
                    borderColor = Colors.red;
                    textColor = Colors.red;
                    icon = Icons.remove;
                  }
                } else if (isInteracting) {
                  // Visual feedback for new selection
                  tileColor = variantType == 'plus'
                      ? Colors.green[100]!
                      : Colors.red[100]!;
                  borderColor =
                      variantType == 'plus' ? Colors.green : Colors.red;
                  textColor = variantType == 'plus' ? Colors.green : Colors.red;
                  icon = variantType == 'plus' ? Icons.add : Icons.remove;
                }

                return GestureDetector(
                  onTap: () => _toggleVariant(variant),
                  child: Dismissible(
                    key: ValueKey(variantId),
                    direction: DismissDirection.horizontal,
                    onUpdate: (details) {
                      // Update the interaction state during swipe
                      if (details.progress > 0) {
                        setState(() {
                          _currentlyInteractingId = variantId;
                        });
                      }
                    },
                    confirmDismiss: (direction) async {
                      if (!isSelected) {
                        _toggleVariant(variant);
                      }
                      if (direction == DismissDirection.startToEnd) {
                        _setVariantType(variantId, 'plus');
                      } else if (direction == DismissDirection.endToStart) {
                        _setVariantType(variantId, 'minus');
                      }
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 20),
                      color: Colors.green[100],
                      child: const Icon(Icons.add, color: Colors.green),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red[100],
                      child: const Icon(Icons.remove, color: Colors.red),
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: ListTile(
                        title: Text(
                          variant['des'],
                          style: TextStyle(
                            color: textColor,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            decoration:
                                isDeleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          variantType == 'plus'
                              ? '+$formattedPrice €'
                              : '-$formattedPrice €',
                          style: TextStyle(
                            color: textColor,
                            decoration:
                                isDeleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        trailing: isSelected
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    color: textColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.check_circle,
                                    color: textColor,
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
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
                  onPressed: () => Navigator.pop(context, selectedVariants),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEBE2B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'CONFERMA',
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
