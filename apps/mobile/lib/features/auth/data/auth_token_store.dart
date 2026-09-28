import 'package:flutter/services.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class AuthTokenStore implements TokenStore {
  static const _channel = MethodChannel('bingo/secure_storage');

  @override
  Future<String?> read() => _channel.invokeMethod<String>('readToken');

  @override
  Future<void> write(String token) =>
      _channel.invokeMethod<void>('writeToken', token);

  @override
  Future<void> clear() => _channel.invokeMethod<void>('clearToken');
}
