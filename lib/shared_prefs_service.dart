import 'package:shared_preferences/shared_preferences.dart';

// 앱 설정 저장 서비스
class SharedPrefsService {
  // 키 상수
  static const String _brokerIpKey = 'broker_ip';
  static const String _clientIdKey = 'client_id';

  // MQTT 브로커 IP 저장
  static Future<void> saveBrokerIp(String ip) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brokerIpKey, ip);
  }

  // MQTT 브로커 IP 가져오기
  static Future<String> getBrokerIp() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_brokerIpKey) ?? '';
  }

  // MQTT 브로커 IP 초기화
  static Future<void> resetBrokerIp() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_brokerIpKey);
  }

  // 클라이언트 ID 저장 (재접속 시 동일 ID 사용)
  static Future<void> saveClientId(String clientId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientIdKey, clientId);
  }

  // 클라이언트 ID 가져오기
  static Future<String> getClientId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clientIdKey) ?? '';
  }

  // 모든 설정 초기화
  static Future<void> resetAllSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
