import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'dart:io' show Platform;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import './shared_prefs_service.dart';
import './mqtt_service.dart';
import 'package:lottie/lottie.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ]).then((_) {
    // 애니메이션이 표시될 시간을 위해 약간의 지연 추가 (선택 사항)
    // 실제 초기화에 시간이 걸리면 이 부분은 필요 없을 수 있습니다
    Future.delayed(Duration(milliseconds: 1500), () {
      runApp(MyApp());
    });
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI FAN Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true, // Material 3 스타일 사용
      ),
      home: AppStartScreen(),
      debugShowCheckedModeBanner: false, // 디버그 배너 제거
    );
  }
}

// 앱 시작 화면 - IP가 저장되어 있는지 확인하고 분기 처리
class AppStartScreen extends StatefulWidget {
  @override
  _AppStartScreenState createState() => _AppStartScreenState();
}

class _AppStartScreenState extends State<AppStartScreen> {
  bool _isLoading = true;
  String? _savedIp;

  @override
  void initState() {
    super.initState();
    _checkSavedIp();
  }

  // 저장된 IP 확인
  Future<void> _checkSavedIp() async {
    final savedIp = await SharedPrefsService.getBrokerIp();
    setState(() {
      _savedIp = savedIp;
      _isLoading = false;
    });
  }

  // IP 저장 후 컨트롤러 화면으로 이동
  void _onIpSaved(String ip) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => ControllerView(brokerIp: ip)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/loading.json',
                repeat: true,
                animate: true,
                onLoaded: (composition) {
                  print("로티 애니메이션 로드 성공!");
                },
                errorBuilder: (context, error, stackTrace) {
                  print("로티 애니메이션 로드 실패: $error");
                  // 에러 발생 시 기본 CircularProgressIndicator 표시
                  return CircularProgressIndicator();
                },
              ),
              SizedBox(height: 20),
              Text('AI FAN 시스템 초기화 중...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // 저장된 IP가 없으면 IP 입력 화면, 있으면 컨트롤러 화면
    if (_savedIp == null || _savedIp!.isEmpty) {
      return IpInputScreen(onIpSaved: _onIpSaved);
    } else {
      return ControllerView(brokerIp: _savedIp!);
    }
  }
}

// IP 입력 화면
class IpInputScreen extends StatefulWidget {
  final Function(String) onIpSaved;

  IpInputScreen({required this.onIpSaved});

  @override
  _IpInputScreenState createState() => _IpInputScreenState();
}

