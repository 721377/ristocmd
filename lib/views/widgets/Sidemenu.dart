import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:ristocmd/Settings/settings.dart';
import 'package:ristocmd/services/database.dart';
import 'package:ristocmd/services/datarepo.dart';
import 'package:ristocmd/services/logger.dart';
import 'package:ristocmd/services/soketmang.dart';
import 'package:ristocmd/services/tablelockservice.dart';
import 'package:ristocmd/services/wifichecker.dart';
import 'package:ristocmd/views/Homepage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModernDrawer extends StatefulWidget {
  final List<Map<String, dynamic>> operators;

  const ModernDrawer({
    super.key,
    required this.operators,
  });

  @override
  State<ModernDrawer> createState() => ModernDrawerState();
}

class ModernDrawerState extends State<ModernDrawer> {
  int _selectedSection = 0; // 0=Settings, 1=Advanced
  bool _isUpdating = false;
  bool _displayInline = false;
  bool _disableNotifications = false;
  final connectionMonitor = WifiConnectionMonitor();
  bool _compactView = false;

  bool _isOnline = true;
  final accentColor = Color.fromARGB(255, 255, 198, 65);
  String _buttonText = 'Aggiorna Impostazioni';
  bool _isSendingLogs = false;
  String _logButtonText = 'Invia Log';
  late String selectedoperator;
 late PackageInfo packageInfo;
  String appVersion = 'Loading...';


 @override
  void initState() {
    super.initState();
    loadCompactViewPreference();
    _initializePackageInfo(); // Initialize package info
    if (widget.operators.isNotEmpty) {
      selectedoperator = widget.operators.first['id'].toString();
    } else {
      selectedoperator = '';
    }
  }


  Future<void> loadCompactViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool('compact_view');

    if (savedValue != null) {
      setState(() {
        _compactView = savedValue;
      });
    }

  }
