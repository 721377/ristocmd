import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCommandStorage {
  static const String _storageKey = 'pending_commands';
  
  Future<void> saveCommand(Map<String, dynamic> command) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_storageKey) ?? [];
    existing.add(jsonEncode(command));
    await prefs.setStringList(_storageKey, existing);
  }

  Future<List<Map<String, dynamic>>> getPendingCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final commands = prefs.getStringList(_storageKey) ?? [];
    return commands.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> clearCommands() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> removeCommand(Map<String, dynamic> command) async {
    final prefs = await SharedPreferences.getInstance();
    final commands = prefs.getStringList(_storageKey) ?? [];
    final commandJson = jsonEncode(command);
    commands.removeWhere((c) => c == commandJson);
    await prefs.setStringList(_storageKey, commands);
  }
}