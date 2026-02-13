import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class StorageService {
  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // API Key
  String get apiKey => _prefs.getString(AppConstants.keyApiKey) ?? '';
  Future<void> setApiKey(String value) =>
      _prefs.setString(AppConstants.keyApiKey, value);

  // Proxy
  String get proxyHost =>
      _prefs.getString(AppConstants.keyProxyHost) ??
      AppConstants.defaultProxyHost;
  Future<void> setProxyHost(String value) =>
      _prefs.setString(AppConstants.keyProxyHost, value);

  int get proxyPort =>
      _prefs.getInt(AppConstants.keyProxyPort) ?? AppConstants.defaultProxyPort;
  Future<void> setProxyPort(int value) =>
      _prefs.setInt(AppConstants.keyProxyPort, value);

  bool get proxyEnabled => _prefs.getBool(AppConstants.keyProxyEnabled) ?? true;
  Future<void> setProxyEnabled(bool value) =>
      _prefs.setBool(AppConstants.keyProxyEnabled, value);

  // Voice
  String get voiceName =>
      _prefs.getString(AppConstants.keyVoiceName) ?? AppConstants.defaultVoice;
  Future<void> setVoiceName(String value) =>
      _prefs.setString(AppConstants.keyVoiceName, value);
}
