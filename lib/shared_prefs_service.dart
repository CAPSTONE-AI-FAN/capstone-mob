import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:math';

// 앱 설정 저장 서비스
class SharedPrefsService {
  // 키 상수
  static const String _brokerIpKey = 'broker_ip';
  static const String _clientIdKey = 'client_id';
  static const String _deviceUuidKey = 'device_uuid';

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

  // 클라이언트 ID 가져오기 (더 안정적인 방법)
  static Future<String> getClientId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedClientId = prefs.getString(_clientIdKey);
    
    // 저장된 클라이언트 ID가 없으면 디바이스별 고유 ID 생성
    if (savedClientId == null || savedClientId.isEmpty) {
      savedClientId = await _generateStableClientId();
      await prefs.setString(_clientIdKey, savedClientId);
    }
    
    return savedClientId;
  }

  // 디바이스별 고유 UUID 생성/가져오기
  static Future<String> _getOrCreateDeviceUuid() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString(_deviceUuidKey);
    
    if (uuid == null || uuid.isEmpty) {
      // 간단한 UUID 생성 (디바이스별 고유성 보장)
      final random = Random();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomNum = random.nextInt(99999);
      
      // 플랫폼 정보 포함
      String platform = 'unknown';
      try {
        if (Platform.isAndroid) platform = 'and';
        else if (Platform.isIOS) platform = 'ios';
        else if (Platform.isMacOS) platform = 'mac';
        else if (Platform.isWindows) platform = 'win';
      } catch (e) {
        platform = 'web';
      }
      
      uuid = '${platform}_${timestamp}_${randomNum}';
      await prefs.setString(_deviceUuidKey, uuid);
    }
    
    return uuid;
  }

  // 안정적인 클라이언트 ID 생성
  static Future<String> _generateStableClientId() async {
    final deviceUuid = await _getOrCreateDeviceUuid();
    // mobile_client_ 접두사는 서버에서 모바일 클라이언트 식별용
    return 'mobile_client_$deviceUuid';
  }

  // 디바이스 UUID 가져오기 (외부에서 사용 가능)
  static Future<String> getDeviceUuid() async {
    return await _getOrCreateDeviceUuid();
  }

  // 모든 설정 초기화
  static Future<void> resetAllSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
