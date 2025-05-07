import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/views/Categorie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ristocmd/services/offlinecomand.dart';

class TableDetailsPage extends StatefulWidget {
  final Map<String, dynamic> table;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> categories;
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const TableDetailsPage({
    Key? key,
    required this.table,
    required this.orders,
    required this.categories,
    required this.onUpdateTableStatus,
  }) : super(key: key);

  @override
  _TableDetailsPageState createState() => _TableDetailsPageState();
}

class _TableDetailsPageState extends State<TableDetailsPage> {
  int _copertiCount = 0;
  bool _isLoading = true;
  bool _shouldAutoOpenModal = false;
  List<Map<String, dynamic>> _offlineOrders = [];
  List<Map<String, dynamic>> _localOrders = [];
  List<Map<String, dynamic>> _localOfflineOrders = [];
  final OfflineCommandStorage _offlineStorage = OfflineCommandStorage();
  bool _showOnline = true;
  bool _showOffline = true;
  int _onlineCardCount = 0;
  int _offlineCardCount = 0;
  String _timeFilter = 'all';
  bool _hasonlineOrder = false; // 'all', 'today', 'last_hour'

  @override
  void initState() {
    super.initState();
    _loadData();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
          statusBarColor: Color.fromARGB(255, 255, 255, 255),
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Color.fromARGB(255, 255, 255, 255),
          systemNavigationBarIconBrightness: Brightness.dark),
    );
  }

  Future<void> _loadData() async {
    await _loadCustomerCount();
    await _loadOfflineOrders();
    await _loadLocalOrders();
    _checkAutoOpenModal();
  }

  Future<void> _loadCustomerCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.table['id']}_customers';
    final savedCount = (_hasonlineOrder)?prefs.getInt(key):0;

    // Find COPERTO order if exists
    final copertiOrder = widget.orders.firstWhere(
      (order) => order['mov_descr'] == 'COPERTO',
      orElse: () => {},
    );

    setState(() {
      _copertiCount =
          copertiOrder.isNotEmpty ? copertiOrder['mov_qta'] : savedCount;
    });
  }

  Future<void> _loadOfflineOrders() async {
    final offlineCommands = await _offlineStorage.getPendingCommands();
    final tableOfflineOrders = offlineCommands
        .where((cmd) => cmd['tavolo'] == widget.table['id'].toString())
        .toList();

    final List<Map<String, dynamic>> offlineOrders = [];
    for (final cmd in tableOfflineOrders) {
      if (cmd['comanda'] is List) {
        for (final order in cmd['comanda'] as List) {
          final orderMap = Map<String, dynamic>.from(order);
          // Ensure each offline order has a timer_start
          if (orderMap['timer_start'] == null) {
            orderMap['timer_start'] =
                cmd['timer_start'] ?? DateTime.now().toIso8601String();
          }
          offlineOrders.add(orderMap);
        }
      }
    }

    setState(() {
      _offlineOrders = offlineOrders;
    });
  }

  Future<void> _loadLocalOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final localOrdersKey = 'local_orders_${widget.table['id']}';
    final localOfflineKey = 'local_offline_${widget.table['id']}';

    final localOrders = prefs.getStringList(localOrdersKey) ?? [];
    final localOffline = prefs.getStringList(localOfflineKey) ?? [];

    setState(() {
      _localOrders = localOrders.map((e) {
        final map = Map<String, dynamic>.from(json.decode(e));
        // Ensure each order has a timer_start and card_id
        map['timer_start'] =
            map['timer_start'] ?? DateTime.now().toIso8601String();
        map['card_id'] = map['card_id'] ??
            _generateCardId(DateTime.parse(map['timer_start']));
        return map;
      }).toList();

      _localOfflineOrders = localOffline.map((e) {
        final map = Map<String, dynamic>.from(json.decode(e));
        // Ensure each offline order has a timer_start and card_id
        map['timer_start'] =
            map['timer_start'] ?? DateTime.now().toIso8601String();
        map['card_id'] = map['card_id'] ??
            _generateCardId(DateTime.parse(map['timer_start']));
        return map;
      }).toList();

      _isLoading = false;
    });
  }

  String _generateCardId(DateTime timer_start) {
    // Group orders within 1 minute window into same card
    final roundedTime = DateTime(
      timer_start.year,
      timer_start.month,
      timer_start.day,
      timer_start.hour,
      timer_start.minute,
    );
    return roundedTime.millisecondsSinceEpoch.toString();
  }

  Future<void> _saveLocalOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final localOrdersKey = 'local_orders_${widget.table['id']}';
    final localOfflineKey = 'local_offline_${widget.table['id']}';

    // Process online orders
    final onlineOrdersToSave =
        widget.orders.where((o) => o['mov_descr'] != 'COPERTO').map((e) {
      final order = Map<String, dynamic>.from(e);
      // Ensure timer_start exists
      order['timer_start'] =
          order['timer_start'] ?? DateTime.now().toIso8601String();
      // Generate consistent card_id based on timer_start
      order['card_id'] = order['card_id'] ??
          _generateCardId(DateTime.parse(order['timer_start']));
      return json.encode(order);
    }).toList();

    // Process offline orders
    final offlineOrdersToSave = _offlineOrders.map((e) {
      final order = Map<String, dynamic>.from(e);
      // Ensure timer_start exists
      order['timer_start'] =
          order['timer_start'] ?? DateTime.now().toIso8601String();
      // Generate consistent card_id based on timer_start
      order['card_id'] = order['card_id'] ??
          _generateCardId(DateTime.parse(order['timer_start']));
      return json.encode(order);
    }).toList();

    await prefs.setStringList(localOrdersKey, onlineOrdersToSave);
    await prefs.setStringList(localOfflineKey, offlineOrdersToSave);
  }

  Future<void> _saveCustomerCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.table['id']}_customers';
    await prefs.setInt(key, count);

    // Update the parent widget's client count if it exists
    if (widget.onUpdateTableStatus != null) {
      widget.onUpdateTableStatus!(
        widget.table['id'].toString(),
        count > 0 || !_hasonlineOrder ? 'hasitems': _hasonlineOrder ? 'occupied' : 'free',
      );
    }

    setState(() {
      _copertiCount = count;
    });

    if (_shouldAutoOpenModal) {
      _shouldAutoOpenModal = false;
      _navigateToCategories();
    }
  }

  void _checkAutoOpenModal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasonlineOrder = widget.orders.any((o) => o['mov_descr'] != 'COPERTO');
      final hasOfflineOrders = _offlineOrders.isNotEmpty;

      if (!_hasonlineOrder && !hasOfflineOrders) {
        if (Settings.copertoPalm == 1 || widget.table['coperti'] == 1) {
          setState(() => _shouldAutoOpenModal = true);
          _showCustomerCountModal();
        } else {
          _navigateToCategories();
        }
      }
    });
  }

  void _navigateToCategories() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CategoriesPage(
          categories: widget.categories,
          tavolo: widget.table,
          onUpdateTableStatus: widget.onUpdateTableStatus,
        ),
      ),
    );
  }

  void _showCustomerCountModal() {
    int tempCount = _copertiCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Numero di clienti',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  /// Counter UI
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hide minus if count is 0
                      if (tempCount > 0)
                        InkWell(
                          onTap: (tempCount > 0 && !_hasonlineOrder)
                              ? () {
                                  setState(() => tempCount--);
                                }
                              : null, // disables the button
                          borderRadius: BorderRadius.circular(40),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (tempCount > 0 && !_hasonlineOrder)
                                  ? Colors.grey[100]
                                  : Colors.grey[300], // dimmed if disabled
                            ),
                            child: Icon(
                              Icons.remove,
                              size: 28,
                              color: (tempCount > 0 && !_hasonlineOrder)
                                  ? Colors.black
                                  : Colors.grey[500], // gray out if disabled
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 80), // Keeps layout aligned

                      const SizedBox(width: 20),

                      // Display count
                      Container(
                        width: 80,
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          '$tempCount',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      // Plus button
                      InkWell(
                        onTap: () {
                          if (tempCount < 99) {
                            setState(() => tempCount++);
                          }
                        },
                        borderRadius: BorderRadius.circular(40),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFEBE2B),
                          ),
                          child: const Icon(Icons.add,
                              size: 28, color: Colors.black),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Action buttons
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
                            side: const BorderSide(color: Colors.black12),
                          ),
                          child: const Text(
                            'Annulla',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color.fromARGB(189, 0, 0, 0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
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
                            backgroundColor: const Color(0xFFFEBE2B),
                            foregroundColor: const Color.fromARGB(255, 255, 255, 255),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Conferma',
                            style: TextStyle(
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

  //filtersw widget
  Widget buildFilterSelector() {
    String _selected = _timeFilter == 'all'
        ? (_showOnline && !_showOffline
            ? 'online'
            : !_showOnline && _showOffline
                ? 'offline'
                : 'Tutti')
        : 'Tutti';

    final List<String> filters = ['online', 'offline', 'Tutti'];
    final Map<String, String> labels = {
      'online': 'Online ($_onlineCardCount)',
      'offline': 'Offline ($_offlineCardCount)',
      'Tutti': 'Tutti',
    };

    return Container(
      margin: EdgeInsets.symmetric(
          horizontal: 24, vertical: 12), // Reduced vertical margin
      padding: EdgeInsets.all(10), // Reduced padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Slightly reduced radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8, // Slightly reduced blur radius
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filtri',
            style: TextStyle(
              fontSize: 14, // Reduced text size
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          SizedBox(height: 12), // Reduced space between title and buttons
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 6.0; // Reduced spacing
              double totalSpacing = spacing * (filters.length - 1);
              double itemWidth =
                  (constraints.maxWidth - totalSpacing) / filters.length;
              int selectedIndex = filters.indexOf(_selected);

              return SizedBox(
                height: 36, // Reduced height of the selector area
                child: Stack(
                  children: [
                    // Sliding background
                    AnimatedPositioned(
                      duration: Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      left: selectedIndex * (itemWidth + spacing),
                      top: 0,
                      child: Container(
                        width: itemWidth,
                        height: 36, // Reduced height of the background
                        decoration: BoxDecoration(
                          color: Color(0xFFFEBE2B),
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                    ),
                    Row(
                      children: filters.map((filter) {
                        bool isSelected = _selected == filter;

                        return Padding(
                          padding: EdgeInsets.only(
                            right: filter != filters.last ? spacing : 0,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (filter == 'online') {
                                  _showOnline = true;
                                  _showOffline = false;
                                  _timeFilter = 'all';
                                } else if (filter == 'offline') {
                                  _showOnline = false;
                                  _showOffline = true;
                                  _timeFilter = 'all';
                                } else if (filter == 'Tutti') {
                                  _showOnline = true;
                                  _showOffline = true;
                                  _timeFilter = 'all';
                                }
                              });
                            },
                            child: Container(
                              width: itemWidth,
                              height:
                                  36, // Reduced height of each filter option
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? Color(0xFFFEBE2B)
                                      : Color(0xFF1A1A1A),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(50),
                                color: Colors.transparent,
                              ),
                              child: Text(
                                labels[filter]!,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize:
                                        12, // Reduced font size for each label
                                    color: isSelected
                                        ? Color.fromARGB(255, 255, 255, 255)
                                        : Color(0xFF1A1A1A)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isTableOccupied = _copertiCount > 0 ||
        widget.orders.any((order) => order['mov_descr'] != 'COPERTO') ||
        _offlineOrders.isNotEmpty;
    final now = DateTime.now();

    // Filter out 'COPERTO' orders and ensure all orders have a valid timer_start
    final displayOnlineOrders = widget.orders
        .where((order) => order['mov_descr'] != 'COPERTO')
        .map((order) {
      final o = Map<String, dynamic>.from(order);
      o['timer_start'] = o['timer_start'] ?? DateTime.now().toIso8601String();
      return o;
    }).toList();

    final displayOfflineOrders = _offlineOrders.map((order) {
      final o = Map<String, dynamic>.from(order);
      o['timer_start'] = o['timer_start'] ?? DateTime.now().toIso8601String();
      return o;
    }).toList();

    // Apply time filter to both online and offline orders
    final filteredOnlineOrders = _applyTimeFilter(displayOnlineOrders);
    final filteredOfflineOrders = _applyTimeFilter(displayOfflineOrders);

    // Group orders by their timer_start (orders within 1 minute get the same card)
    final onlineOrderGroups = _groupOrdersByTimerStart(filteredOnlineOrders);
    final offlineOrderGroups = _groupOrdersByTimerStart(filteredOfflineOrders);

    // Compare with local storage
    final newOnlineCards = _getNewOrderCards(onlineOrderGroups, _localOrders);
    final existingOnlineCards =
        _getExistingOrderCards(onlineOrderGroups, _localOrders);
    final newOfflineCards =
        _getNewOrderCards(offlineOrderGroups, _localOfflineOrders);
    final existingOfflineCards =
        _getExistingOrderCards(offlineOrderGroups, _localOfflineOrders);

    // Update card counters
    _onlineCardCount = (newOnlineCards.length + existingOnlineCards.length);
    _offlineCardCount = (newOfflineCards.length + existingOfflineCards.length);

    // Calculate totals
    final onlineTotal = _calculateTotal(filteredOnlineOrders);
    final offlineTotal = _calculateTotal(filteredOfflineOrders);
    final total = onlineTotal + offlineTotal;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SafeArea(
            top: true,
            bottom: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(26),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Back Button
                      Container(
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 22,
                            color: Colors.black,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),

                      // Table Description & Time
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tavolo ${widget.table['des']}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_formatDate(now)} - ${_formatTime(now)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Total
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '€${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      // Coperti Count
                      if (Settings.copertoPalm != 0)
                        GestureDetector(
                          onTap: _showCustomerCountModal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person,
                                    size: 16, color: Colors.black),
                                const SizedBox(width: 4),
                                Text(
                                  _copertiCount > 0 ? '$_copertiCount' : '0',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Time Filter and Type Filter
          Column(
            children: [
              buildFilterSelector(),
            ],
          ),

          // Orders list
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_showOnline || _showOffline)
                        _buildOrderSummarySection(
                          newOnlineCards: _showOnline ? newOnlineCards : [],
                          existingOnlineCards:
                              _showOnline ? existingOnlineCards : [],
                          newOfflineCards: _showOffline ? newOfflineCards : [],
                          existingOfflineCards:
                              _showOffline ? existingOfflineCards : [],
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(26),
              topRight: Radius.circular(26),
            ),
            color: const Color.fromARGB(255, 255, 255, 255),
            border: Border.all(
              color: const Color.fromARGB(255, 232, 232, 232),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                spreadRadius: 0,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                _saveLocalOrders();
                _navigateToCategories();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEBE2B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: Text(
                isTableOccupied ? "Aggiungi ordine" : "Crea ordine",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color.fromARGB(255, 255, 255, 255),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupOrdersByTimerStart(
      List<Map<String, dynamic>> orders) {
    final groups = <String, List<Map<String, dynamic>>>{};

    for (final order in orders) {
      final timerStart = DateTime.parse(order['timer_start']);
      // Generate card_id based on rounded timer_start (per minute)
      final cardId = _generateCardId(timerStart);

      if (!groups.containsKey(cardId)) {
        groups[cardId] = [];
      }
      groups[cardId]!.add(order);
    }

    // Sort each group by exact timer_start (newest first)
    groups.forEach((key, value) {
      value.sort((a, b) {
        final timeA = DateTime.parse(a['timer_start']);
        final timeB = DateTime.parse(b['timer_start']);
        return timeB.compareTo(timeA);
      });
    });

    return groups;
  }

  List<Map<String, dynamic>> _applyTimeFilter(
      List<Map<String, dynamic>> orders) {
    final now = DateTime.now();

    return orders.where((order) {
      final orderTime = DateTime.parse(order['timer_start'] ?? now.toString());

      switch (_timeFilter) {
        case 'today':
          return orderTime.day == now.day &&
              orderTime.month == now.month &&
              orderTime.year == now.year;
        case 'last_hour':
          return now.difference(orderTime).inHours < 1;
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  List<List<Map<String, dynamic>>> _getNewOrderCards(
      Map<String, List<Map<String, dynamic>>> currentGroups,
      List<Map<String, dynamic>> savedOrders) {
    final savedCardIds = savedOrders.map((o) => o['timer_start']).toSet();
    return currentGroups.entries
        .where((entry) => !savedCardIds.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
  }

  List<List<Map<String, dynamic>>> _getExistingOrderCards(
      Map<String, List<Map<String, dynamic>>> currentGroups,
      List<Map<String, dynamic>> savedOrders) {
    final savedCardIds = savedOrders.map((o) => o['timer_start']).toSet();
    return currentGroups.entries
        .where((entry) => savedCardIds.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
  }

  Widget _buildOrderSummarySection({
    required List<List<Map<String, dynamic>>> newOnlineCards,
    required List<List<Map<String, dynamic>>> existingOnlineCards,
    required List<List<Map<String, dynamic>>> newOfflineCards,
    required List<List<Map<String, dynamic>>> existingOfflineCards,
  }) {
    final hasNewOnline = newOnlineCards.isNotEmpty;
    final hasExistingOnline = existingOnlineCards.isNotEmpty;
    final hasNewOffline = newOfflineCards.isNotEmpty;
    final hasExistingOffline = existingOfflineCards.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Ordini attivi",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),

        // New online orders
        if (hasNewOnline) ...[
          for (final cardOrders in newOnlineCards)
            _buildCompleteOrderCard(
              title: "ordine online",
              orders: cardOrders,
              isOffline: false,
              isNew: true,
              color: const Color(0xFF28A745),
              bgcolor: Color(0xFFE6F4EA),
            ),
          if (hasNewOnline) const SizedBox(height: 16),
        ],

        // Existing online orders
        // if (hasExistingOnline) ...[
        //   for (final cardOrders in existingOnlineCards)
        //     _buildCompleteOrderCard(
        //       title: "Ordine online",
        //       orders: cardOrders,
        //       isOffline: false,
        //       isNew: false,
        //       color: const Color(0xFF28A745),
        //       bgcolor: Color(0xFFE6F4EA),
        //     ),
        //   if (hasExistingOnline) const SizedBox(height: 16),
        // ],

        // New offline orders
        if (hasNewOffline) ...[
          for (final cardOrders in newOfflineCards)
            _buildCompleteOrderCard(
              title: "Nuovo ordine offline",
              orders: cardOrders,
              isOffline: true,
              isNew: true,
              color: const Color(0xFFFEBE2B),
              bgcolor: Color(0xFFFFF3E0),
            ),
          if (hasNewOffline) const SizedBox(height: 16),
        ],

        // Existing offline orders
        if (hasExistingOffline) ...[
          for (final cardOrders in existingOfflineCards)
            _buildCompleteOrderCard(
              title: "Ordine offline",
              orders: cardOrders,
              isOffline: true,
              isNew: false,
              color: const Color(0xFFFEBE2B),
              bgcolor: Color(0xFFFFF3E0),
            ),
        ],

        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCompleteOrderCard({
    required String title,
    required List<Map<String, dynamic>> orders,
    required bool isOffline,
    required bool isNew,
    required Color color,
    required Color bgcolor,
  }) {
    // Sort orders by 'timer_start' in descending order (newest first)
    orders.sort((a, b) {
      final timeA = DateTime.parse(a['timer_start']);
      final timeB = DateTime.parse(b['timer_start']);
      return timeB.compareTo(timeA); // Newest first
    });

    // Get the time for the first order (newest)
    final orderTime = orders.isNotEmpty
        ? DateTime.parse(orders.first['timer_start'])
        : DateTime.now();

    // Calculate total price including variants
    final orderTotal = orders.fold(0.0, (sum, order) {
      final basePrice = order['mov_prz'] * order['mov_qta'];
      final variantPrice = (order['variantiPrz'] ?? 0.0) * order['mov_qta'];
      return sum + basePrice + variantPrice;
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgcolor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isOffline ? Icons.sync_disabled : Icons.check_circle,
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                    if (isNew)
                      // Container(
                      //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      //   decoration: BoxDecoration(
                      //     color: const Color.fromARGB(255, 255, 255, 255),
                      //     borderRadius: BorderRadius.circular(10),
                      //   ),
                      //   // child: const Text(
                      //   //   'NUOVO',
                      //   //   style: TextStyle(
                      //   //     fontSize: 10,
                      //   //     fontWeight: FontWeight.bold,
                      //   //     color: Color.fromARGB(255, 21, 21, 21),
                      //   //   ),
                      //   // ),
                      // ),
                      const SizedBox(width: 8),
                    Text(
                      "€${orderTotal.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(orderTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          ...orders.map((order) => _buildOrderItemRow(
                order,
                color,
                DateTime.parse(order['timer_start']),
              )),
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(
      Map<String, dynamic> order, Color color, DateTime orderTime) {
    final itemName = order['mov_descr'];
    final quantity = order['mov_qta'];
    final basePrice = order['mov_prz'].toDouble();
    final variantPrice = (order['variantiPrz'] ?? 0.0).toDouble();
    final variantDescription = order['variantiDes']?.toString();
    final hasVariant =
        variantDescription != null && variantDescription.isNotEmpty;
    final totalPrice = (basePrice + variantPrice) * quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (hasVariant)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(238, 255, 255, 255),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            variantDescription,
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color.fromARGB(255, 59, 59, 59),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      "$quantity x €${(basePrice + variantPrice).toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "€${totalPrice.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatExactTime(orderTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

// Helper to format time with seconds
  String _formatExactTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dateTime) {
    return 'Oggi alle ${_formatTime(dateTime)}';
  }

  double _calculateTotal(List<Map<String, dynamic>> orders) {
    return orders.fold(0.0, (sum, order) {
      final basePrice = order['mov_prz'] * order['mov_qta'];
      final variantPrice = (order['variantiPrz'] ?? 0.0) * order['mov_qta'];
      return sum + basePrice + variantPrice;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
