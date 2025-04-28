import 'package:flutter/material.dart';
import 'package:ristocmd/views/Categorie.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TableDetailsPage extends StatefulWidget {
  final Map<String, dynamic> table;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> categories;

  const TableDetailsPage({
    Key? key,
    required this.table,
    required this.orders,
    required this.categories,
  }) : super(key: key);

  @override
  _TableDetailsPageState createState() => _TableDetailsPageState();
}

class _TableDetailsPageState extends State<TableDetailsPage> {
  int _copertiCount = 0;
  bool _isLoading = true;
  bool _shouldAutoOpenModal = false;

  @override
  void initState() {
    super.initState();
    _loadCustomerCount();
    _checkAutoOpenModal();
  }

Future<void> _loadCustomerCount() async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'table_${widget.table['id']}_customers';
  final savedCount = prefs.getInt(key) ?? 0;

  final copertiOrder = widget.orders.firstWhere(
    (order) => order['mov_descr'] == 'COPERTO',
    orElse: () => {},
  );

  setState(() {
    _copertiCount = copertiOrder.isNotEmpty ? copertiOrder['mov_qta'] : savedCount;
    _isLoading = false;
  });
}

Future<void> _saveCustomerCount(int count) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'table_${widget.table['id']}_customers';
  await prefs.setInt(key, count);
  setState(() {
    _copertiCount = count;
  });

  // If modal was opened automatically, navigate after saving
  if (_shouldAutoOpenModal) {
    _shouldAutoOpenModal = false;
    _navigateToCategories();
  }
}

void _checkAutoOpenModal() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Check if orders list is empty instead of copertiCount
    if (widget.orders.isEmpty) {
      if (widget.table['coperti'] == 1) {
        setState(() {
          _shouldAutoOpenModal = true;
        });
        _showCustomerCountModal();
      } else if (widget.table['coperti'] == 0) {
        _navigateToCategories();
      }
    }
  });
}


  void _navigateToCategories() {
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CategoriesPage(categories: widget.categories,tavolo: widget.table),
      ),
    );
  }

void _showCustomerCountModal() {
  int tempCount = _copertiCount;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ), // <-- This parenthesis was missing
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Numero di clienti',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.remove_circle_outline, size: 30),
                      onPressed: () {
                        if (tempCount > 0) {
                          setState(() => tempCount--);
                        }
                      },
                    ),
                    Container(
                      width: 60,
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black.withOpacity(0.1)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tempCount.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline, size: 30),
                      onPressed: () {
                        if (tempCount < 99) {
                          setState(() => tempCount++);
                        }
                      },
                    ),
                  ],
                ),
                SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.black.withOpacity(0.1)),
                          ),
                        ),
                        child: Text(
                          'Annulla',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _saveCustomerCount(tempCount);
                          Navigator.pop(context);
                          if (!_shouldAutoOpenModal) {
                            _navigateToCategories();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFEBE2B),
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Conferma',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
              ],
            ),
          );
        },
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isTableOccupied = _copertiCount > 0 || 
      widget.orders.any((order) => order['mov_descr'] != 'COPERTO');
    final now = DateTime.now();
    final total = _calculateTotal(widget.orders.where((order) => 
      order['mov_descr'] != 'COPERTO').toList());
    final hasOrders = widget.orders.any((order) => order['mov_descr'] != 'COPERTO');

    // If no orders and not occupied, show empty state (will be redirected automatically)
    if (!hasOrders && !isTableOccupied) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(), // This will be very brief as redirect happens quickly
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            backgroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              titlePadding: EdgeInsets.only(bottom: 16),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tavolo ${widget.table['des']}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  
                  SizedBox(width: 8),
                 if (widget.table['coperti'] != 0)
                  Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person, size: 18, color: Colors.black),
                        SizedBox(width: 4),
                        GestureDetector(
                          onTap: _showCustomerCountModal,
                          child: Text(
                            _copertiCount > 0 ? '$_copertiCount' : '0',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pinned: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (isTableOccupied) ...[
                  Text(
                    '${_formatDate(now)} - ${_formatTime(now)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                  SizedBox(height: 24),
                  if (hasOrders) _buildOrderSummaryCard(widget.orders, total),
                ],
                SizedBox(height: isTableOccupied ? 24 : 0),
                _buildActionButton(context, isTableOccupied),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTotal(List<Map<String, dynamic>> orders) {
    return orders.fold(0.0, (sum, order) {
      return sum + (order['mov_prz'] * order['mov_qta']);
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildOrderSummaryCard(List<Map<String, dynamic>> orders, double total) {
    final displayOrders = orders.where((order) => order['mov_descr'] != 'COPERTO').toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(19, 20, 20, 20),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
          BoxShadow(
            color: const Color.fromARGB(15, 0, 0, 0),
            blurRadius: 3,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Riepilogo ordine",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 16),
          ...displayOrders.map((order) => _buildOrderItem(
            order['mov_descr'],
            order['mov_qta'],
            order['mov_prz'].toDouble()
          )).toList(),
          Divider(height: 32, color: Colors.black.withOpacity(0.1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Totale",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "€${total.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFEBE2B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, bool isOccupied) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          _navigateToCategories();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFFFEBE2B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Text(
          isOccupied ? "Aggiungi ordine" : "Crea ordine",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderItem(String name, int quantity, double price) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$quantity x $name",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "€${(quantity * price).toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}