import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/serverComun.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:ristocmd/views/Tabledetails.dart';
import './widgets/Appbar.dart';
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
  List<Map<String, dynamic>> rooms = [];
  int selectedRoomIndex = 0;
  final PageController _roomPageController = PageController(
    viewportFraction: 0.8,
  );

  List<Map<String, dynamic>> tables = [];
  bool isLoadingRooms = true;
  bool isLoadingTables = false;
  late TableLockManager tableLockManager;
  late IO.Socket socket;
  bool _isOnline = true;
  final connectionMonitor = WifiConnectionMonitor();
  List<Map<String, dynamic>> categories = [];
  bool isLoadingCategories = false;

  // Map to store client counts for each table
  Map<int, int> tableClientCounts = {};

  @override
  void initState() {
    super.initState();

    // 1. First set the system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // 2. Initialize the connection monitor
    connectionMonitor.startMonitoring();

    // 3. Initialize SocketManager first (needed for TableLockManager)
    _initializeSocketAndServices();
  }

  Future<void> _initializeSocketAndServices() async {
    try {
      // Initialize SocketManager
      await SocketManager().initialize(
        connectionMonitor: connectionMonitor,
        context: context,
        onStatusChanged: (isOnline) {
          if (mounted) {
            setState(() {
              _isOnline = isOnline;
              if (isOnline) {
                // Load data when coming online
                loadInitialData();
                _loadCategories();
              }
            });
          }
        },
      );

      // Only proceed if we're mounted (widget still exists)
      if (!mounted) return;

      // 4. Initialize TableLockManager
      TableLockService().initialize(
        onTableOccupiedUpdated: (tableId, isOccupied) {
          if (mounted) {
            // Use the full update method including status
            updateTableStatus(
              tableId,
              isOccupied ? 'occupied' : 'free',
            );
          }
        },
        clientName: 'Mobile Client ${Random().nextInt(1000)}',
        dataRepository: DataRepository(),
        context: context,
        connectionMonitor: connectionMonitor,
      );

      // 5. Load initial data if online
      if (_isOnline) {
        loadInitialData();
        _loadCategories();
      }
    } catch (e) {
      if (mounted) {
        // Show error to user or retry initialization
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Connection initialization failed: ${e.toString()}')),
        );
      }
      // Retry after delay
      Future.delayed(const Duration(seconds: 5), _initializeSocketAndServices);
    }
  }

  Future<void> updateTableStatus(String tableId, String status) async {
    if (!mounted) return;

    // Debug print to verify updates
    print('Updating table $tableId to status: $status');

    setState(() {
      tables = tables.map((table) {
        if (table['id'].toString() == tableId) {
          return {
            ...table,
            'status': status,
            'conti_aperti': status == 'occupied' ? 1 : 0,
          };
        }
        return table;
      }).toList();
    });

    // Only send to server if online and status is occupied
    if (status == 'occupied' && await connectionMonitor.isConnectedToWifi()) {
      try {
        final success =
            await TableLockService().manager.tableUpdatefromserver();
        if (!success) {
          print('Failed to update server status for table $tableId');
        }
      } catch (e) {
        print('Error updating server table status: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating table status')),
          );
        }
      }
    }
  }

  Future<void> loadInitialData() async {
    if (!mounted) return;
    final isOnline = await connectionMonitor.isConnectedToWifi();
    setState(() => isLoadingRooms = true);
    try {
      rooms = await DataRepository().getSalas(context, isOnline);
      if (rooms.isNotEmpty) {
        await _loadTavolosForSala(rooms[selectedRoomIndex]['id'] as int);
      }
    } catch (e) {
      print("Error loading data: $e");
    }
    if (mounted) {
      setState(() => isLoadingRooms = false);
    }
  }

  Future<void> _loadTavolosForSala(int salaId) async {
    if (isLoadingTables || !mounted) return;

    setState(() => isLoadingTables = true);

    try {
      final isOnline = await connectionMonitor.isConnectedToWifi();
      final newTables =
          await DataRepository().getTavolos(context, salaId, isOnline);

      // Filter out tables where mod_banco = 1
      final filteredTables =
          newTables.where((table) => table['mod_banco'] != 1).toList();

      if (mounted) {
        setState(() {
          tables = filteredTables;
          // Reset client counts when loading new tables
          tableClientCounts.clear();
          _loadClientCountsForTables(filteredTables);
        });
      }
    } catch (e) {
      print("Error loading tavolos: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tables')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingTables = false);
      }
    }
  }

  Future<void> _loadClientCountsForTables(
    List<Map<String, dynamic>> tables,
  ) async {
    tables.where((t) => t['conti_aperti'] > 0).forEach((table) async {
      final orders = await DataRepository().getOrdersForTable(
        context,
        table['id'],
        await connectionMonitor.isConnectedToWifi(),
      );

      final copertoOrder = orders.firstWhere(
        (order) => order['mov_descr'] == 'COPERTO',
        orElse: () => {},
      );

      if (copertoOrder.isNotEmpty && mounted) {
        setState(() {
          tableClientCounts[table['id']] = copertoOrder['mov_qta'] ?? 1;
        });
      }
    });
  }

  Future<void> _loadCategories() async {
    final isOnline = await connectionMonitor.isConnectedToWifi();
    if (!mounted) return;

    setState(() => isLoadingCategories = true);

    try {
      categories = await DataRepository().getGruppi(context, isOnline);

      if (categories.isNotEmpty) {
        await Future.wait(
          categories.map((gruppo) {
            final gruppoId = gruppo['id'];
            return Future.wait([
              DataRepository().getArticoliByGruppo(context, gruppoId, isOnline),
              DataRepository().getvariantiByGruppo(context, gruppoId, isOnline),
            ]);
          }),
        );
      }
    } catch (e) {
      print("Error loading categories and related data: $e");
      await AppLogger().log(
        'Error loading categories and related data',
        error: e.toString(),
      );
    }

    if (mounted) {
      setState(() => isLoadingCategories = false);
    }
  }

  Future<void> _onSalaChanged(int index) async {
    if (index == selectedRoomIndex ||
        index < 0 ||
        index >= rooms.length ||
        !mounted) return;
    setState(() => selectedRoomIndex = index);
    await _loadTavolosForSala(rooms[index]['id'] as int);
  }

  @override
  void dispose() {
    TableLockService().manager.dispose();
    _roomPageController.dispose();
    connectionMonitor.stopMonitoring();
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
              padding: EdgeInsets.symmetric(horizontal: 8),
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
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
      shape: CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: Colors.grey[700]),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          shape: CircleBorder(),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _isOnline ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnline ? Colors.green : Colors.red,
          width: 1.5,
        ),
      ),
      child: Text(
        _isOnline ? 'Online' : 'Offline',
        style: TextStyle(
          color: _isOnline ? Colors.green[800] : Colors.red[800],
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFfcfcfc),
      body: Column(
        children: [
          Stack(children: [CustomAppBar()]),
          SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sala',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                _buildConnectionStatus(),
              ],
            ),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: isLoadingRooms
                ? _buildRoomShimmer()
                : rooms.isEmpty
                    ? Center(child: Text("No rooms available"))
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          PageView.builder(
                            controller: _roomPageController,
                            itemCount: rooms.length,
                            onPageChanged: (index) => _onSalaChanged(index),
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selectedRoomIndex == index
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selectedRoomIndex == index
                                          ? Colors.black
                                          : Colors.grey[300]!,
                                      width: 1.5,
                                    ),
                                    boxShadow: selectedRoomIndex == index
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.1,
                                              ),
                                              blurRadius: 6,
                                              offset: Offset(0, 3),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    rooms[index]['des'] as String,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: selectedRoomIndex == index
                                          ? Colors.black
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
                                    duration: Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              }),
                            ),
                          if (rooms.length > 1)
                            Positioned(
                              right: 4,
                              child:
                                  _buildChevronButton(Icons.chevron_right, () {
                                if (selectedRoomIndex < rooms.length - 1) {
                                  _roomPageController.nextPage(
                                    duration: Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              }),
                            ),
                        ],
                      ),
          ),
          SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tavoli',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: isLoadingRooms || isLoadingTables
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
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: tables.length,
                          itemBuilder: (context, index) {
                            final table = tables[index];
                            return TableWidget(
                              table: table,
                              categories: categories,
                              clientCount: tableClientCounts[table['id']] ?? 0,
                              connectionMonitor: connectionMonitor,
                              onUpdateTableStatus: (tableId, status) {
                                updateTableStatus(tableId, status);
                              },
                            );
                          },
                        ),
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class TableWidget extends StatelessWidget {
  final Map<String, dynamic> table;
  final List<Map<String, dynamic>> categories;
  final int clientCount;
  final connectionMonitor;
  final void Function(String tableId, String status)? onUpdateTableStatus;

  const TableWidget({
    Key? key,
    required this.table,
    required this.categories,
    required this.clientCount,
    required this.connectionMonitor,
    this.onUpdateTableStatus,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use conti_aperti as fallback for status
    final status =
        table['status'] ?? (table['conti_aperti'] > 0 ? 'occupied' : 'free');
    final isOccupied = status == 'occupied';
    final isPending = status == 'pending';
    final hasClients = (table['conti_aperti'] ?? 0) > 0 && clientCount > 0;

    // Colors based on status
    final Color backgroundColor;
    final Color borderColor;
    final Color textColor = Colors.grey[800]!;

    if (isPending) {
      backgroundColor = const Color(0xFFFFF3E0); // Light orange
      borderColor = Colors.orange;
    } else if (isOccupied) {
      backgroundColor = const Color(0xFFD1ECCE); // Light green
      borderColor = const Color(0xFF48A93B); // Green
    } else {
      backgroundColor = Colors.white;
      borderColor = Colors.grey[300]!;
    }

    return GestureDetector(
      onTap: () async {
        final isOnline = await connectionMonitor.isConnectedToWifi();
        try {
          final orders = await DataRepository().getOrdersForTable(
            context,
            table['id'],
            isOnline,
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TableDetailsPage(
                table: table,
                orders: orders,
                categories: categories,
                onUpdateTableStatus: onUpdateTableStatus,
              ),
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading table details')),
          );
        }
      },
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    table['des'] ?? '',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  if (isPending)
                    Text(
                      'In attesa',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasClients)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[700]),
                    const SizedBox(width: 4),
                    Text(
                      clientCount.toString(),
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
    );
  }
}
