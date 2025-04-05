import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool isFirstLaunch() {
    return _prefs.getBool('is_first_launch') ?? true;
  }

  static Future<void> setNotFirstLaunch() async {
    await _prefs.setBool('is_first_launch', false);
  }

  static Future<void> saveCountry(String country) async {
    await _prefs.setString('mapping_country', country);
  }

  static String? getCountry() {
    return _prefs.getString('mapping_country');
  }
}