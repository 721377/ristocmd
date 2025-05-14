import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/serverComun.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/offlinecomand.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:ristocmd/views/Tabledetails.dart';
import 'package:ristocmd/views/widgets/Sidemenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

final GlobalKey<HomePageState> homePageKey = GlobalKey<HomePageState>();

class HomePage extends StatefulWidget {
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const HomePage({Key? key, this.onUpdateTableStatus}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // Data variables
  List<Map<String, dynamic>> rooms = [];
  List<Map<String, dynamic>> tables = [];
  List<Map<String, dynamic>> categories = [];
  Map<int, int> tableClientCounts = {};
  List<Map<String, dynamic>> operators = [];
  // State variables
  int selectedRoomIndex = 0;
  bool _isOnline = false;
  bool _initialDataLoaded = false;
  bool _hasError = false;
  bool _showShimmer = true;
  bool _isChecking = false;

  // Controllers
  final PageController _roomPageController =
      PageController(viewportFraction: 0.8);

  // Services
  late TableLockManager tableLockManager;
  late IO.Socket socket;
  final connectionMonitor = WifiConnectionMonitor();

  @override
  void initState() {
    super.initState();
    _setSystemUIOverlayStyle();
    _initializeConnectionMonitoring();
    _startInitializationSequence();
    _checkConnectionStatus();
    _startShimmerTimer();
    _startStatusSyncTimer();
  }

  void _startShimmerTimer() {
    // Hide shimmer after max 3 seconds even if data isn't loaded
    Timer(const Duration(seconds: 3), () {
      if (mounted && _showShimmer) {
        setState(() => _showShimmer = false);
      }
    });
  }

  void _setSystemUIOverlayStyle() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color.fromARGB(255, 255, 255, 255),
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color.fromARGB(255, 255, 255, 255),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  void _initializeConnectionMonitoring() {
    connectionMonitor.addConnectionListener((isConnected) {
      if (mounted) {
        setState(() {
          _isOnline = isConnected;
          if (isConnected) {
            // Refresh data when connection is restored
            _loadInitialData();
          }
        });
      }
    });
    connectionMonitor.startMonitoring();
  }

  void _handleConnectionChange(bool isConnected) {
    if (mounted) {
      setState(() {
        _isOnline = isConnected;
        if (isConnected) {
          // Refresh data when connection is restored
          _loadInitialData();
          // Reinitialize socket if needed
          _initializeSocketManager();
        } else {
          // Handle offline scenario if needed
        }
      });
      print('Connection status changed: ${isConnected ? "Online" : "Offline"}');
    }
  }

  Future<void> _startInitializationSequence() async {
    try {
      // Start connection monitoring
      connectionMonitor.startMonitoring();

      // Load settings in parallel with other initialization
      await Future.wait([
        Settings.loadAllSettings(),
        _initializeEssentialServices(),
      ]);

      // Load initial data
      await _loadInitialData();
    } catch (e) {
      _handleInitializationError(e);
      // Retry after delay if failed
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _startInitializationSequence();
    }
  }

  Future<void> _initializeEssentialServices() async {
    // Initialize socket manager without waiting for completion
    unawaited(_initializeSocketManager());
    await _initializeTableLockService();
  }

  Future<void> _initializeSocketManager() async {
    try {
      await SocketManager().initialize(
        connectionMonitor: connectionMonitor,
        context: context,
        onStatusChanged: (isOnline) {
          if (mounted) {
            setState(() => _isOnline = isOnline);
             if (isOnline) _loadInitialData();
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _isOnline = false);
      AppLogger().log('Socket initialization failed', error: e.toString());
    }
  }

  Future<void> _initializeTableLockService() async {
    TableLockService().initialize(
      onTableOccupiedUpdated: (tableId, isOccupied) {
        if (mounted) {
          updateTableStatus(tableId, isOccupied ? 'occupied' : 'free');
        }
      },
      clientName: 'Mobile Client ${Random().nextInt(1000)}',
      dataRepository: DataRepository(),
      context: context,
      connectionMonitor: connectionMonitor,
    );
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      // First load rooms and tables (critical path)
      await _loadRoomsAndTables();

      // Mark initial load complete to remove shimmer
      if (mounted) {
        setState(() {
          _initialDataLoaded = true;
          _showShimmer = false;
        });
      }
      await _loadCategories();
      // Then load other data in background (non-critical)
      unawaited(_loadBackgroundData(_isOnline));
    } catch (e) {
      _handleDataLoadingError(e);
    }
  }

  Future<void> _loadRoomsAndTables() async {
    // Load rooms first
    final isOnline = await connectionMonitor.isConnectedToWifi();
    final loadedRooms = await DataRepository().getSalas(context, isOnline);

    if (!mounted) return;

    setState(() => rooms = loadedRooms);

    // Load tables for first room if available
    if (rooms.isNotEmpty) {
      await _loadTablesForRoom(rooms[selectedRoomIndex]['id']);
    }
  }

  Future<void> _loadTablesForRoom(int salaId) async {
    try {
      final isOnline = await connectionMonitor.isConnectedToWifi();
      final newTables =
          await DataRepository().getTavolos(context, salaId, isOnline);
      final filteredTables =
          newTables.where((table) => table['mod_banco'] != 1).toList();

      if (mounted) {
        setState(() => tables = filteredTables);
        // Load client counts in background without blocking UI
        unawaited(_loadClientCountsForTables(filteredTables));
      }
    } catch (e) {
      _handleTableLoadingError(e);
    }
  }

  Future<void> _loadClientCountsForTables(
      List<Map<String, dynamic>> tables) async {
    final isOnline = await connectionMonitor.isConnectedToWifi();
    final counts = <int, int>{};

    // Only load counts for tables with open bills
    final tablesWithOpenBills =
        tables.where((t) => t['conti_aperti'] > 0).toList();

    if (tablesWithOpenBills.isEmpty) return;

    await Future.wait(tablesWithOpenBills.map((table) async {
      try {
        final orders = await DataRepository().getOrdersForTable(
          context,
          table['id'],
          isOnline,
        );

        final copertoOrder = orders.firstWhere(
          (order) => order['mov_descr'] == 'COPERTO',
          orElse: () => {},
        );

        counts[table['id']] =
            copertoOrder.isNotEmpty ? copertoOrder['mov_qta'] ?? 1 : 1;
      } catch (e) {
        AppLogger().log('Error loading client count', error: e.toString());
      }
    }));

    if (mounted) setState(() => tableClientCounts = counts);
  }

  Future<void> _loadProducts(bool isOnline) async {
    try {
      List<Future> futures = [];

      for (var category in categories) {
        final categoryId = category['id'];
        if (categoryId != null) {
          futures.addAll([
            DataRepository().getArticoliByGruppo(context, categoryId, isOnline),
            DataRepository().getvariantiByGruppo(context, categoryId, isOnline),
          ]);
        }
      }

      // Wait for all to complete in parallel
      await Future.wait(futures);
    } catch (e) {
      print('Error loading products: $e');
    }
  }

Future<void> _loadBackgroundData(bool isOnline) async {
  try {
    await Future.wait([
      loadAndSaveImpostazioni(context, isOnline),
      _loadProducts(isOnline),
      loadoperatore(context, isOnline),
    ]);
  } catch (e) {
     AppLogger().log('Error in background loading: $e');
  }
}


  static Future<void> loadAndSaveImpostazioni(
      BuildContext context, isonline) async {
    try {
      final impostazioni =
          await DataRepository().getImpostazioniPalmari(context, isonline);
      final prefs = await SharedPreferences.getInstance();

      for (var setting in impostazioni) {
        for (var entry in setting.entries) {
          final key = entry.key;
          final value = entry.value;

          if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          }
        }
      }

      await Settings.loadAllSettings();
    } catch (e) {
      AppLogger().log('Failed to load/save settings', error: e.toString());
    }
  }

  Future<void> loadoperatore(BuildContext context, isonline) async {
    try {
      final loadedoperators =
          await DataRepository().getOperatore(context, isonline);
      if (mounted) setState(() => operators = loadedoperators);
    } catch (e) {
      _handleoperatoreLoadingError(e);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final isOnline = await connectionMonitor.isConnectedToWifi();
      final loadedCategories =
          await DataRepository().getGruppi(context, isOnline);

      if (mounted) setState(() => categories = loadedCategories);
    } catch (e) {
      _handleCategoryLoadingError(e);
    }
  }

  Future<void> updateTableStatus(String tableId, String status) async {
    if (!mounted) return;

    final DatabaseHelper dbHelper = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${tableId}_customers';
    final savedCount = prefs.getInt(key) ?? 0;

    setState(() {
      tables = tables.map((table) {
        if (table['id'].toString() == tableId) {
          return {
            ...table,
            'status': status,
            'conti_aperti': status == 'occupied' ? 1 : 0,
            'coperti': savedCount,
          };
        }
        return table;
      }).toList();
    });
    if (status == 'free') {
      final tableIdInt = int.tryParse(tableId) ?? 0;
      if (tableIdInt > 0) {
        await dbHelper.emptyOrdersForTable(tableIdInt);
      }
    }

    await prefs.setString(
        'last_status_$tableId', DateTime.now().toIso8601String());
  }

  // Add this new method to periodically check status
  void _startStatusSyncTimer() {
    Timer.periodic(Duration(seconds: 10), (_) async {
      if (!mounted || !_isOnline) return;

      try {
        // For each table, check if we need to verify status
        for (final table in tables) {
          final tableId = table['id'].toString();
          final prefs = await SharedPreferences.getInstance();
          final lastUpdate = prefs.getString('last_status_$tableId');

          if (lastUpdate == null ||
              DateTime.now().difference(DateTime.parse(lastUpdate)) >
                  Duration(minutes: 1)) {
            // Force status verification
            final isOnline = await connectionMonitor.isConnectedToWifi();
            final updatedTables = await DataRepository()
                .getTavolos(context, rooms[selectedRoomIndex]['id'], isOnline);

            if (mounted) {
              final updatedTable = updatedTables.firstWhere(
                (t) => t['id'].toString() == tableId,
                orElse: () => {},
              );

              if (updatedTable.isNotEmpty) {
                updateTableStatus(tableId,
                    updatedTable['conti_aperti'] > 0 ? 'occupied' : 'free');
              }
            }
          }
        }
      } catch (e) {
        AppLogger().log('Status sync error', error: e.toString());
      }
    });
  }

  void _handleInitializationError(dynamic error) {
    print('Initialization error: $error');
    Future.delayed(const Duration(seconds: 5), _startInitializationSequence);
    AppLogger().log('Initialization error:', error: error.toString());
  }

  void _handleDataLoadingError(dynamic error) {
    print('Data loading error: $error');
    AppLogger().log('Error loading data', error: error.toString());
  }

  void _handleTableLoadingError(dynamic error) {
    print('Table loading error: $error');
    AppLogger().log('Error loading tables', error: error.toString());
  }

  void _handleCategoryLoadingError(dynamic error) {
    print('Category loading error: $error');
    AppLogger().log(
      'Error loading categories',
      error: error.toString(),
    );
  }

  void _handleoperatoreLoadingError(dynamic error) {
    print('operators loading error: $error');
    AppLogger().log(
      'Error loading operators',
      error: error.toString(),
    );
  }

  Future<void> _onSalaChanged(int index) async {
    if (!mounted ||
        index == selectedRoomIndex ||
        index < 0 ||
        index >= rooms.length) return;
    setState(() => selectedRoomIndex = index);
    await _loadTablesForRoom(rooms[index]['id']);
    Settings.loadAllSettings();
  }

  Future<void> _checkConnectionStatus() async {
    setState(() {
      _isChecking = true;
    });

    final monitor = WifiConnectionMonitor();
    final isWifiConnected = await monitor.isConnectedToWifi();

    if (isWifiConnected) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 6);

        final request =
            await client.getUrl(Uri.parse('${Settings.baseUrl}/v1'));
        final response = await request.close();

        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);

