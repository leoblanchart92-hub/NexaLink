import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/vpn_config.dart';
import '../config/constants.dart';

/// Local storage service using SharedPreferences
class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Device identity
  String? getDeviceId() => _prefs.getString(AppConstants.keyDeviceId);
  
  Future<void> setDeviceId(String id) async {
    await _prefs.setString(AppConstants.keyDeviceId, id);
  }

  // VPN Config
  VpnConfig? getVpnConfig() {
    final json = _prefs.getString(AppConstants.keyOwnerConfig) ??
        _prefs.getString(AppConstants.keyGuestConfig);
    if (json == null) return null;
    try {
      return VpnConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveVpnConfig(VpnConfig config, {bool isOwner = true}) async {
    final key = isOwner ? AppConstants.keyOwnerConfig : AppConstants.keyGuestConfig;
    await _prefs.setString(key, jsonEncode(config.toJson()));
  }

  Future<void> clearVpnConfig() async {
    await _prefs.remove(AppConstants.keyOwnerConfig);
    await _prefs.remove(AppConstants.keyGuestConfig);
  }

  // Guest devices management (owner side)
  List<Device> getGuestDevices() {
    final jsonList = _prefs.getString(AppConstants.keyGuestList);
    if (jsonList == null) return [];
    try {
      final list = jsonDecode(jsonList) as List<dynamic>;
      return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addGuestDevice(Device device) async {
    final guests = getGuestDevices();
    guests.add(device);
    await _saveGuestList(guests);
  }

  Future<void> updateGuestDevice(Device device) async {
    final guests = getGuestDevices();
    final index = guests.indexWhere((d) => d.id == device.id);
    if (index >= 0) {
      guests[index] = device;
      await _saveGuestList(guests);
    }
  }

  Future<void> removeGuestDevice(String deviceId) async {
    final guests = getGuestDevices();
    guests.removeWhere((d) => d.id == deviceId);
    await _saveGuestList(guests);
  }

  Future<void> revokeGuestDevice(String deviceId) async {
    final guests = getGuestDevices();
    final index = guests.indexWhere((d) => d.id == deviceId);
    if (index >= 0) {
      guests[index] = guests[index].copyWith(status: DeviceStatus.revoked);
      await _saveGuestList(guests);
    }
  }

  Device? getGuestDevice(String deviceId) {
    final guests = getGuestDevices();
    try {
      return guests.firstWhere((d) => d.id == deviceId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveGuestList(List<Device> guests) async {
    final jsonList = guests.map((d) => d.toJson()).toList();
    await _prefs.setString(AppConstants.keyGuestList, jsonEncode(jsonList));
  }

  // Settings
  String? getRelayServer() => _prefs.getString('relay_server');
  
  Future<void> setRelayServer(String server) async {
    await _prefs.setString('relay_server', server);
  }

  bool getAutoConnect() => _prefs.getBool('auto_connect') ?? false;

  Future<void> setAutoConnect(bool value) async {
    await _prefs.setBool('auto_connect', value);
  }

  bool getConsentGiven() => _prefs.getBool('consent_given') ?? false;

  Future<void> setConsentGiven(bool value) async {
    await _prefs.setBool('consent_given', value);
  }

  bool isFirstLaunch() => _prefs.getBool(AppConstants.keyFirstLaunch) ?? true;

  Future<void> setFirstLaunchDone() async {
    await _prefs.setBool(AppConstants.keyFirstLaunch, false);
  }

  // Traffic stats persistence
  Future<void> saveTrafficStats(int bytesReceived, int bytesSent) async {
    await _prefs.setInt('total_rx', bytesReceived);
    await _prefs.setInt('total_tx', bytesSent);
  }

  int getTotalRx() => _prefs.getInt('total_rx') ?? 0;
  int getTotalTx() => _prefs.getInt('total_tx') ?? 0;

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
