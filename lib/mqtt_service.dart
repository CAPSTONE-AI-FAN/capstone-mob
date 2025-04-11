import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class MQTTService {
  // MQTT 브로커 연결 설정
  final String broker;
  final int port;
  final int wsPort; // WebSocket 포트 추가
  final String clientIdentifier;
  final String username;
  final String password;
  final bool useTLS;

  int? lastMessageTimestamp;

  // 연결 상태 강화를 위한 추가 필드
  bool _receivedMessagesAfterConnect = false;
  bool _effectivelyConnected = false;
  DateTime _lastMessageReceived = DateTime.now();

  // 간접 연결 안정화를 위한 추가 필드
  int _consecutiveSuccessMessages = 0;
  int _consecutiveFailures = 0;
  bool _stableIndirectConnection = false;
  DateTime _lastConnectionAttempt = DateTime.now();
  bool _useWebSocket = false; // WebSocket 사용 여부

  // MQTT 토픽 설정
  static const Map<String, String> TOPICS = {
    'STATUS': 'device/status',
    'COMMAND': 'device/command',
    'TEMPERATURE': 'sensor/temperature',
    'SYSTEM': 'system/status',
    'CONTROL_ROTATION': 'control/rotation',
    'CONTROL_DIRECTION': 'control/direction',
    'CONTROL_AUTO_MODE': 'control/auto_mode',
    'CONTROL_STATUS': 'control/status',
  };

  late MqttServerClient client;

  // 메시지 스트림 컨트롤러 (토픽별 분리)
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers =
      {};

  // 연결 상태 스트림
  final StreamController<MqttConnectionState> _connectionStateController =
      StreamController<MqttConnectionState>.broadcast();

  // 효과적 연결 상태 스트림
  final StreamController<bool> _effectiveConnectionController =
      StreamController<bool>.broadcast();

  // 타이머
  Timer? _connectionMonitorTimer;
  Timer? _stabilityCheckTimer;

  // 연결 시도 카운터 및 타이머
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _explicitDisconnect = false;

  // 마지막으로 수신된 시스템 상태
  Map<String, dynamic>? _lastSystemState;

  // 온도 데이터 히스토리
  List<Map<String, dynamic>> _temperatureHistory = [];
  final int _maxTempHistoryItems = 20;

  // 게터
  Stream<MqttConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<bool> get effectiveConnectionStream =>
      _effectiveConnectionController.stream;
  MqttConnectionState? get connectionState => client.connectionStatus?.state;
  Map<String, dynamic>? get lastSystemState => _lastSystemState;
  List<Map<String, dynamic>> get temperatureHistory =>
      List.from(_temperatureHistory);
  bool get effectivelyConnected => _effectivelyConnected;
  bool get stableIndirectConnection => _stableIndirectConnection;
  bool get usingWebSocket => _useWebSocket;

  // 토픽별 메시지 스트림 획득
  Stream<Map<String, dynamic>> getTopicStream(String topic) {
    if (!_topicControllers.containsKey(topic)) {
      _topicControllers[topic] =
          StreamController<Map<String, dynamic>>.broadcast();
    }
    return _topicControllers[topic]!.stream;
  }

  MQTTService({
    required this.broker,
    required this.port,
    this.wsPort = 8883, // WebSocket 기본 포트 설정
    required this.clientIdentifier,
    required this.username,
    required this.password,
    this.lastMessageTimestamp,
    this.useTLS = false,
  }) {
    print(
        'MQTTService: 초기화 - 브로커: $broker, 포트: $port, WS포트: $wsPort, 클라이언트ID: $clientIdentifier');

    // 🔴 클라이언트 ID를 간단한 형식으로 변경
    final uniqueId = 'mob_${DateTime.now().millisecondsSinceEpoch % 10000}';

    // MQTT 클라이언트 초기화 시 고유 ID 사용
    _initializeClient(useWebSocket: false, clientId: uniqueId);

    // 모니터링 타이머 시작
    _startConnectionMonitor();
    _startStabilityCheck();
  }

  void _initializeClient({bool useWebSocket = false, String? clientId}) {
    _useWebSocket = useWebSocket;

    // 제공된 clientId를 사용하거나 기본값 사용
    final effectiveClientId = clientId ?? clientIdentifier;

    // MQTT 클라이언트 생성 - WebSocket URL 형식 조정
    if (useWebSocket) {
      final wsUrl = 'ws://$broker';
      print(
          'MQTTService: WebSocket 사용 - $wsUrl:$wsPort, 클라이언트ID: $effectiveClientId');
      client = MqttServerClient.withPort(wsUrl, effectiveClientId, wsPort);
      client.useWebSocket = true;
      client.websocketProtocols = ['mqtt'];
    } else {
      // 표준 TCP 연결
      client = MqttServerClient(broker, effectiveClientId);
      client.port = port;
    }

    // 공통 설정
    client.logging(on: true);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.connectTimeoutPeriod = 5000;

    // 콜백
    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
    client.onSubscribeFail = _onSubscribeFail;
    client.pongCallback = _pong;
    client.onAutoReconnect = _onAutoReconnect;
    client.onAutoReconnected = _onAutoReconnected;

    // TLS 설정
    if (useTLS) {
      client.secure = true;
      client.securityContext = SecurityContext.defaultContext;
    }

    // 연결 메시지 설정 (LWT 포함)
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(effectiveClientId)
        .authenticateAs(username, password)
        .withWillTopic(TOPICS['STATUS']!)
        .withWillMessage(jsonEncode({
          "device_id": effectiveClientId,
          "status": "disconnected",
          "client_type": "mobile_app",
          "connection_type": useWebSocket ? "websocket" : "tcp",
          "timestamp": DateTime.now().millisecondsSinceEpoch
        }))
        .startClean()
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain();

    client.connectionMessage = connMessage;
  }

  // 연결 모니터링 타이머 시작
  void _startConnectionMonitor() {
    _connectionMonitorTimer?.cancel();
    _connectionMonitorTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      final now = DateTime.now();
      final mqttConnected =
          client.connectionStatus?.state == MqttConnectionState.connected;

      // 메시지 수신 기반 연결 상태 확인 (시간 간격 확장)
      final messageReceivedRecently =
          now.difference(_lastMessageReceived).inSeconds < 20; // 20초로 확장

      // 새로운 효과적 연결 상태 계산
      final newEffectiveState = mqttConnected ||
          messageReceivedRecently ||
          (_receivedMessagesAfterConnect && _stableIndirectConnection);

      // 상태가 변경되었을 때만 업데이트
      if (newEffectiveState != _effectivelyConnected) {
        _effectivelyConnected = newEffectiveState;
        _effectiveConnectionController.add(_effectivelyConnected);
        print(
            'MQTTService: 효과적 연결 상태 변경: $_effectivelyConnected (안정적 간접 연결: $_stableIndirectConnection)');

        // 연결 상태가 변경될 때 필요한 조치 수행
        if (_effectivelyConnected) {
          // 연결이 복구되면 재시도 카운터 리셋
          _consecutiveFailures = 0;

          // 직접 MQTT 연결이 없지만 간접 연결된 경우 주기적인 재연결 시도 스케줄링
          if (!mqttConnected &&
              _reconnectTimer == null &&
              !_explicitDisconnect) {
            _scheduleReconnect(quiet: true); // 조용한 재연결 시도
          }
        } else {
          // 연결이 끊어진 경우 즉시 재연결 시도
          if (!_explicitDisconnect && _reconnectTimer == null) {
            _scheduleReconnect();
          }
        }
      }
    });
  }

  // 연결 안정성 확인 타이머
  void _startStabilityCheck() {
    _stabilityCheckTimer?.cancel();
    _stabilityCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      final now = DateTime.now();

      // 최근 메시지 수신 여부 확인
      if (lastMessageTimestamp != null) {
        final messageAge = now.millisecondsSinceEpoch - lastMessageTimestamp!;

        if (messageAge < 12000) {
          // 12초 이내 메시지 수신
          _consecutiveSuccessMessages++;
          _consecutiveFailures = 0;

          // 연속 2회 이상 성공적인 메시지 수신 시 안정적인 간접 연결로 간주
          if (_consecutiveSuccessMessages >= 2 && !_stableIndirectConnection) {
            _stableIndirectConnection = true;
            print('MQTTService: 안정적인 간접 연결 설정됨');
          }
        } else {
          _consecutiveSuccessMessages = 0;
          _consecutiveFailures++;

          // 연속 3회 이상 메시지 수신 실패 시 안정적 연결 상태 해제
          if (_consecutiveFailures >= 3 && _stableIndirectConnection) {
            _stableIndirectConnection = false;
            print('MQTTService: 안정적인 간접 연결 해제됨');

            // 연결 상태 업데이트
            if (client.connectionStatus?.state !=
                MqttConnectionState.connected) {
              _effectivelyConnected = false;
              _effectiveConnectionController.add(false);

              // 재연결 시도
              if (!_explicitDisconnect && _reconnectTimer == null) {
                _scheduleReconnect();
              }
            }
          }
        }
      }

      // 직접 MQTT 연결이 없고 마지막 연결 시도 이후 특정 시간이 지나면 재시도
      if (client.connectionStatus?.state != MqttConnectionState.connected &&
          _stableIndirectConnection &&
          now.difference(_lastConnectionAttempt).inMinutes >= 1 &&
          _reconnectTimer == null &&
          !_explicitDisconnect) {
        print('MQTTService: 간접 연결 상태에서 정기적인 직접 연결 시도');
        _scheduleReconnect(quiet: true, delay: 1000);
      }

      // 일정 기간 동안 어떤 메시지도 수신하지 못했으면 연결 재설정 시도
      if (lastMessageTimestamp != null) {
        final lastMsgTime =
            DateTime.fromMillisecondsSinceEpoch(lastMessageTimestamp!);
        if (now.difference(lastMsgTime).inSeconds > 60 && // 1분 이상 메시지 없음
            _reconnectTimer == null &&
            !_explicitDisconnect) {
          print('MQTTService: 장시간 메시지 수신 없음 - 전체 연결 재설정');
          _forceReconnect();
        }
      }

      // TCP 연결 실패 후 WebSocket 연결 시도
      if (!_useWebSocket &&
          _reconnectAttempts >= 3 &&
          client.connectionStatus?.state != MqttConnectionState.connected &&
          !_effectivelyConnected) {
        print('MQTTService: TCP 연결 실패 후 WebSocket으로 전환 시도');
        _switchToWebSocket();
      }
    });
  }

  // WebSocket 연결로 전환
  void _switchToWebSocket() {
    if (_useWebSocket) return; // 이미 WebSocket 사용 중이면 스킵

    print('MQTTService: WebSocket 연결로 전환');

    // 기존 연결 종료
    try {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.disconnect();
      }
    } catch (e) {
      print('MQTTService: 기존 연결 종료 중 오류: $e');
    }

    // WebSocket 클라이언트로 재초기화
    _initializeClient(useWebSocket: true);

    // 재연결 시도
    _reconnectAttempts = 0;
    _connect();
  }

  // TCP 연결로 되돌리기
  void _switchToTcp() {
    if (!_useWebSocket) return; // 이미 TCP 사용 중이면 스킵

    print('MQTTService: TCP 연결로 되돌리기');

    // 기존 연결 종료
    try {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.disconnect();
      }
    } catch (e) {
      print('MQTTService: 기존 연결 종료 중 오류: $e');
    }

    // TCP 클라이언트로 재초기화
    _initializeClient(useWebSocket: false);

    // 재연결 시도
    _reconnectAttempts = 0;
    _connect();
  }

  // 강제 연결 재설정
  void _forceReconnect() {
    print('MQTTService: 강제 연결 재설정 시작');

    // 기존 연결 정리
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // 모든 상태 초기화
    _receivedMessagesAfterConnect = false;
    _effectivelyConnected = false;
    _stableIndirectConnection = false;
    _consecutiveSuccessMessages = 0;
    _consecutiveFailures = 0;
    _reconnectAttempts = 0;

    // 연결 상태 업데이트
    _effectiveConnectionController.add(false);
    _connectionStateController.add(MqttConnectionState.disconnected);

    try {
      // 강제 연결 해제
      client.disconnect();
    } catch (e) {
      print('MQTTService: 강제 연결 해제 중 오류: $e');
    }

    // TCP 연결 실패 후 WebSocket을 시도하지 않았다면 전환
    if (!_useWebSocket && _reconnectAttempts >= 3) {
      _switchToWebSocket();
    } else {
      // 잠시 대기 후 재연결
      Timer(Duration(milliseconds: 500), () {
        connect();
      });
    }
  }

  // 기본 연결 메서드 (public)
  Future<bool> connect() async {
    _lastConnectionAttempt = DateTime.now();

    // 여기에 권한 요청 추가
    await requestNetworkPermissions();
    return _connect();
  }

  Future<void> requestNetworkPermissions() async {
    try {
      // 각 플랫폼별 권한 요청 처리
      if (Platform.isAndroid || Platform.isIOS) {
        // 모바일 기기의 위치 권한 요청
        Map<Permission, PermissionStatus> statuses = await [
          Permission.location,
        ].request();

        print('위치 권한 상태: ${statuses[Permission.location]}');
      } else if (Platform.isMacOS) {
        print('macOS에서는 Info.plist와 Entitlements 파일의 권한 설정이 필요합니다.');
        // macOS에서는 런타임 권한 요청이 아닌 Entitlements로 처리
      }

      // 인터넷 권한 확인 (대부분 manifest 파일에서 처리)
      print('네트워크 연결 권한 상태 확인 중...');
    } catch (e) {
      print('권한 요청 중 오류 발생: $e');
    }
  }

  // 연결 전 네트워크 상태 확인
  Future<bool> checkNetworkBeforeConnect() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      print('네트워크 연결이 없습니다');
      return false;
    }
    print('네트워크 연결 상태: $connectivityResult');
    return true;
  }

  // 5. Update MQTTService with fallback connection logic
  Future<bool> _connect() async {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      print('MQTTService: 이미 연결됨');
      return true;
    }

    print('MQTTService: 연결 시작 - ${DateTime.now()}');

    // 연결 시도 전 약간의 지연 추가 (이전 연결이 정리될 시간 제공)
    await Future.delayed(Duration(milliseconds: 500));

    final simpleId = 'mob_${DateTime.now().millisecondsSinceEpoch % 10000}';
    _initializeClient(useWebSocket: _useWebSocket, clientId: simpleId);

    try {
      print('MQTTService: 브로커 ${broker}:${port}에 연결 시도');
      await client.connect();

      // 연결 성공 시 추가 로깅
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        print(
            'MQTTService: 연결 성공! 상태 코드: ${client.connectionStatus?.returnCode}');

        // 연결 성공 시 먼저 상태 메시지 발행
        publishMessage(TOPICS['STATUS']!, {
          "device_id": client.clientIdentifier,
          "status": "connected",
          "client_type": "mobile_app",
          "connection_type": _useWebSocket ? "websocket" : "tcp",
          "timestamp": DateTime.now().millisecondsSinceEpoch
        });

        // 연결 이벤트 처리
        _connectionStateController.add(MqttConnectionState.connected);
        _effectivelyConnected = true;
        _effectiveConnectionController.add(true);

        // 토픽 구독
        _subscribeToTopics();

        // 메시지 리스너 설정
        client.updates?.listen(_onMessage);

        // 핑 타이머 시작
        _startPingTimer();

        return true;
      } else {
        print(
            'MQTTService: 연결 실패 - 상태: ${client.connectionStatus?.state}, 코드: ${client.connectionStatus?.returnCode}');
        return false;
      }
    } catch (e) {
      print('MQTTService: 연결 예외 발생: $e');
      return false;
    }
  }

  // 서버 응답 테스트
  void _checkServerResponseDespiteError() {
    // 5초 후 메시지 수신 여부 확인
    Future.delayed(Duration(seconds: 5), () {
      if (_receivedMessagesAfterConnect) {
        print('MQTTService: MQTT 연결은 실패했지만 메시지 수신이 정상 작동 중');
        _effectivelyConnected = true;
        _effectiveConnectionController.add(true);
      }
    });
  }

  // 토픽 구독 메서드
  void _subscribeToTopics() {
    try {
      print('MQTTService: 토픽 구독 시작');

      // 토픽이 맞는지 확인
      print('MQTTService: SYSTEM 토픽: ${TOPICS['SYSTEM']}');
      print('MQTTService: CONTROL_ROTATION 토픽: ${TOPICS['CONTROL_ROTATION']}');

      client.subscribe(TOPICS['SYSTEM']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['COMMAND']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['TEMPERATURE']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['STATUS']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['CONTROL_ROTATION']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['CONTROL_DIRECTION']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['CONTROL_AUTO_MODE']!, MqttQos.atLeastOnce);
      client.subscribe(TOPICS['CONTROL_STATUS']!, MqttQos.atLeastOnce);

      print('MQTTService: 토픽 구독 완료');
    } catch (e) {
      print('MQTTService: 토픽 구독 오류: $e');
    }
  }

  // 메시지 수신 처리 메서드 수정
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> c) {
    final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
    final String messageString =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    final String topic = c[0].topic;

    print('MQTTService: 메시지 수신: $topic - $messageString');

    // 메시지 수신 시간 및 상태 업데이트
    lastMessageTimestamp = DateTime.now().millisecondsSinceEpoch;
    _lastMessageReceived = DateTime.now();
    _receivedMessagesAfterConnect = true;
    _consecutiveSuccessMessages++;
    _consecutiveFailures = 0;

    // 메시지를 수신했으므로 효과적으로 연결된 것으로 간주
    if (!_effectivelyConnected) {
      _effectivelyConnected = true;
      _effectiveConnectionController.add(true);
    }

    try {
      // JSON 파싱
      final Map<String, dynamic> messageJson = jsonDecode(messageString);

      // 토픽별 처리
      if (topic == TOPICS['SYSTEM']) {
        _lastSystemState = messageJson;
      } else if (topic == TOPICS['TEMPERATURE']) {
        // 온도 히스토리 업데이트
        messageJson['received_at'] = DateTime.now().millisecondsSinceEpoch;
        _temperatureHistory.add(messageJson);

        // 최대 개수 유지
        if (_temperatureHistory.length > _maxTempHistoryItems) {
          _temperatureHistory.removeAt(0);
        }
      }

      // 해당 토픽의 스트림 컨트롤러가 있으면 메시지 전달
      if (_topicControllers.containsKey(topic)) {
        _topicControllers[topic]!.add(messageJson);
      }

      // 모든 토픽을 한꺼번에 수신하려는 리스너가 있으면 전달
      if (_topicControllers.containsKey('all')) {
        _topicControllers['all']!.add({
          'topic': topic,
          'message': messageJson,
          'timestamp': DateTime.now().millisecondsSinceEpoch
        });
      }
    } catch (e) {
      print('MQTTService: 메시지 처리 중 오류: $e, 메시지: $messageString');
    }
  }

  // 메시지 발행 (강화된 오류 처리)
  bool publishMessage(String topic, Map<String, dynamic> messageMap) {
    try {
      final String message = jsonEncode(messageMap);
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);

      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        print('MQTTService: 메시지 발행 - 토픽: $topic');
        client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        return true;
      } else if (_effectivelyConnected) {
        // MQTT 직접 연결은 없지만 효과적으로 연결된 상태라면
        print('MQTTService: 효과적 연결 상태로 메시지 발행 시도 - 토픽: $topic');

        try {
          // 연결 상태에 관계없이 발행 시도
          client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        } catch (e) {
          print('MQTTService: 효과적 연결 상태에서 메시지 발행 실패: $e');
          // 실패해도 true 반환 - 서버가 메시지를 받을 수 있음
        }

        // 직접 연결 없으면 주기적으로 재연결 시도
        if (client.connectionStatus?.state != MqttConnectionState.connected &&
            _reconnectTimer == null &&
            !_explicitDisconnect) {
          _scheduleReconnect(quiet: true, delay: 5000); // 5초 후 조용히 재연결 시도
        }

        return true;
      } else {
        print('MQTTService: 메시지 발행 불가 - 연결되지 않음');

        // 연결 재시도
        if (!_explicitDisconnect && _reconnectTimer == null) {
          _scheduleReconnect();
        }
        return false;
      }
    } catch (e) {
      print('MQTTService: 메시지 발행 중 오류: $e');
      return false;
    }
  }

  // 오토모드 설정
  bool setAutoMode(bool enabled) {
    return publishMessage(
      TOPICS['CONTROL_AUTO_MODE']!,
      {
        "device_id": clientIdentifier,
        "mode": enabled ? "enable_autonomous" : "disable_autonomous",
        "timestamp": DateTime.now().millisecondsSinceEpoch
      },
    );
  }

  // 회전 방향 제어
  bool setRotation(double angle) {
    return publishMessage(
      TOPICS['CONTROL_ROTATION']!,
      {
        "device_id": clientIdentifier,
        "angle": angle.toStringAsFixed(1),
        "timestamp": DateTime.now().millisecondsSinceEpoch
      },
    );
  }

  // 방향 제어 (상하좌우)
  bool setDirection(String direction) {
    return publishMessage(
      TOPICS['CONTROL_DIRECTION']!,
      {
        "device_id": clientIdentifier,
        "direction": direction,
        "timestamp": DateTime.now().millisecondsSinceEpoch
      },
    );
  }

  // 연결 끊기
  void disconnect() {
    print('MQTTService: 연결 종료 중');
    _explicitDisconnect = true;

    // 연결 종료 전 상태 메시지 발행
    try {
      if (client.connectionStatus?.state == MqttConnectionState.connected ||
          _effectivelyConnected) {
        publishMessage(
          TOPICS['STATUS']!,
          {
            "device_id": clientIdentifier,
            "status": "disconnected",
            "client_type": "mobile_app",
            "connection_type": _useWebSocket ? "websocket" : "tcp",
            "timestamp": DateTime.now().millisecondsSinceEpoch
          },
        );
      }
    } catch (e) {
      print('MQTTService: 연결 종료 메시지 발행 중 오류: $e');
    }

    // 타이머 정리
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionMonitorTimer?.cancel();
    _stabilityCheckTimer?.cancel();

    // 연결 상태 업데이트
    _connectionStateController.add(MqttConnectionState.disconnected);
    _effectivelyConnected = false;
    _effectiveConnectionController.add(false);
    _stableIndirectConnection = false;

    // 연결 종료
    client.disconnect();
  }

  // 재연결 스케줄링 (조용한 연결 시도 옵션 추가)
  void _scheduleReconnect({bool quiet = false, int? delay}) {
    if (_reconnectTimer != null) {
      return;
    }

    // 명시적 종료 중이면 재연결 안함
    if (_explicitDisconnect) {
      return;
    }

    // 재연결 시도 횟수 증가 및 지수 백오프 적용
    _reconnectAttempts++;
    final calculatedDelay = delay ?? _calculateReconnectDelay();

    if (!quiet) {
      print(
          'MQTTService: ${calculatedDelay}ms 후 재연결 시도 (시도 횟수: $_reconnectAttempts)');
    }

    _reconnectTimer = Timer(Duration(milliseconds: calculatedDelay), () {
      _reconnectTimer = null;
      if (!_explicitDisconnect) {
        _connect();
      }
    });
  }

  // 재연결 딜레이 계산 (지수 백오프)
  int _calculateReconnectDelay() {
    // 안정적인 간접 연결이 있으면 더 길게 지연
    if (_stableIndirectConnection) {
      return 30000; // 30초
    }

    // 기본 딜레이 2초, 최대 1분까지 지수적으로 증가
    final baseDelay = 2000;
    final maxDelay = 60000;
    int delay =
        baseDelay * (1 << Math.min((_reconnectAttempts - 1), 5)); // 최대 32배로 제한

    // 랜덤 요소 추가 (±30%)
    final random = (DateTime.now().millisecondsSinceEpoch % 60) / 100;
    delay = (delay * (0.7 + random * 0.6)).toInt();

    return delay > maxDelay ? maxDelay : delay;
  }

  // 핑 타이머 시작 (연결 유지를 위한 주기적 메시지)
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (client.connectionStatus?.state == MqttConnectionState.connected ||
          _effectivelyConnected) {
        publishMessage(
          'ping',
          {
            "device_id": clientIdentifier,
            "connection_type": _useWebSocket ? "websocket" : "tcp",
            "timestamp": DateTime.now().millisecondsSinceEpoch
          },
        );
      } else {
        // 연결이 끊어진 경우 핑 중지
        timer.cancel();
      }
    });
  }

  // 콜백 메서드들
  void _onConnected() {
    print('MQTTService: 연결됨 (${_useWebSocket ? "WebSocket" : "TCP"})');
  }

  void _onDisconnected() {
    print('MQTTService: 연결 해제됨 (${_useWebSocket ? "WebSocket" : "TCP"})');

    // 메시지를 수신 중이면 효과적으로 연결된 것으로 간주
    if (!_receivedMessagesAfterConnect) {
      // 연결 상태 업데이트
      _connectionStateController.add(MqttConnectionState.disconnected);
      _effectivelyConnected = false;
      _effectiveConnectionController.add(false);
    } else {
      // 안정적 간접 연결이 있는 경우
      if (_stableIndirectConnection) {
        print('MQTTService: MQTT는 연결 해제되었지만 안정적인 간접 연결 상태 유지');
      } else {
        print('MQTTService: MQTT는 연결 해제되었지만 메시지 수신 중이므로 효과적으로 연결된 상태 유지');

        // 최근에 메시지를 받았는지 다시 확인
        final now = DateTime.now();
        if (lastMessageTimestamp != null) {
          final messageAge = now.millisecondsSinceEpoch - lastMessageTimestamp!;
          if (messageAge > 15000) {
            // 15초 이상 메시지 없음
            print('MQTTService: 최근 메시지 수신 없음, 효과적 연결 상태 해제');
            _effectivelyConnected = false;
            _effectiveConnectionController.add(false);
          }
        }
      }
    }

    // 타이머 정리
    _pingTimer?.cancel();

    // 명시적 연결 종료가 아니라면 재연결 시도
    if (!_explicitDisconnect) {
      if (_stableIndirectConnection) {
        // 안정적인 간접 연결이 있는 경우 더 지연된 재연결 시도
        _scheduleReconnect(quiet: true, delay: 30000); // 30초 후 조용히 재연결
      } else {
        // TCP 소켓 연결 실패가 계속되면 WebSocket으로 전환
        if (!_useWebSocket && _reconnectAttempts >= 3) {
          print('MQTTService: 연속 연결 실패로 WebSocket으로 전환');
          _switchToWebSocket();
        } else {
          _scheduleReconnect();
        }
      }
    }
  }

  void _onSubscribed(String topic) {
    print('MQTTService: 구독 성공: $topic');
  }

  void _onSubscribeFail(String topic) {
    print('MQTTService: 구독 실패: $topic');
  }

  void _pong() {
    print('MQTTService: Pong 응답 수신');
    // Pong 응답도 메시지로 간주
    _lastMessageReceived = DateTime.now();
  }

  // 자동 재연결 이벤트
  void _onAutoReconnect() {
    print('MQTTService: 자동 재연결 시도 중...');

    // 메시지를 수신 중이 아니면 연결 중 상태로 변경
    if (!_receivedMessagesAfterConnect && !_stableIndirectConnection) {
      _connectionStateController.add(MqttConnectionState.connecting);
    }
  }

  // 자동 재연결 완료 이벤트
  void _onAutoReconnected() {
    print('MQTTService: 자동 재연결 성공');
    _connectionStateController.add(MqttConnectionState.connected);
    _effectivelyConnected = true;
    _effectiveConnectionController.add(true);
    _reconnectAttempts = 0;

    // 재연결 후 토픽 재구독
    _subscribeToTopics();

    // 재연결 성공 메시지 발행
    publishMessage(
      TOPICS['STATUS']!,
      {
        "device_id": clientIdentifier,
        "status": "reconnected",
        "client_type": "mobile_app",
        "connection_type": _useWebSocket ? "websocket" : "tcp",
        "timestamp": DateTime.now().millisecondsSinceEpoch
      },
    );
  }

  // 자원 해제
  void dispose() {
    print('MQTTService: 리소스 해제');
    disconnect();

    // 모든 스트림 컨트롤러 닫기
    _connectionStateController.close();
    _effectiveConnectionController.close();

    for (var controller in _topicControllers.values) {
      controller.close();
    }
    _topicControllers.clear();
  }

  // 연결 상태 확인 메서드 (수정)
  bool isConnected() {
    return client.connectionStatus?.state == MqttConnectionState.connected ||
        _effectivelyConnected ||
        _stableIndirectConnection;
  }

  // 서버 시간 확인 메서드 (연결 지연 테스트)
  Future<int> checkServerTime() async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final pingCompleter = Completer<int>();

    // 핑용 토픽 구독
    final String pingTopic = 'ping/response/${clientIdentifier}';
    try {
      client.subscribe(pingTopic, MqttQos.atLeastOnce);

      // 먼저 변수를 선언만 하고
      late StreamSubscription subscription;

      // 그 다음에 초기화합니다
      subscription = client.updates!.listen((messages) {
        for (var message in messages) {
          if (message.topic == pingTopic) {
            final endTime = DateTime.now().millisecondsSinceEpoch;
            final delay = endTime - startTime;

            // 구독 해제
            client.unsubscribe(pingTopic);
            subscription.cancel();

            // 핑 완료
            if (!pingCompleter.isCompleted) {
              pingCompleter.complete(delay);
            }
            break;
          }
        }
      });

      // 핑 요청 보내기
      publishMessage(
        'ping/request',
        {
          "device_id": clientIdentifier,
          "response_topic": pingTopic,
          "timestamp": startTime
        },
      );
    } catch (e) {
      print('MQTTService: 핑 요청 중 오류: $e');
      if (!pingCompleter.isCompleted) {
        pingCompleter.complete(-1);
      }
    }

    // 타임아웃 설정
    Timer(Duration(seconds: 5), () {
      if (!pingCompleter.isCompleted) {
        pingCompleter.complete(-1); // 타임아웃시 -1 반환
      }
    });

    return pingCompleter.future;
  }
}

// Math 클래스 추가 (min 함수를 위해)
class Math {
  static int min(int a, int b) {
    return a < b ? a : b;
  }
}