        _isOnline = decoded['status'] == 'ok';
      } catch (_) {
        _isOnline = false;
      }
    } else {
      _isOnline = false;
    }

    setState(() {
      _isChecking = false;
    });
  }

  @override
  void dispose() {
    TableLockService().manager.dispose();
    SocketManager().closeConnection(); // Optional cleanup here too
    TableLockService().dispose();
    _roomPageController.dispose();
    connectionMonitor.stopMonitoring();
    connectionMonitor.removeConnectionListener(_handleConnectionChange);
    super.dispose();
  }

  Widget _buildRoomShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Row(
        children: List.generate(
          3,
          (index) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTablesShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChevronButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: Colors.grey[700]),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final Color backgroundColor = _isChecking
        ? Colors.grey[200]!
        : _isOnline
            ? const Color(0xFFE6F4EA)
            : const Color(0xFFFFEBEE);

    final Color borderColor = _isChecking
        ? Colors.grey
        : _isOnline
            ? const Color(0xFF28A745)
            : const Color(0xFFF44336);

    final Color textColor = _isChecking
        ? Colors.black54
        : _isOnline
            ? const Color(0xFF28A745)
            : const Color(0xFFF44336);

    final IconData icon = _isChecking
        ? Icons.sync
        : _isOnline
            ? Icons.wifi
            : Icons.wifi_off;

    return GestureDetector(
      onTap: _checkConnectionStatus,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 6),
            Text(
              _isChecking ? 'Checking...' : (_isOnline ? 'Online' : 'Offline'),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: ModernDrawer(operators: operators),
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: RefreshIndicator(
        onRefresh: _startInitializationSequence,
        child: Column(
          children: [
            const ModernAppBar(),
            const SizedBox(height: 34),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Seleziona sala',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  _buildConnectionStatus(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 70,
              child: _showShimmer || !_initialDataLoaded
                  ? _buildRoomShimmer()
                  : rooms.isEmpty
                      ? const Center(child: Text("Nessuna sala disponibile"))
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            PageView.builder(
                              controller: _roomPageController,
                              itemCount: rooms.length,
                              onPageChanged: (index) => _onSalaChanged(index),
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selectedRoomIndex == index
                                          ? const Color.fromARGB(
                                              255, 255, 198, 65)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: selectedRoomIndex == index
                                            ? const Color.fromARGB(
                                                255, 231, 231, 231)
                                            : Colors.grey[300]!,
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      rooms[index]['des'] as String,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: selectedRoomIndex == index
                                            ? const Color.fromARGB(
                                                255, 255, 255, 255)
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (rooms.length > 1)
                              Positioned(
                                left: 4,
                                child:
                                    _buildChevronButton(Icons.chevron_left, () {
                                  if (selectedRoomIndex > 0) {
                                    _roomPageController.previousPage(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                }),
                              ),
                            if (rooms.length > 1)
                              Positioned(
                                right: 4,
                                child: _buildChevronButton(Icons.chevron_right,
                                    () {
                                  if (selectedRoomIndex < rooms.length - 1) {
                                    _roomPageController.nextPage(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                }),
                              ),
                          ],
                        ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tavoli',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _showShimmer || !_initialDataLoaded
                    ? _buildTablesShimmer()
                    : tables.isEmpty
                        ? Center(
                            child: Text(
                              "Nessun tavolo disponibile in questa sala",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: tables.length,
                            itemBuilder: (context, index) {
                              final table = tables[index];
                              return TableWidget(
                                table: table,
                                categories: categories,
                                clientCount:
                                    tableClientCounts[table['id']] ?? 0,
                                online: _isOnline,
                                onUpdateTableStatus: (tableId, status) {
                                  updateTableStatus(tableId, status);
                                },
                              );
                            },
                          ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class TableWidget extends StatefulWidget {
  final Map<String, dynamic> table;
  final List<Map<String, dynamic>> categories;
  final int clientCount;
  final bool online;
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const TableWidget({
    Key? key,
    required this.table,
    required this.categories,
    required this.clientCount,
    required this.online,
    this.onUpdateTableStatus,
  }) : super(key: key);

  @override
  State<TableWidget> createState() => _TableWidgetState();
}

class _TableWidgetState extends State<TableWidget> {
  bool _isNavigating = false;
  DateTime? _lastTapTime;

  Future<bool> _hasOfflinePendingOrder(String tableId) async {
    final offlineCommands = await OfflineCommandStorage().getPendingCommands();
    return offlineCommands
        .any((cmd) => cmd['tavolo'].toString() == tableId.toString());
  }

Future<void> _navigateToTableDetails() async {
  final now = DateTime.now();
  if (_lastTapTime != null && now.difference(_lastTapTime!) < Duration(seconds: 1)) {
    return;
  }
  _lastTapTime = now;

  
  setState(() => _isNavigating = true);

  try {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TableDetailsPage(
          table: widget.table,
          categories: widget.categories,
          onUpdateTableStatus: widget.onUpdateTableStatus,
          isonline: widget.online,
        ),
      ),
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore nel caricamento dei dettagli del tavolo'),
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _isNavigating = false);
  }
}


  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasOfflinePendingOrder(widget.table['id'].toString()),
      builder: (context, snapshot) {
        final hasOfflineOrder = snapshot.data == true;

        final status = widget.table['status'] ??
            (widget.online
                ? (widget.table['conti_aperti'] > 0 ? 'occupied' : 'free')
                : (hasOfflineOrder
                    ? 'pending'
                    : (widget.table['is_occupied'] == 1
                        ? 'occupied'
                        : (widget.table['is_pending'] == 1
                            ? 'pending'
                            : 'free'))));

        final isOccupied = status == 'occupied';
        final isPending = status == 'pending';
        final hasitem = status == 'hasitems';
        final hasClients = isOccupied;
        final numClientUpdated = widget.table['coperti'];

        final Color backgroundColor;
        final Color borderColor;
        final Color textColor = Colors.grey[800]!;

        if (isPending) {
          backgroundColor = const Color(0xFFFFF3E0);
          borderColor = const Color(0xFFFFA000);
        } else if (isOccupied) {
          backgroundColor = const Color(0xFFE6F4EA);
          borderColor = const Color(0xFF28A745);
        } else if (hasitem) {
          backgroundColor = const Color(0xFFF0F0F0);
          borderColor = const Color(0xFF6C757D);
        } else {
          backgroundColor = Colors.white;
          borderColor = Colors.grey[300]!;
        }

        return AbsorbPointer(
          absorbing: _isNavigating,
          child: GestureDetector(
            onTap: _navigateToTableDetails,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: borderColor,
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromARGB(13, 0, 0, 0),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.table['des'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        if (isPending)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFA000),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'In attesa',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasClients)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.grey[700]),
                          const SizedBox(width: 4),
                          Text(
                            (numClientUpdated > widget.clientCount)
                                ? numClientUpdated.toString()
                                : widget.clientCount.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
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
}

class ModernAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int notificationCount; // To represent the number of notifications

  const ModernAppBar({Key? key, this.notificationCount = 0}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 90);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        bottom: 40,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 198, 65),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(48),
          bottomRight: Radius.circular(48),
        ),
        border: Border.all(
            color: const Color.fromARGB(255, 218, 218, 218), width: 1.1),
        boxShadow: [
          const BoxShadow(
            color: Color.fromARGB(18, 0, 0, 0),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.sort,
                    color: Color.fromARGB(255, 255, 255, 255), size: 30),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
              ),
              const Text(
                "RISTOCOMANDE",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 255, 255, 255),
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications,
                      color: Color.fromARGB(255, 255, 255, 255),
                      size: 30,
                    ),
                    onPressed: () {
                      // Handle notification icon press
                    },
                  ),
                  if (notificationCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$notificationCount',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
