class AppConfig {
  const AppConfig({
    required this.apiBaseUri,
    this.apiPrefix = '/api/v1',
  });

  factory AppConfig.fromEnvironment() {
    const rawUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    const rawPrefix = String.fromEnvironment(
      'API_PREFIX',
      defaultValue: '/api/v1',
    );
    final uri = Uri.parse(rawUrl);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('API_BASE_URL must be an absolute URL');
    }
    return AppConfig(
      apiBaseUri: uri,
      apiPrefix: _normalizePrefix(rawPrefix),
    );
  }

  final Uri apiBaseUri;
  final String apiPrefix;

  Uri endpoint(String path) => apiBaseUri.replace(
        path: '$apiPrefix${path.startsWith('/') ? path : '/$path'}',
        query: null,
        fragment: null,
      );

  static String _normalizePrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('/')) {
      throw const FormatException('API_PREFIX must start with /');
    }
    if (trimmed.contains('?') || trimmed.contains('#')) {
      throw const FormatException('API_PREFIX must only contain a URL path');
    }
    return trimmed.length > 1 && trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
