import 'dart:async';
import 'dart:io';

import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:flutter/services.dart';

class PushRegistrationService {
  PushRegistrationService({
    required PushGateway gateway,
  }) : _gateway = gateway;

  static const _channel = MethodChannel('bingo/push');

  final PushGateway _gateway;
  Map<String, dynamic>? _deviceInfo;
  String? _clientId;
  bool _configured = false;
  bool _authenticated = false;
  String? _userId;
  bool _starting = false;
  bool _started = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _configured = await _channel.invokeMethod<bool>('isConfigured') ?? false;
    if (!_configured) return;
    _deviceInfo = Map<String, dynamic>.from(
      await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo') ??
          const {},
    );
    if (_authenticated) unawaited(_startSdk());
  }

  Future<void> activate(String userId) async {
    _userId = userId;
    _authenticated = true;
    if (!_configured) return;
    unawaited(_startSdk());
  }

  Future<void> _startSdk() async {
    if (_starting) return;
    _starting = true;
    try {
      final userId = _userId;
      if (!_authenticated || userId == null) return;
      await _channel.invokeMethod<void>('setAccount', {'user_id': userId});
      if (!_authenticated || _userId != userId) return;
      await _channel.invokeMethod<void>('requestPermission');
      if (!_started) {
        _started = await _channel.invokeMethod<bool>('initialize') ?? false;
      }
      if (!_started) return;
      await _loadClientId();
      await _registerIfReady();
    } on Exception {
      // Push registration is best-effort and must not delay app startup.
    } finally {
      _starting = false;
    }
  }

  Future<void> _loadClientId() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      _clientId = await _channel.invokeMethod<String>('getClientId');
      if (_clientId?.trim().isNotEmpty ?? false) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> deactivate() async {
    _authenticated = false;
    _userId = null;
    final installationId = _deviceInfo?['installation_id'] as String?;
    if (!_configured || installationId == null) return;
    try {
      await _channel.invokeMethod<void>('setAccount', {'user_id': null});
      await _gateway.unregisterPushDevice(installationId);
    } on Exception {
      // Logout must still work if the server is temporarily unavailable.
    }
  }

  Future<void> _registerIfReady() async {
    final info = _deviceInfo;
    final clientId = _clientId;
    if (!_configured || !_authenticated || info == null || clientId == null) {
      return;
    }
    if (clientId.trim().isEmpty) return;
    await _gateway.registerPushDevice(
      installationId: info['installation_id'] as String,
      clientId: clientId,
      manufacturer: info['manufacturer'] as String?,
      model: info['model'] as String?,
      appVersion: info['app_version'] as String?,
      roleAvatarNotifications: true,
    );
  }
}
