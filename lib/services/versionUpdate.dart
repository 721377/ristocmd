import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VersionChecker {
  static Future<bool> isAppUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    
    final currentVersion = packageInfo.version;
    final savedVersion = prefs.getString('app_version');

    if (savedVersion == null || savedVersion != currentVersion) {
      await prefs.setString('app_version', currentVersion);
      return true;
    }
    return false;
  }

  static Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static Future<String?> getSavedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_version');
  }
}