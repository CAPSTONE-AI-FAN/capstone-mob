// lib/mqtt_service.dart

import 'dart:async';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class MQTTService {
  final String broker;
  final int port;
  final String clientIdentifier;
  final String username;
  final String password;
  final bool useTLS;

  late MqttServerClient client;
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  Stream<String> get messages => _messageController.stream;

  MQTTService({
    required this.broker,
    required this.port,
    required this.clientIdentifier,
    required this.username,
    required this.password,
    this.useTLS = false,
  }) {
    client = MqttServerClient(broker, clientIdentifier);
    client.port = port;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
    client.onSubscribeFail = _onSubscribeFail;
    client.pongCallback = _pong;

    if (useTLS) {
      client.secure = true;
      client.securityContext = SecurityContext.defaultContext;
      // 만약 자체 서명된 인증서를 사용하는 경우, 여기에서 인증서를 로드하세요.
      // client.securityContext.setTrustedCertificates('path/to/ca.crt');
    }

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .authenticateAs(username, password)
        .withWillTopic('fan/control') // Optional
        .withWillMessage('My Mobile message')
        .startClean() // Non-persistent session
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;
  }

  Future<void> connect() async {
    try {
      print('MQTTService: Connecting to MQTT broker...');
      await client.connect();
    } catch (e) {
      print('MQTTService: Connection failed: $e');
      disconnect();
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      print('MQTTService: Connected to MQTT broker');
      // Subscribe to topics if needed
      client.subscribe('fan/control/#', MqttQos.atLeastOnce);
    } else {
      print(
          'MQTTService: Connection failed - status: ${client.connectionStatus?.state}');
      disconnect();
    }

    // Listen for incoming messages
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String message =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      final String topic = c[0].topic;
      print('MQTTService: Received message: $message from topic: $topic');
      _messageController.add(message);
    });
  }

  void disconnect() {
    print('MQTTService: Disconnecting');
    client.disconnect();
    _onDisconnected();
  }

  void _onSubscribed(String topic) {
    print('MQTTService: Subscribed to $topic');
  }

  void _onSubscribeFail(String topic) {
    print('MQTTService: Failed to subscribe $topic');
  }

  void _onConnected() {
    print('MQTTService: Connected');
  }

  void _onDisconnected() {
    print('MQTTService: Disconnected');
    // Optionally implement reconnection logic here
  }

  void _pong() {
    print('MQTTService: Pong callback');
  }

  void publishMessage(String topic, String message) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      print('MQTTService: Publishing "$message" to $topic');
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    } else {
      print('MQTTService: Cannot publish, not connected');
      // Optional: Attempt to reconnect or notify the user
    }
  }

  void dispose() {
    _messageController.close();
    disconnect();
  }
}