Future<void> _initializePackageInfo() async {
    try {
      packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        appVersion = packageInfo.version; // Update the display value
      });
      
      // Save the current version to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_version', packageInfo.version);
    } catch (e) {
      setState(() {
        appVersion = 'Unknown'; // Fallback if there's an error
      });
      AppLogger().log('Error getting package info', error: e.toString());
    }
  }

  void _toggleCompactView() async {
    setState(() {
      _compactView = !_compactView;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('compact_view', _compactView);
  }

  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Drawer(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Menu',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(
                              width:
                                  12), // small space between "Menu" and version
                          Text(
                          'V$appVersion',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color.fromARGB(255, 147, 147, 147),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black),
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                // Navigation tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      _buildNavButton('Impostazioni', 0, accentColor),
                      const SizedBox(width: 8),
                      _buildNavButton('Avanzate', 1, accentColor),
                    ],
                  ),
                ),

                const Divider(height: 32, thickness: 1, color: Colors.grey),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedSection == 0) ...[
                          _buildSectionTitle('Operatore'),
                          const SizedBox(height: 8),
                          _buildOperatorButton(accentColor),
                          const SizedBox(height: 24),
                          _buildSectionTitle('Layout'),
                          const SizedBox(height: 16),
                          _buildSettingsList(accentColor),
                        ] else ...[
                          _buildSectionTitle('Impostazioni Avanzate'),
                          const SizedBox(height: 16),
                          _buildAdvancedSettings(),
                        ],
                        const SizedBox(height: 16),
                        _buildUpdateButton(accentColor, context),
                        const SizedBox(height: 12),
                        _buildLogoutButton(context), // Pass context here
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(String text, int section, Color accentColor) {
    final isSelected = _selectedSection == section;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSection = section),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? accentColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected ? accentColor : Colors.grey,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildOperatorButton(Color accentColor) {
    final bool isLoading = widget.operators.isEmpty;

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(13, 0, 0, 0),
            blurRadius: 10,
            spreadRadius: 1,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: isLoading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Attendere il caricamento dei dati...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            )
          : DropdownButton<String>(
              value: selectedoperator,
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    selectedoperator = newValue;
                  });
                }
              },
              isExpanded: true,
              dropdownColor: Colors.white,
              items: widget.operators.map<DropdownMenuItem<String>>((operator) {
                final rawName =
                    (operator['nome'] as String?)?.isNotEmpty == true
                        ? operator['nome']
                        : operator['username'];
                final displayName = rawName.replaceAll('%20', ' ');

                return DropdownMenuItem<String>(
                  value: operator['id'].toString(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              }).toList(),
              icon: const Icon(Icons.arrow_drop_down,
                  color: Colors.black54, size: 24),
              underline: Container(),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
              ),
              hint: Text(
                'Seleziona operatore',
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
            ),
    );
  }

  Widget _buildSettingsList(Color accentColor) {
    return Column(
      children: [
        _buildSettingTile(
          icon: Icons.view_agenda_outlined,
          title: 'Prodotti in riga',
          value: _compactView,
          onChanged: (val) {
            _toggleCompactView();
          },
          accentColor: accentColor,
        ),
        _buildSettingTile(
          icon: Icons.notifications_outlined,
          title: 'Notifiche',
          value: !_disableNotifications,
          onChanged: (val) => setState(() => _disableNotifications = !val),
          accentColor: accentColor,
        ),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
    required Color accentColor,
  }) {
    print(value);
    return GestureDetector(
      onTap: () => onChanged(!value), // This toggles the value
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: const Color.fromARGB(255, 218, 218, 218), width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 26, color: accentColor),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(color: Colors.black)),
              const Spacer(),
              Transform.scale(
                scale:
                    1.1, // Slightly reduced the size for a more balanced look
                child: Switch(
                  value: value, // Use the current value (true or false)
                  onChanged: onChanged, // Pass the callback for toggling
                  activeColor: accentColor,
                  activeTrackColor: value
                      ? Color.fromARGB(
                          255, 255, 230, 171) // Background color when selected
                      : const Color.fromARGB(
                          255, 220, 220, 220), // Lighter active track color
                  inactiveTrackColor: const Color.fromARGB(
                      255, 218, 218, 218), // Color for unselected state
                  inactiveThumbColor:
                      Colors.white, // Color of the thumb in unselected state
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    return Column(
      children: [
        _buildListTile(
          icon: Icons.send_outlined,
          title: _logButtonText,
          onTap: _sendLogs,
          isDisabled: _isSendingLogs,
          leadingOverride: _isSendingLogs
              ? const SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color.fromARGB(255, 255, 198, 65),
                  ),
                )
              : null,
        ),
        _buildListTile(
          icon: Icons.info_outline,
          title: 'Log',
          onTap: () {},
        ),
        _buildListTile(
          icon: Icons.help_outline,
          title: 'Assistenza',
          onTap: () {},
        ),
      ],
    );
  }

  Future<void> _sendLogs() async {
    setState(() {
      _isSendingLogs = true;
      _logButtonText = 'Invio in corso...';
    });

    final logger = AppLogger();
    await logger.init();
    final success = await logger.sendLogsToServer();

    if (mounted) {
      setState(() {
        _logButtonText = success ? 'Invio completato!' : 'Invio fallito';
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isSendingLogs = false;
            _logButtonText = 'Invia Log';
          });
        }
      });
    }
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDisabled = false,
    Widget? leadingOverride,
  }) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: const Color.fromARGB(255, 218, 218, 218),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: leadingOverride ?? Icon(icon, color: accentColor, size: 25),
          title: Text(
            title,
            style: TextStyle(
              color: isDisabled ? Colors.grey : Colors.black,
            ),
          ),
          trailing: isDisabled
              ? null
              : const Icon(Icons.chevron_right, color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildUpdateButton(Color accentColor, BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _buttonText == 'Aggiornato con successo'
              ? const Color(0xFFE6F4EA)
              : accentColor,
          foregroundColor: _buttonText == 'Aggiornato con successo'
              ? const Color(0xFF28A745)
              : const Color.fromARGB(255, 255, 255, 255),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _isUpdating
            ? null
            : () async {
                await _updateSettings(context);
                setState(() {
                  _buttonText = 'Aggiornato con successo';
                });

                await Future.delayed(const Duration(seconds: 2));

                setState(() {
                  _buttonText = 'Aggiorna Impostazioni';
                });
              },
        child: _isUpdating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color.fromARGB(255, 51, 51, 51),
                ),
              )
            : Text(_buttonText),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () => _showLogoutConfirmation(context),
        child: const Text('Logout'),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout,
                  size: 48,
                  color: Color.fromARGB(255, 255, 198, 65),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Disconnetti?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sei sicuro di voler uscire?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black54,
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Annulla'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Color.fromARGB(255, 255, 198, 65),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _logout(context);
                        },
                        child: const Text('Disconnetti'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateSettings(context) async {
    setState(() => _isUpdating = true);

    _isOnline = await connectionMonitor.isConnectedToWifi();
    await HomePageState.loadAndSaveImpostazioni(context, _isOnline);

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isUpdating = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await _disposeAllServices();
      await DatabaseHelper.instance.clearAllTables();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/setup',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      AppLogger().log('Error during logout', error: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error during logout')),
        );
      }
    }
  }

  Future<void> _disposeAllServices() async {
    try {
      SocketManager().dispose();
    } catch (e) {
      AppLogger().log('Error disposing SocketManager', error: e.toString());
    }
    try {
      connectionMonitor.stopMonitoring();
    } catch (e) {
      AppLogger().log('Error stopping connection monitor', error: e.toString());
    }
  }
}