class _IpInputScreenState extends State<IpInputScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isValidIp = false;
  bool _isSaving = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // 이전에 저장된 IP가 있다면 불러오기
    _loadSavedIp();
  }

  // 저장된 IP 로드
  Future<void> _loadSavedIp() async {
    final savedIp = await SharedPrefsService.getBrokerIp();
    if (savedIp.isNotEmpty) {
      setState(() {
        _ipController.text = savedIp;
        _validateIp(savedIp);
      });
    }
  }

  // IP 유효성 검사
  void _validateIp(String value) {
    if (value.isEmpty) {
      setState(() {
        _isValidIp = false;
        _errorMessage = '';
      });
      return;
    }

    // 간단한 IP 형식 검사 (점이 있는 숫자 형식)
    final RegExp ipRegex = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    );

    if (!ipRegex.hasMatch(value)) {
      setState(() {
        _isValidIp = false;
        _errorMessage = '올바른 IP 주소 형식이 아닙니다';
      });
      return;
    }

    // 각 숫자는 0-255 범위 내에 있어야 함
    final parts = value.split('.');
    for (final part in parts) {
      final intPart = int.tryParse(part);
      if (intPart == null || intPart < 0 || intPart > 255) {
        setState(() {
          _isValidIp = false;
          _errorMessage = 'IP 주소의 각 부분은 0-255 범위여야 합니다';
        });
        return;
      }
    }

    setState(() {
      _isValidIp = true;
      _errorMessage = '';
    });
  }

  // IP 저장 및 앱 시작
  Future<void> _saveIpAndStart() async {
    if (!_isValidIp) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final ip = _ipController.text.trim();
      await SharedPrefsService.saveBrokerIp(ip);
      widget.onIpSaved(ip);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = '설정을 저장하는 중 오류가 발생했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI FAN 서버 연결 설정'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.router,
                  size: 64,
                  color: Colors.blue,
                ),
                SizedBox(height: 24),
                Text(
                  'MQTT 브로커 IP 주소 입력',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'AI FAN 시스템에 연결하기 위한 서버의 IP 주소를 입력하세요.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                TextField(
                  controller: _ipController,
                  decoration: InputDecoration(
                    labelText: 'MQTT 브로커 IP',
                    hintText: '예: 192.168.104.223',
                    prefixIcon: Icon(Icons.lan),
                    border: OutlineInputBorder(),
                    errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: _validateIp,
                  enabled: !_isSaving,
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isValidIp && !_isSaving ? _saveIpAndStart : null,
                  child: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('연결하기'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                SizedBox(height: 16),
                TextButton(
                  onPressed: !_isSaving
                      ? () {
                          setState(() {
                            _ipController.text = '192.168.104.223';
                            _validateIp('192.168.104.223');
                          });
                        }
                      : null,
                  child: Text('기본값 사용 (192.168.104.223)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }
}

// 컨트롤러 메인 화면
class ControllerView extends StatefulWidget {
  final String brokerIp;

  ControllerView({required this.brokerIp});

  @override
  _ControllerViewState createState() => _ControllerViewState();
}

class _ControllerViewState extends State<ControllerView>
    with WidgetsBindingObserver {
  // 회전 및 제어 상태
  double rotationAngle = 0.0;
  bool isAutoMode = false;
  String currentDirection = "none";

  // MQTT 서비스 및 연결 상태
  late MQTTService mqttService;
  bool isConnected = false;
  bool isEffectivelyConnected = false;
  bool isStableIndirectConnection = false; // 추가: 안정적 간접 연결 상태
  String connectionStatus = "연결 중...";
  String lastMessage = "";

  // 시스템 상태 정보
  String systemState = "unknown";
  double currentTemperature = 0.0;
  String lastUpdateTime = "";

  // 선풍기 전원 상태
  bool fanPowerOn = false;

  // 타이머 및 구독
  Timer? _statusUpdateTimer;
  Timer? _reconnectTimer;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _effectiveConnectionSubscription;
  StreamSubscription? _systemStatusSubscription;
  StreamSubscription? _temperatureSubscription;
  StreamSubscription? _deviceStatusSubscription;

  // 연결 복구 관련 변수
  int _connectionLossCount = 0;
  DateTime _lastConnectionLoss = DateTime.now();
  bool _isRecovering = false;

  // 초기화 상태
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool isUsingWebSocket = false;

  // 마지막 메시지 시간
  int _lastServerMessageTime = 0;

  // ControllerView 클래스 내부에 추가할 변수
  bool _isMenuExpanded = false;

  // 전역적인 명령 발행 제한 (추가)
  bool _isCommandInProgress = false;
  int _lastGlobalCommandTime = 0;

  // 중복 방지 변수들 (추가)
  String _lastFanRotationCommand = "";
  int _lastFanRotationTime = 0;
  String _lastMovementCommand = "";
  int _lastMovementTime = 0;
  
  // 전용 플래그 변수들 (추가)
  bool _isFanRotationInProgress = false;
  bool _isMovementInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMqttService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;

    print('앱 라이프사이클 상태 변경: $state');

    // 앱이 백그라운드로 전환될 때
    if (state == AppLifecycleState.paused) {
      // 자동 모드 아닌 경우 연결 끊기
      if (!isAutoMode && (isConnected || isEffectivelyConnected)) {
        mqttService.disconnect();
      }
    }
    // 앱이 다시 포그라운드로 돌아올 때
    else if (state == AppLifecycleState.resumed) {
      // 연결이 끊어져 있다면 재연결
      if (!isConnected && !isEffectivelyConnected) {
        _reconnectToMqttBroker();
      }
    }
  }

  // MQTT 서비스 초기화
  Future<void> _initializeMqttService() async {
    // 고유한 클라이언트 ID를 한 번만 생성하여 재사용
    // 저장된 값이 있으면 그대로 사용, 없으면 새로 생성 후 저장
    String clientId = await SharedPrefsService.getClientId();

    mqttService = MQTTService(
      broker: widget.brokerIp,
      port: 1883, // TCP 포트
      wsPort: 8883, // WebSocket 포트 추가
      clientIdentifier: clientId,
      username: 'aifan',
      password: 'aifan',
      useTLS: false,
    );

    setState(() {
      connectionStatus = "MQTT 브로커에 연결 중...";
    });

    // 연결 상태 변화 구독
    _connectionSubscription = mqttService.connectionStateStream.listen((state) {
      if (_isDisposed) return;

      setState(() {
        // MQTT 직접 연결 상태
        isConnected = state == MqttConnectionState.connected;
        isUsingWebSocket = mqttService.usingWebSocket;
        _updateConnectionStatusUI();
      });

      // 연결되면 시스템 상태 구독 시작
      if (state == MqttConnectionState.connected) {
        _subscribeToTopics();
        _startStatusUpdateTimer();

        // 연결 복구 상태 리셋
        _connectionLossCount = 0;
        _isRecovering = false;
      }
    });

    // 효과적 연결 상태 변화 구독
    _effectiveConnectionSubscription =
        mqttService.effectiveConnectionStream.listen((effective) {
      if (_isDisposed) return;

      setState(() {
        isEffectivelyConnected = effective;
        isStableIndirectConnection = mqttService.stableIndirectConnection;
        isUsingWebSocket = mqttService.usingWebSocket;
        _updateConnectionStatusUI();

        // 효과적 연결이 되었을 때 토픽 구독 시작
        if (effective && !_isRecovering) {
          if (!isConnected) {
            _subscribeToTopics();
            _startStatusUpdateTimer();
          }

          // 연결 복구 상태 리셋
          _connectionLossCount = 0;
          _isRecovering = false;
        } else if (!effective && !isConnected) {
          _handleConnectionLoss();
        }
      });
    });

    // 초기 연결 시도
    await _reconnectToMqttBroker();

    setState(() {
      _isInitialized = true;
    });
  }

  // 연결 상태 UI 업데이트
  void _updateConnectionStatusUI() {
    if (isConnected) {
      connectionStatus = isUsingWebSocket ? 'WebSocket 연결됨' : '연결됨';
    } else if (isEffectivelyConnected) {
      connectionStatus = isStableIndirectConnection ? '안정적 간접 연결' : '간접 연결됨';
    } else if (_isRecovering) {
      connectionStatus = '연결 복구 중...';
    } else {
      connectionStatus = '연결 끊김';
    }
  }

  // 연결 끊김 처리
  void _handleConnectionLoss() {
    _connectionLossCount++;
    _lastConnectionLoss = DateTime.now();

    // 3회 이상 연속으로 연결이 끊기면 강제 재연결 시도
    if (_connectionLossCount >= 3 && !_isRecovering) {
      _isRecovering = true;
      setState(() {
        connectionStatus = '연결 복구 중...';
      });

      // 잠시 대기 후 재연결 시도
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: 3), () {
        _reconnectTimer = null;
        _reconnectToMqttBroker(forceReconnect: true);
      });
    } else {
      _scheduleReconnect();
    }
  }

  // 토픽 구독
  void _subscribeToTopics() {
    // 시스템 상태 토픽 구독
    _systemStatusSubscription?.cancel();
    _systemStatusSubscription = mqttService
        .getTopicStream(MQTTService.TOPICS['SYSTEM']!)
        .listen((data) {
      if (_isDisposed) return;

      setState(() {
        systemState = data['state'] ?? 'unknown';
        _lastServerMessageTime = DateTime.now().millisecondsSinceEpoch;

        // 서버로부터 자동 모드 상태 확인 응답 처리 (최적화된 빠른 처리)
        if (data.containsKey('auto_mode_response')) {
          final serverAutoMode = data['auto_mode'] ?? false;
          final responseRequestId = data['request_id']?.toString();
          
          print('=== AUTO MODE RESPONSE RECEIVED (FAST) ===');
          print('Server Auto Mode: $serverAutoMode');
          print('Response Request ID: $responseRequestId');
          print('Expected Request ID: $_lastAutoModeRequestId');
          print('UI Auto Mode: $isAutoMode');
          print('========================================');
          
          // 응답이 오면 즉시 토글 상태 해제 (빠른 피드백)
          if (_isTogglingAutoMode) {
            _isTogglingAutoMode = false;
            print('✅ Auto mode toggle completed successfully');
          }
          
          // 서버 상태와 UI 상태 동기화 (불일치 시에만 업데이트)
          if (isAutoMode != serverAutoMode) {
            isAutoMode = serverAutoMode;
            print('🔄 Auto mode synced with server: $serverAutoMode');
          }
          
          _lastAutoModeRequestId = null; // 요청 ID 초기화
        } 
        // 일반적인 상태 업데이트에 따른 자동 모드 상태 동기화 (토글 중이 아닐 때만)
        else if (!_isTogglingAutoMode) {
          if (systemState == 'measuring' || systemState == 'rotating') {
            if (!isAutoMode) {
              isAutoMode = true;
              print('Auto mode activated by system state: $systemState');
            }
          } else if (systemState == 'idle') {
            if (isAutoMode) {
              isAutoMode = false;
              print('Auto mode deactivated by system state: $systemState');
            }
          }
        }

        lastUpdateTime = _formatTimestamp(data['timestamp']);

        // 연결 상태도 업데이트
        if (!isConnected && !isEffectivelyConnected) {
          isEffectivelyConnected = true;
          _updateConnectionStatusUI();
        }
      });
    });

    // 중요: 장치 상태 토픽 구독 (device/status)
    _deviceStatusSubscription?.cancel();
    _deviceStatusSubscription = mqttService
        .getTopicStream(MQTTService.TOPICS['STATUS']!)
        .listen((data) {
      if (_isDisposed) return;

      _lastServerMessageTime = DateTime.now().millisecondsSinceEpoch;

      // 서버 컨트롤러 상태 업데이트 확인
      if (data['device_id'] == 'server_controller') {
        setState(() {
          // 서버 상태 수신 시 항상 연결된 것으로 간주
          if (!isEffectivelyConnected) {
            isEffectivelyConnected = true;
            _updateConnectionStatusUI();
          }
        });
      }
    });

    // 온도 데이터 토픽 구독
    _temperatureSubscription?.cancel();
    _temperatureSubscription = mqttService
        .getTopicStream(MQTTService.TOPICS['TEMPERATURE']!)
        .listen((data) {
      if (_isDisposed) return;

      _lastServerMessageTime = DateTime.now().millisecondsSinceEpoch;

      final temp = data['temperature'];
      if (temp != null) {
        setState(() {
          currentTemperature = double.tryParse(temp.toString()) ?? 0.0;

          // 메시지 수신 시 연결 상태 업데이트
          if (!isConnected && !isEffectivelyConnected) {
            isEffectivelyConnected = true;
            _updateConnectionStatusUI();
          }
        });
      }
    });

    // 선풍기 상태 토픽 구독
    mqttService.getTopicStream('device/fan/status').listen((data) {
      if (_isDisposed) return;
      
      _lastServerMessageTime = DateTime.now().millisecondsSinceEpoch;
      
      setState(() {
        fanPowerOn = data['power_on'] ?? false;
        
        // 메시지 수신 시 연결 상태 업데이트
        if (!isConnected && !isEffectivelyConnected) {
          isEffectivelyConnected = true;
          _updateConnectionStatusUI();
        }
      });
    });
  }

  // 상태 타이머 시작 (상태 아이콘 업데이트 및 연결 모니터링)
  void _startStatusUpdateTimer() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      final currentTime = DateTime.now().millisecondsSinceEpoch;

      // MQTT 클라이언트가 아직 연결되어 있는지 확인
      final mqttConnected = mqttService.isConnected();

      // 서버에서 최근 메시지를 받았는지 확인 (20초 이내)
      final hasRecentServerMessages = _lastServerMessageTime > 0 &&
          (currentTime - _lastServerMessageTime < 20000);

      // 클라이언트에서 최근 메시지를 받았는지 확인
      final hasRecentClientMessages =
          mqttService.lastMessageTimestamp != null &&
              (currentTime - mqttService.lastMessageTimestamp! < 20000);

      final isStableMode = mqttService.stableIndirectConnection;

      setState(() {
        // 연결 상태 확인
        final wasConnected = isConnected || isEffectivelyConnected;

        // 직접 MQTT 연결 확인
        isConnected =
            mqttService.connectionState == MqttConnectionState.connected;

        // 효과적 연결 확인 (더 신뢰할 수 있는 메서드 사용)
        isEffectivelyConnected = mqttConnected ||
            hasRecentServerMessages ||
            hasRecentClientMessages ||
            mqttService.effectivelyConnected;

        // 안정적 간접 연결 상태 업데이트
        isStableIndirectConnection = isStableMode;

        // 연결 상태 텍스트 업데이트
        _updateConnectionStatusUI();

        // 이전에 연결되어 있었는데 연결이 끊어진 경우
        if (wasConnected &&
            !isConnected &&
            !isEffectivelyConnected &&
            !_isRecovering) {
          _handleConnectionLoss();
        }
      });
    });
  }

  // 재연결 스케줄링
  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    _reconnectTimer = Timer(Duration(seconds: 5), () {
      _reconnectTimer = null;
      if (!_isDisposed && !isConnected && !isEffectivelyConnected) {
        _reconnectToMqttBroker();
      }
    });
  }

  // 재연결
  Future<void> _reconnectToMqttBroker({bool forceReconnect = false}) async {
    if (_isDisposed) return;

    setState(() {
      connectionStatus = "MQTT 브로커에 연결 중...";
    });

    bool connected = false;

    // 강제 재연결이 필요한 경우
    if (forceReconnect) {
      // 기존 구독 정리
      _systemStatusSubscription?.cancel();
      _deviceStatusSubscription?.cancel();
      _temperatureSubscription?.cancel();

      // 서비스 자체를 재초기화하는 방식을 사용해 볼 수 있음
      String clientId = await SharedPrefsService.getClientId();
      mqttService = MQTTService(
        broker: widget.brokerIp,
        port: 1883,
        clientIdentifier: clientId,
        username: 'AIFAN',
        password: 'AIFAN',
        useTLS: false,
      );

      // 구독 재설정
      _connectionSubscription?.cancel();
      _effectiveConnectionSubscription?.cancel();

      _connectionSubscription =
          mqttService.connectionStateStream.listen((state) {
        if (_isDisposed) return;
        setState(() {
          isConnected = state == MqttConnectionState.connected;
          _updateConnectionStatusUI();
        });
        if (state == MqttConnectionState.connected) {
          _subscribeToTopics();
          _startStatusUpdateTimer();
          _isRecovering = false;
        }
      });

      _effectiveConnectionSubscription =
          mqttService.effectiveConnectionStream.listen((effective) {
        if (_isDisposed) return;
        setState(() {
          isEffectivelyConnected = effective;
          isStableIndirectConnection = mqttService.stableIndirectConnection;
          _updateConnectionStatusUI();
        });
        if (effective && !isConnected) {
          _subscribeToTopics();
          _startStatusUpdateTimer();
          _isRecovering = false;
        }
      });
    }

    // 연결 시도
    try {
      connected = await mqttService.connect();
    } catch (e) {
      print('연결 시도 중 예외 발생: $e');
      // 오류가 발생해도 계속 진행
    }

    if (_isDisposed) return;

    setState(() {
      isConnected =
          mqttService.connectionState == MqttConnectionState.connected;
      isEffectivelyConnected = connected || mqttService.effectivelyConnected;
      isStableIndirectConnection = mqttService.stableIndirectConnection;

      _updateConnectionStatusUI();

      // 여전히 연결이 안 되면 재시도 예약
      if (!isConnected && !isEffectivelyConnected && !_isRecovering) {
        _scheduleReconnect();
      } else {
        _isRecovering = false;
      }
    });
  }

  // 타임스탬프 포맷팅
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '-';

    try {
      final int ts = int.parse(timestamp.toString());
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return '-';
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // 타이머 해제
    _statusUpdateTimer?.cancel();
    _reconnectTimer?.cancel();
    _autoModeDebounceTimer?.cancel();

    // 자동 모드 토글 상태 정리
    _isTogglingAutoMode = false;
    _lastAutoModeRequestId = null;

    // 중복 방지 변수 초기화
    _lastFanRotationCommand = "";
    _lastFanRotationTime = 0;
    _lastMovementCommand = "";
    _lastMovementTime = 0;
    
    // 전용 플래그 변수 초기화
    _isFanRotationInProgress = false;
    _isMovementInProgress = false;
    
    // 전역적인 명령 발행 제한 변수 초기화
    _isCommandInProgress = false;
    _lastGlobalCommandTime = 0;

    // 구독 해제
    _connectionSubscription?.cancel();
    _effectiveConnectionSubscription?.cancel();
    _systemStatusSubscription?.cancel();
    _temperatureSubscription?.cancel();
    _deviceStatusSubscription?.cancel();

    // MQTT 서비스 해제
    mqttService.dispose();

    super.dispose();
  }

  // 조이스틱 이동 처리 (선풍기 회전용) - 중복 방지 로직 포함
  void onJoystickMove(String direction) {
    if (!(isConnected || isEffectivelyConnected) || isAutoMode) return;

    // 방향에 따라 모터 속도 값 설정 (절대값)
    int motorSpeed = 0;
    String motorDirection = "center";
    
    switch (direction) {
      case "left":
        motorDirection = "left";
        motorSpeed = 50; // 절대값
        break;
      case "right":
        motorDirection = "right";
        motorSpeed = 50; // 절대값
        break;
      case "center":
      case "stop":
      default:
        motorDirection = "center";
        motorSpeed = 0;
        break;
    }

    // 선풍기 회전 제어 명령 발행 (중복 방지 적용)
    _publishFanRotation(motorDirection, motorSpeed, DateTime.now().millisecondsSinceEpoch);
  }

  // 방향 버튼 처리 (선풍기 회전 + 이동 통합) - 개선된 버전
  void onDirectionPressed(String direction) {
    if (!(isConnected || isEffectivelyConnected) || isAutoMode) return;

    setState(() {
      currentDirection = direction;
    });

    // 방향에 따라 적절한 토픽만 발행하도록 개선
    _handleDirectionCommand(direction);
  }

  // 방향 명령 처리 로직 - 바퀴 이동만 제어
  void _handleDirectionCommand(String direction) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // 방향 제어는 오직 바퀴 이동만 담당 (선풍기 회전 제외)
    _publishMovementCommand(_mapDirectionToMovement(direction), timestamp);
  }

   void _publishFanRotation(String direction, int speed, int timestamp) {
    mqttService.publishMessage('control/fan/rotation', {
      "device_id": mqttService.clientIdentifier,
      "action": "set_direction",
      "direction": direction,
      "speed": speed,
      "timestamp": timestamp
    });

    print('Fan rotation command sent - Direction: $direction, Speed: $speed');
  }

    void _publishMovementCommand(String direction, int timestamp) {
    mqttService.publishMessage('control/movement', {
      "device_id": mqttService.clientIdentifier,
      "action": "move",
      "direction": direction,
      "timestamp": timestamp
    });

    print('Movement command sent - Direction: $direction');
  }

  // 방향을 이동 명령으로 매핑하는 헬퍼 함수
  String _mapDirectionToMovement(String direction) {
    switch (direction) {
      case "up":
        return "forward";
      case "down":
        return "backward";  // stop에서 backward로 수정
      case "left":
        return "left";
      case "right":
        return "right";
      case "center":
      case "stop":
      default:
        return "stop";
    }
  }

  // 자동 모드 토글 상태 관리
  bool _isTogglingAutoMode = false;
  Timer? _autoModeDebounceTimer;
  String? _lastAutoModeRequestId;

  // 자동 모드 토글 (최적화된 빠른 응답)
  void toggleAutoMode() {
    if (!(isConnected || isEffectivelyConnected)) return;
    
    // 이미 토글 중이면 무시
    if (_isTogglingAutoMode) {
      print('Auto mode toggle already in progress, ignoring duplicate request');
      return;
    }

    // 디바운싱 시간을 대폭 단축 (200ms)
    _autoModeDebounceTimer?.cancel();
    _autoModeDebounceTimer = Timer(Duration(milliseconds: 200), () {
      _performAutoModeToggle();
    });
  }

  void _performAutoModeToggle() {
    // 다시 한 번 토글 상태 확인
    if (_isTogglingAutoMode) {
      print('Auto mode toggle still in progress, skipping');
      return;
    }
    
    final newAutoMode = !isAutoMode;
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    
    print('=== AUTO MODE TOGGLE REQUEST (OPTIMIZED) ===');
    print('Target Mode: ${newAutoMode ? "AUTO" : "MANUAL"}');
    print('Request ID: $requestId');
    print('Current State: ${isAutoMode ? "AUTO" : "MANUAL"}');
    print('===========================================');

    // UI 즉시 업데이트 (낙관적 업데이트)
    setState(() {
      _isTogglingAutoMode = true;
      isAutoMode = newAutoMode;
    });

    _lastAutoModeRequestId = requestId;

    // 메시지 발행 (비동기로 처리하여 UI 블로킹 방지)
    Future.microtask(() async {
      bool messageSent = mqttService.publishMessage('control/auto_mode', {
        "device_id": mqttService.clientIdentifier,
        "auto_mode": newAutoMode,
        "action": newAutoMode ? "enable_autonomous_mode" : "disable_autonomous_mode",
        "request_id": requestId,
        "timestamp": DateTime.now().millisecondsSinceEpoch
      });

      if (!messageSent) {
        print('Failed to send auto mode message - reverting UI');
        // 메시지 전송 실패 시 UI 되돌리기
        if (mounted && _lastAutoModeRequestId == requestId) {
          setState(() {
            isAutoMode = !newAutoMode; // 원래 상태로 되돌리기
            _isTogglingAutoMode = false;
          });
        }
        return;
      }
      
      print('✅ Auto mode request sent successfully');
    });

    // 타임아웃을 3초로 단축 (빠른 피드백)
    Timer(Duration(seconds: 3), () {
      if (_isTogglingAutoMode && _lastAutoModeRequestId == requestId) {
        setState(() {
          _isTogglingAutoMode = false;
        });
        print('Auto mode toggle timeout (3s) - assuming success for request: $requestId');
      }
    });
  }

  // 선풍기 전원 토글
  void toggleFanPower() {
    if (!(isConnected || isEffectivelyConnected)) return;

    final newPowerState = !fanPowerOn;
    setState(() {
      fanPowerOn = newPowerState;
    });

    mqttService.publishMessage('control/fan/power', {
      "device_id": mqttService.clientIdentifier,
      "action": newPowerState ? "power_on" : "power_off",
      "power_state": newPowerState,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    });

    print('Fan power command sent: ${newPowerState ? "ON" : "OFF"}');
  }

  // IP 초기화 및 IP 입력 화면으로 돌아가기
  Future<void> _resetIpSettings() async {
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('IP 설정 초기화'),
            content: Text('MQTT 브로커 IP 설정을 초기화하시겠습니까?\n초기화 후 앱이 재시작됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('초기화'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await SharedPrefsService.resetBrokerIp();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => AppStartScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text('AI FAN Controller'),
            leading: IconButton(
              icon: Icon(_isMenuExpanded ? Icons.menu_open : Icons.menu),
              onPressed: () {
                setState(() {
                  _isMenuExpanded = !_isMenuExpanded;
                });
              },
            ),
            actions: [
              // 재연결 버튼 (문제 발생 시)
              if (_connectionLossCount > 0 &&
                  !isConnected &&
                  !isEffectivelyConnected &&
                  !_isRecovering)
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.orange),
                  tooltip: '연결 복구 시도',
                  onPressed: () {
                    setState(() {
                      _isRecovering = true;
                      connectionStatus = '연결 복구 중...';
                    });
                    _reconnectToMqttBroker(forceReconnect: true);
                  },
                ),

              // 연결 상태 표시
              Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green.shade700
                        : (isStableIndirectConnection
                            ? Colors.teal.shade700
                            : (isEffectivelyConnected
                                ? Colors.orange.shade700
                                : (_isRecovering
                                    ? Colors.purple.shade700
                                    : Colors.red.shade700))),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected
                            ? Icons.wifi
                            : (isStableIndirectConnection
                                ? Icons.wifi_tethering
                                : (isEffectivelyConnected
                                    ? Icons.wifi_find
                                    : (_isRecovering
                                        ? Icons.sync
                                        : Icons.wifi_off))),
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        connectionStatus,
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
            ],
          ),
          body: !_isInitialized
              ? Center(
                  child: Lottie.asset('assets/loading.json',
                      repeat: true, animate: true, onLoaded: (composition) {
                  print("로티 애니메이션 로드 성공!");
                }))
              : Column(
                  children: [
                    // 컨트롤러 영역
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          bool isLandscape =
                              constraints.maxWidth > constraints.maxHeight;
                          return isLandscape
                              ? Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('방향 제어',
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold)),
                                          SizedBox(height: 20),
                                          DirectionalController(
                                            enabled: (isConnected ||
                                                    isEffectivelyConnected) &&
                                                !isAutoMode,
                                            onDirectionPressed:
                                                onDirectionPressed,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('회전 제어',
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold)),
                                          SizedBox(height: 20),
                                          RotationJoystick(
                                            enabled: (isConnected ||
                                                    isEffectivelyConnected) &&
                                                !isAutoMode,
                                            rotationAngle: rotationAngle,
                                            onMove: onJoystickMove,
                                          ),
                                          SizedBox(height: 20),
                                                                    AutoModeButton(
                            enabled: (isConnected ||
                                isEffectivelyConnected) && !_isTogglingAutoMode,
                            isAutoMode: isAutoMode,
                            isToggling: _isTogglingAutoMode,
                            onPressed: toggleAutoMode,
                          ),
                                          SizedBox(height: 10),
                                          FanPowerButton(
                                            enabled: isConnected ||
                                                isEffectivelyConnected,
                                            fanPowerOn: fanPowerOn,
                                            onPressed: toggleFanPower,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('방향 제어',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    DirectionalController(
                                      enabled: (isConnected ||
                                              isEffectivelyConnected) &&
                                          !isAutoMode,
                                      onDirectionPressed: onDirectionPressed,
                                    ),
                                    SizedBox(height: 20),
                                    Text('회전 제어',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    RotationJoystick(
                                      enabled: (isConnected ||
                                              isEffectivelyConnected) &&
                                          !isAutoMode,
                                      rotationAngle: rotationAngle,
                                      onMove: onJoystickMove,
                                    ),
                                    SizedBox(height: 20),
                                    AutoModeButton(
                                      enabled:
                                          (isConnected || isEffectivelyConnected) && !_isTogglingAutoMode,
                                      isAutoMode: isAutoMode,
                                      isToggling: _isTogglingAutoMode,
                                      onPressed: toggleAutoMode,
                                    ),
                                    SizedBox(height: 10),
                                    FanPowerButton(
                                      enabled:
                                          isConnected || isEffectivelyConnected,
                                      fanPowerOn: fanPowerOn,
                                      onPressed: toggleFanPower,
                                    ),
                                  ],
                                );
                        },
                      ),
                    ),
                  ],
                ),
        ),

        // 접이식 메뉴 오버레이 (새로 수정된 부분)
        if (_isMenuExpanded)
          Positioned(
            top: 0, // AppBar를 포함한 상단 전체를 덮도록 수정
            left: 0,
            right: 0,
            bottom: 0, // 전체 화면을 커버
            child: Material(
              // 전체를 Material로 감싸서 이벤트 처리를 보장
              color: Colors.transparent,
              child: Container(
                color: Colors.black.withOpacity(0.3), // 배경에 반투명 오버레이 추가
                child: Column(
                  children: [
                    SizedBox(
                        height: AppBar().preferredSize.height +
                            MediaQuery.of(context).padding.top), // AppBar 공간 확보
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.all(0),
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: FoldableMenuContent(
                          brokerIp: widget.brokerIp,
                          systemState: systemState,
                          temperature: currentTemperature,
                          lastUpdate: lastUpdateTime,
                          isConnected: isConnected || isEffectivelyConnected,
                          onResetIp: _resetIpSettings,
                          isStableIndirect: isStableIndirectConnection,
                          connectionStatus: connectionStatus,
                          fanPowerOn: fanPowerOn,
                          onClose: () {
                            // 새 콜백 속성 추가
                            setState(() {
                              _isMenuExpanded = false;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 오버레이 (자동 모드 활성화 시)
        if (isAutoMode && (isConnected || isEffectivelyConnected))
          Positioned.fill(
            child: GestureDetector(
              onTap: toggleAutoMode,
              child: Stack(
                children: [
                  // 배경 이미지 레이어
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.5,
                      child: Image.asset(
                        'assets/backgyeong.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // 반투명 오버레이
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                    ),
                  ),
                  // 컨텐츠 레이어
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 48,
                          color: Colors.white,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '자동 모드 활성화',
                          style: TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: toggleAutoMode,
                          child: Text('수동 모드로 전환'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 연결 복구 중 오버레이
        if (_isRecovering)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          '연결 복구 중...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text('서버와의 연결을 재구성하고 있습니다.'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// 접이식 메뉴 내용을 위한 새로운 위젯
class FoldableMenuContent extends StatelessWidget {
  final String brokerIp;
  final String systemState;
  final double temperature;
  final String lastUpdate;
  final bool isConnected;
  final bool isStableIndirect;
  final String connectionStatus;
  final bool fanPowerOn;
  final VoidCallback onResetIp;
  final VoidCallback onClose; // 새로운 콜백 속성 추가

  FoldableMenuContent({
    required this.brokerIp,
    required this.systemState,
    required this.temperature,
    required this.lastUpdate,
    required this.isConnected,
    required this.isStableIndirect,
    required this.connectionStatus,
    required this.fanPowerOn,
    required this.onResetIp,
    required this.onClose,
  });

  // 시스템 상태에 따른 색상 및 아이콘
  IconData _getStateIcon() {
    switch (systemState) {
      case 'measuring':
        return Icons.thermostat;
      case 'rotating':
        return Icons.rotate_right;
      case 'detected':
        return Icons.person;
      case 'idle':
        return Icons.pause_circle;
      case 'error':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  Color _getStateColor() {
    switch (systemState) {
      case 'measuring':
        return Colors.blue;
      case 'rotating':
        return Colors.green;
      case 'detected':
        return Colors.orange;
      case 'idle':
        return Colors.grey;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStateText() {
    switch (systemState) {
      case 'measuring':
        return '온도 측정 중';
      case 'rotating':
        return '팬 회전 중';
      case 'detected':
        return '사람 감지됨';
      case 'idle':
        return '대기 중';
      case 'error':
        return '오류 발생';
      case 'unknown':
        return isConnected ? '상태 수신 대기중' : '상태 미확인';
      default:
        return '상태 미확인';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      // Material 위젯 추가
      color: Colors.white,
      elevation: 0,
      child: SafeArea(
        top: false, // 이미 상단 공간을 확보했으므로 불필요
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 제목 및 닫기 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '시스템 정보',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: onClose, // 수정된 콜백 사용
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
              Divider(height: 1),

              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // 브로커 IP 정보
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.router, color: Colors.blue.shade700),
                      title: Text('브로커 IP'),
                      subtitle: Text(brokerIp),
                      trailing: IconButton(
                        icon: Icon(Icons.refresh, color: Colors.red.shade700),
                        tooltip: 'IP 설정 초기화',
                        onPressed: onResetIp,
                      ),
                    ),

                    // 연결 상태
                    ListTile(
                      dense: true,
                      leading: Icon(
                        isConnected
                            ? Icons.wifi
                            : (isStableIndirect
                                ? Icons.wifi_tethering
                                : Icons.wifi_off),
                        color: isConnected
                            ? Colors.green.shade700
                            : (isStableIndirect
                                ? Colors.teal.shade700
                                : Colors.red.shade700),
                      ),
                      title: Text('연결 상태'),
                      subtitle: Text(connectionStatus),
                    ),

                    // 시스템 상태
                    ListTile(
                      dense: true,
                      leading: Icon(_getStateIcon(), color: _getStateColor()),
                      title: Text('시스템 상태'),
                      subtitle: Text(_getStateText()),
                    ),

                    // 선풍기 전원 상태
                    ListTile(
                      dense: true,
                      leading: Icon(
                        fanPowerOn ? Icons.power : Icons.power_off,
                        color: fanPowerOn ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      title: Text('선풍기 전원'),
                      subtitle: Text(fanPowerOn ? 'ON' : 'OFF'),
                    ),

                    // 현재 온도
                    ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.thermostat,
                        color: temperature > 37.5 ? Colors.red : Colors.blue,
                      ),
                      title: Text('현재 온도'),
                      subtitle: Text(
                        temperature > 0
                            ? '${temperature.toStringAsFixed(1)}°C'
                            : '--°C',
                      ),
                    ),

                    // 마지막 업데이트
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.update, color: Colors.grey.shade700),
                      title: Text('마지막 업데이트'),
                      subtitle: Text(
                        lastUpdate != '-' && lastUpdate.isNotEmpty
                            ? lastUpdate
                            : '없음',
                      ),
                    ),

                    // 제어 기능 설명 추가
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.info, color: Colors.orange.shade700),
                      title: Text('제어 기능'),
                      subtitle: Text('방향 버튼: 이동 제어 / 회전 조이스틱: 선풍기 회전'),
                    ),

                    // 하단 버튼들
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: Icon(Icons.refresh),
                            label: Text('연결 복구'),
                            onPressed: isConnected
                                ? null
                                : () {
                                    // 연결 복구 로직 실행 (이 버튼에서는 UI만 변경)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text('연결 복구 시도 중...')));
                                    final controllerViewState =
                                        context.findAncestorStateOfType<
                                            _ControllerViewState>();
                                    if (controllerViewState != null) {
                                      controllerViewState
                                          ._reconnectToMqttBroker(
                                              forceReconnect: true);
                                    }
                                    // 메뉴 닫기
                                    onClose();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              disabledBackgroundColor: Colors.grey.shade400,
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: Icon(Icons.info_outline),
                            label: Text('정보'),
                            onPressed: () {
                              // 앱 정보 다이얼로그 표시
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('AI FAN Controller'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('버전: 1.0.0'),
                                      Text('개발: AI FAN 팀'),
                                      SizedBox(height: 8),
                                      Text('© 2024 AI FAN 프로젝트'),
                                      SizedBox(height: 8),
                                      Text('* 방향 버튼: 이동 제어'),
                                      Text('* 회전 조이스틱: 선풍기 회전 제어'),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: Text('확인'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// AutoModeButton 컴포넌트 (최적화된 빠른 반응)
class AutoModeButton extends StatelessWidget {
  final bool isAutoMode;
  final bool enabled;
  final bool isToggling;
  final VoidCallback onPressed;

  AutoModeButton({
    required this.isAutoMode,
    required this.onPressed,
    this.enabled = true,
    this.isToggling = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 150), // 빠른 애니메이션
      child: ElevatedButton.icon(
        onPressed: enabled && !isToggling ? onPressed : null,
        icon: isToggling 
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(
                isAutoMode ? Icons.auto_fix_high : Icons.gamepad,
                size: 22,
              ),
        label: Text(
          isToggling 
              ? '처리 중...' // 텍스트 단축
              : (isAutoMode ? '수동 모드로 전환' : '자동 모드로 전환'),
          style: TextStyle(
            fontSize: 15, // 약간 축소
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          backgroundColor: _getButtonColor(),
          foregroundColor: Colors.white,
          elevation: isToggling ? 1 : 4, // 토글 시 더 낮은 elevation
          shadowColor: Colors.black.withOpacity(0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          animationDuration: Duration(milliseconds: 150), // 빠른 애니메이션
        ),
      ),
    );
  }

  Color _getButtonColor() {
    if (!enabled) {
      return Colors.grey.shade400;
    }
    
    if (isToggling) {
      // 토글 중일 때는 약간 어두운 색상
      return isAutoMode ? Colors.orange.shade700 : Colors.blue.shade700;
    }
    
    if (isAutoMode) {
      return Colors.orange.shade600; // 자동 모드 - 주황색
    } else {
      return Colors.blue.shade600; // 수동 모드 - 파란색
    }
  }
}

// FanPowerButton 컴포넌트
class FanPowerButton extends StatelessWidget {
  final bool fanPowerOn;
  final bool enabled;
  final VoidCallback onPressed;

  FanPowerButton({
    required this.fanPowerOn,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(fanPowerOn ? Icons.power_off : Icons.power),
      label: Text(fanPowerOn ? '선풍기 끄기' : '선풍기 켜기'),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        backgroundColor: enabled
            ? (fanPowerOn ? Colors.red.shade700 : Colors.green.shade700)
            : Colors.grey,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// DirectionalController 컴포넌트 - 중복 발행 완전 방지
class DirectionalController extends StatefulWidget {
  final Function(String) onDirectionPressed;
  final bool enabled;

  DirectionalController({
    required this.onDirectionPressed,
    this.enabled = true,
  });

  @override
  _DirectionalControllerState createState() => _DirectionalControllerState();
}

class _DirectionalControllerState extends State<DirectionalController> {
  // 각 방향별 개별 상태 관리
  Map<String, bool> _directionPressed = {
    'up': false,
    'down': false,
    'left': false,
    'right': false,
  };
  
  // 각 방향별 메시지 발행 상태 (이미 발행했는지 추적)
  Map<String, bool> _messageSent = {
    'up': false,
    'down': false,
    'left': false,
    'right': false,
  };

  String? _activeDirection;
  bool _stopMessageSent = false; // stop 메시지 발행 여부

  // 방향을 이동 명령으로 매핑하는 헬퍼 함수
  String _mapDirectionToMovement(String direction) {
    switch (direction) {
      case "up":
        return "forward";
      case "down":
        return "backward";
      case "left":
        return "left";
      case "right":
        return "right";
      default:
        return "stop";
    }
  }

  void _onDirectionTapDown(String direction) {
    if (!widget.enabled) return;
    
    // 이미 해당 방향이 눌려있고 메시지가 발행되었으면 무시
    if (_directionPressed[direction] == true && _messageSent[direction] == true) {
      print('Direction $direction already pressed and message sent, ignoring');
      return;
    }
    
    // 다른 방향이 활성화되어 있으면 먼저 해제
    if (_activeDirection != null && _activeDirection != direction) {
      _releaseDirection(_activeDirection!);
    }
    
    setState(() {
      _activeDirection = direction;
      _directionPressed[direction] = true;
      _messageSent[direction] = true; // 메시지 발행 상태로 변경
      _stopMessageSent = false; // stop 메시지 상태 초기화
    });
    
    // 한 번만 메시지 발행
    widget.onDirectionPressed(direction);
    print('✅ Direction message sent ONCE: $direction -> ${_mapDirectionToMovement(direction)}');
  }

  void _onDirectionTapUpOrCancel(String direction) {
    if (!widget.enabled) return;
    
    // 해당 방향이 눌려있지 않으면 무시
    if (_directionPressed[direction] != true) {
      return;
    }
    
    // 현재 활성화된 방향이 아니면 무시
    if (_activeDirection != direction) {
      return;
    }
    
    _releaseDirection(direction);
  }

  void _releaseDirection(String direction) {
    // 이미 stop 메시지를 보냈으면 무시
    if (_stopMessageSent) {
      print('Stop message already sent, ignoring release for: $direction');
      return;
    }
    
    setState(() {
      _activeDirection = null;
      _directionPressed[direction] = false;
      _messageSent[direction] = false; // 메시지 발행 상태 초기화
      _stopMessageSent = true; // stop 메시지 발행 상태로 변경
    });
    
    // stop 메시지 한 번만 발행
    widget.onDirectionPressed('stop');
    print('✅ Stop message sent ONCE for direction: $direction');
  }

  // 모든 방향 해제 (안전장치)
  void _releaseAllDirections() {
    if (_activeDirection != null && !_stopMessageSent) {
      final currentDirection = _activeDirection!;
      setState(() {
        _activeDirection = null;
        _directionPressed.forEach((key, value) {
          _directionPressed[key] = false;
          _messageSent[key] = false;
        });
        _stopMessageSent = true;
      });
      
      widget.onDirectionPressed('stop');
      print('✅ Emergency stop message sent for: $currentDirection');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: widget.enabled
            ? Colors.blue.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.enabled
              ? Colors.blue.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          // 중앙 원
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: widget.enabled
                    ? Colors.blue.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.gamepad,
                color: widget.enabled ? Colors.blue.shade800 : Colors.grey,
                size: 30,
              ),
            ),
          ),
          
          // 위쪽 버튼 (전진)
          Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTapDown: (_) => _onDirectionTapDown("up"),
              onTapUp: (_) => _onDirectionTapUpOrCancel("up"),
              onTapCancel: () => _onDirectionTapUpOrCancel("up"),
              // 패닝이나 드래그 시에도 안전하게 해제
              onPanEnd: (_) => _onDirectionTapUpOrCancel("up"),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _directionPressed["up"] == true
                      ? (widget.enabled
                          ? Colors.blue.shade600
                          : Colors.grey.shade400)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward,
                  size: 40,
                  color: widget.enabled
                      ? (_directionPressed["up"] == true
                          ? Colors.white
                          : Colors.blue.shade800)
                      : Colors.grey,
                ),
              ),
            ),
          ),
          
          // 아래쪽 버튼 (후진)
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTapDown: (_) => _onDirectionTapDown("down"),
              onTapUp: (_) => _onDirectionTapUpOrCancel("down"),
              onTapCancel: () => _onDirectionTapUpOrCancel("down"),
              onPanEnd: (_) => _onDirectionTapUpOrCancel("down"),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _directionPressed["down"] == true
                      ? (widget.enabled
                          ? Colors.blue.shade600
                          : Colors.grey.shade400)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_downward,
                  size: 40,
                  color: widget.enabled
                      ? (_directionPressed["down"] == true
                          ? Colors.white
                          : Colors.blue.shade800)
                      : Colors.grey,
                ),
              ),
            ),
          ),
          
          // 왼쪽 버튼
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTapDown: (_) => _onDirectionTapDown("left"),
              onTapUp: (_) => _onDirectionTapUpOrCancel("left"),
              onTapCancel: () => _onDirectionTapUpOrCancel("left"),
              onPanEnd: (_) => _onDirectionTapUpOrCancel("left"),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _directionPressed["left"] == true
                      ? (widget.enabled
                          ? Colors.blue.shade600
                          : Colors.grey.shade400)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_back,
                  size: 40,
                  color: widget.enabled
                      ? (_directionPressed["left"] == true
                          ? Colors.white
                          : Colors.blue.shade800)
                      : Colors.grey,
                ),
              ),
            ),
          ),
          
          // 오른쪽 버튼
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTapDown: (_) => _onDirectionTapDown("right"),
              onTapUp: (_) => _onDirectionTapUpOrCancel("right"),
              onTapCancel: () => _onDirectionTapUpOrCancel("right"),
              onPanEnd: (_) => _onDirectionTapUpOrCancel("right"),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _directionPressed["right"] == true
                      ? (widget.enabled
                          ? Colors.blue.shade600
                          : Colors.grey.shade400)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward,
                  size: 40,
                  color: widget.enabled
                      ? (_directionPressed["right"] == true
                          ? Colors.white
                          : Colors.blue.shade800)
                      : Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 위젯이 파괴될 때 안전하게 모든 방향 해제
    _releaseAllDirections();
    super.dispose();
  }
}

// RotationJoystick 컴포넌트 - 간소화된 중복 방지
class RotationJoystick extends StatefulWidget {
  final double rotationAngle;
  final Function(String) onMove;
  final bool enabled;

  RotationJoystick({
    required this.rotationAngle,
    required this.onMove,
    this.enabled = true,
  });

  @override
  _RotationJoystickState createState() => _RotationJoystickState();
}

class _RotationJoystickState extends State<RotationJoystick> {
  // 간단한 상태 관리
  Map<String, bool> _rotationPressed = {
    'left': false,
    'right': false,
  };
  
  // 각 방향별 메시지 발행 상태
  Map<String, bool> _messageSent = {
    'left': false,
    'right': false,
  };
  
  String? _activeDirection;
  bool _stopMessageSent = false;

  void _startRotation(String direction) {
    if (!widget.enabled) return;
    
    // 이미 해당 방향이 눌려있고 메시지가 발행되었으면 무시
    if (_rotationPressed[direction] == true && _messageSent[direction] == true) {
      print('Rotation $direction already active and message sent, ignoring');
      return;
    }
    
    // 다른 방향이 활성화되어 있으면 먼저 해제
    if (_activeDirection != null && _activeDirection != direction) {
      _stopRotation();
    }
    
    setState(() {
      _activeDirection = direction;
      _rotationPressed[direction] = true;
      _messageSent[direction] = true;
      _stopMessageSent = false;
      
      // 다른 방향은 false로 설정
      _rotationPressed.forEach((key, value) {
        if (key != direction) {
          _rotationPressed[key] = false;
          _messageSent[key] = false;
        }
      });
    });

    // 한 번만 명령 전송
    widget.onMove(direction);
    print('✅ Rotation message sent ONCE: $direction');
  }

  void _stopRotation() {
    if (!widget.enabled) return;
    
    // 이미 stop 메시지를 보냈거나 활성화된 방향이 없으면 무시
    if (_stopMessageSent || _activeDirection == null) {
      return;
    }
    
    final currentDirection = _activeDirection;
    
    setState(() {
      _activeDirection = null;
      _stopMessageSent = true;
      _rotationPressed.forEach((key, value) {
        _rotationPressed[key] = false;
        _messageSent[key] = false;
      });
    });

    // 정지 명령 한 번만 전송
    widget.onMove("center");
    print('✅ Rotation stop message sent ONCE for: $currentDirection');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = 300.0;
        final containerHeight = 60.0;
        final buttonSize = 50.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: containerWidth,
              height: containerHeight,
              decoration: BoxDecoration(
                gradient: widget.enabled
                    ? LinearGradient(
                        colors: [Colors.blue.shade100, Colors.blue.shade200],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : LinearGradient(
                        colors: [Colors.grey.shade200, Colors.grey.shade300],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                borderRadius: BorderRadius.circular(containerHeight / 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // 왼쪽 회전 버튼
                  Positioned(
                    left: 5,
                    top: (containerHeight - buttonSize) / 2,
                    child: GestureDetector(
                      onTapDown: (_) => _startRotation("left"),
                      onTapUp: (_) => _stopRotation(),
                      onTapCancel: _stopRotation,
                      onPanEnd: (_) => _stopRotation(),
                      child: Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          gradient: widget.enabled
                              ? (_rotationPressed["left"] == true
                                  ? LinearGradient(
                                      colors: [
                                        Colors.blue.shade600,
                                        Colors.blue.shade800
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : LinearGradient(
                                      colors: [
                                        Colors.blue.shade400,
                                        Colors.blue.shade600
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ))
                              : LinearGradient(
                                  colors: [
                                    Colors.grey.shade400,
                                    Colors.grey.shade500
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          shape: BoxShape.circle,
                          boxShadow: widget.enabled
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: _rotationPressed["left"] == true ? 2 : 5,
                                    spreadRadius: _rotationPressed["left"] == true ? 0 : 1,
                                    offset: Offset(0, _rotationPressed["left"] == true ? 1 : 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.rotate_left,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 오른쪽 회전 버튼
                  Positioned(
                    right: 5,
                    top: (containerHeight - buttonSize) / 2,
                    child: GestureDetector(
                      onTapDown: (_) => _startRotation("right"),
                      onTapUp: (_) => _stopRotation(),
                      onTapCancel: _stopRotation,
                      onPanEnd: (_) => _stopRotation(),
                      child: Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          gradient: widget.enabled
                              ? (_rotationPressed["right"] == true
                                  ? LinearGradient(
                                      colors: [
                                        Colors.blue.shade600,
                                        Colors.blue.shade800
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : LinearGradient(
                                      colors: [
                                        Colors.blue.shade400,
                                        Colors.blue.shade600
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ))
                              : LinearGradient(
                                  colors: [
                                    Colors.grey.shade400,
                                    Colors.grey.shade500
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          shape: BoxShape.circle,
                          boxShadow: widget.enabled
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: _rotationPressed["right"] == true ? 2 : 5,
                                    spreadRadius: _rotationPressed["right"] == true ? 0 : 1,
                                    offset: Offset(0, _rotationPressed["right"] == true ? 1 : 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.rotate_right,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 중앙 정보 표시
                  Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: widget.enabled
                            ? Colors.blue.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.enabled
                              ? Colors.blue.withOpacity(0.3)
                              : Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.rotate_90_degrees_ccw,
                            size: 18,
                            color: widget.enabled
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '회전 제어',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.enabled
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 상태 표시
            SizedBox(height: 8),
            Text(
              _rotationPressed["left"] == true
                  ? '← 좌회전 중'
                  : (_rotationPressed["right"] == true ? '우회전 중 →' : '회전 대기'),
              style: TextStyle(
                fontSize: 14,
                color: widget.enabled
                    ? (_rotationPressed["left"] == true || _rotationPressed["right"] == true
                        ? Colors.blue.shade800
                        : Colors.blue.shade700)
                    : Colors.grey.shade600,
                fontWeight: _rotationPressed["left"] == true || _rotationPressed["right"] == true
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // 위젯이 파괴될 때 안전하게 정지
    if (_activeDirection != null && !_stopMessageSent) {
      widget.onMove("center");
    }
    super.dispose();
  }
}