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
  List<Map<String, dynamic>> rooms = [];
  int selectedRoomIndex = 0;
  final PageController _roomPageController = PageController(viewportFraction: 0.8);

  List<Map<String, dynamic>> tables = [];
  bool isLoadingRooms = true;
  bool isLoadingTables = false;
  bool isLoadingCategories = false;
  bool _isOnline = true;

  late TableLockManager tableLockManager;
  late IO.Socket socket;
  final connectionMonitor = WifiConnectionMonitor();
  Map<int, int> tableClientCounts = {};
  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF1A1A1A),
        statusBarIconBrightness: Brightness.light,
      ),
    );

    connectionMonitor.startMonitoring();
    _initializeServicesAndFetchData();
  }

  Future<void> _initializeServicesAndFetchData() async {
    try {
      await SocketManager().initialize(
        connectionMonitor: connectionMonitor,
        context: context,
        onStatusChanged: (isOnline) {
          if (mounted) {
            setState(() => _isOnline = isOnline);
            if (isOnline) _fetchAllData();
          }
        },
      );

      if (!mounted) return;

      TableLockService().initialize(
        onTableOccupiedUpdated: (tableId, isOccupied) {
          if (mounted) {
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

      if (_isOnline) {
        await _fetchAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection initialization failed: $e')),
        );
      }
      Future.delayed(const Duration(seconds: 5), _initializeServicesAndFetchData);
    }
  }

  Future<void> _fetchAllData() async {
    final isOnline = await connectionMonitor.isConnectedToWifi();
    if (!mounted || !isOnline) return;

    setState(() => isLoadingRooms = true);
    try {
      rooms = await DataRepository().getSalas(context, isOnline);
      if (rooms.isNotEmpty) {
        await _loadTavolosForSala(rooms[selectedRoomIndex]['id']);
        await _loadAndSaveImpostazioni();
        await _loadCategories();
      }
    } catch (e) {
      print("Error loading initial data: $e");
    } finally {
      if (mounted) setState(() => isLoadingRooms = false);
    }
  }

  Future<void> updateTableStatus(String tableId, String status) async {
    if (!mounted) return;

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

    if (status == 'occupied' && await connectionMonitor.isConnectedToWifi()) {
      try {
        final success = await TableLockService().manager.tableUpdatefromserver();
        if (!success) {
          print('Failed to update server status for table $tableId');
        }
      } catch (e) {
        print('Error updating server table status: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error updating table status')),
          );
        }
      }
    }
  }

  Future<void> _loadTavolosForSala(int salaId) async {
    if (!mounted || isLoadingTables) return;

    setState(() => isLoadingTables = true);

    try {
      final isOnline = await connectionMonitor.isConnectedToWifi();
      final newTables = await DataRepository().getTavolos(context, salaId, isOnline);

      final filteredTables = newTables.where((table) => table['mod_banco'] != 1).toList();

      if (mounted) {
        setState(() {
          tables = filteredTables;
          tableClientCounts.clear();
        });
        await _loadClientCountsForTables(filteredTables);
      }
    } catch (e) {
      print("Error loading tavolos: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading tables')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoadingTables = false);
    }
  }

  Future<void> _loadClientCountsForTables(List<Map<String, dynamic>> tables) async {
    for (final table in tables.where((t) => t['conti_aperti'] > 0)) {
      try {
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
        } else if (mounted) {
          setState(() {
            tableClientCounts[table['id']] = 1;
          });
        }
      } catch (e) {
        print("Error loading client count for table ${table['id']}: $e");
      }
    }
  }

  Future<void> _loadAndSaveImpostazioni() async {
    final isOnline = await connectionMonitor.isConnectedToWifi();
    try {
      final impostazioni = await DataRepository().getImpostazioniPalmari(context, isOnline);
      final prefs = await SharedPreferences.getInstance();

      for (var setting in impostazioni) {
        setting.forEach((key, value) async {
          if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          }
        });
      }

      print("Impostazioni saved to SharedPreferences: $impostazioni");
    } catch (e) {
      print("Failed to load/save impostazioni: $e");
    }
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

    if (mounted) setState(() => isLoadingCategories = false);
  }

  Future<void> _onSalaChanged(int index) async {
    if (!mounted || index == selectedRoomIndex || index < 0 || index >= rooms.length) return;
    setState(() => selectedRoomIndex = index);
    await _loadTavolosForSala(rooms[index]['id']);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isOnline ? const  Color(0xFFE6F4EA) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnline ? const Color(0xFF28A745) : const Color(0xFFF44336),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOnline ? Icons.wifi : Icons.wifi_off,
            size: 14,
            color:
                _isOnline ? const Color(0xFF28A745) : const Color(0xFFF44336),
          ),
          const SizedBox(width: 4),
          Text(
            _isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color:
                  _isOnline ? const Color(0xFF28A745) : const Color(0xFFF44336),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: Column(
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
            child: isLoadingRooms
                ? _buildRoomShimmer()
                : rooms.isEmpty
                    ? Center(child: Text("Nessuna sala disponibile"))
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
                                    color:  selectedRoomIndex == index
                                          ? const Color.fromARGB(255, 255, 198, 65):Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selectedRoomIndex == index
                                          ? const Color.fromARGB(255, 231, 231, 231)
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
                                          ? const Color.fromARGB(255, 255, 255, 255)
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
                                    duration: const Duration(milliseconds: 300),
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
                                    duration: const Duration(milliseconds: 300),
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
          const SizedBox(height: 16),
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
    final status = table['status'] ?? (table['conti_aperti'] > 0 ? 'occupied' : 'free');
    final isOccupied = status == 'occupied';
    final isPending = status == 'pending';
    final hasClients = isOccupied; // Show client count if table is occupied

    // Colors based on status
    final Color backgroundColor;
    final Color borderColor;
    final Color textColor = Colors.grey[800]!;

    if (isPending) {
      backgroundColor = const Color(0xFFFFF3E0);
      borderColor = const Color(0xFFFFA000);
    } else if (isOccupied) {
      backgroundColor = const Color(0xFFE6F4EA);
      borderColor = const Color(0xFF28A745);
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
            const SnackBar(content: Text('Errore nel caricamento dei dettagli del tavolo')),
          );
        }
      },
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
                    table['des'] ?? '',
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
                        child: Text(
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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

class ModernAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ModernAppBar({Key? key}) : super(key: key);

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
        color: Color.fromARGB(255, 255, 198, 65),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(48),
          bottomRight: Radius.circular(48),
        ),
        border: Border.all(color: const Color.fromARGB(255, 218, 218, 218),width:1.1),
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
                icon: const Icon(Icons.sort, color:  Color.fromARGB(255, 255, 255, 255),size: 30,),
                onPressed: () {},
              ),
              const Text(
                "RISTOCOMANDE",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color:  Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(width: 48), // Balance the layout
            ],
          ),
        ],
      ),
    );
  }
}
