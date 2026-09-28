import 'package:bingo/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the public default API prefix', () {
    final config = AppConfig(apiBaseUri: Uri.parse('https://example.com'));

    expect(
      config.endpoint('/health').toString(),
      'https://example.com/api/v1/health',
    );
  });

  test('supports a deployment-specific API prefix', () {
    final config = AppConfig(
      apiBaseUri: Uri.parse('https://agentchat.cloud'),
      apiPrefix: '/bingo/api/v1',
    );

    expect(
      config.endpoint('/chat/stream').toString(),
      'https://agentchat.cloud/bingo/api/v1/chat/stream',
    );
  });
}
