import 'package:flutter/services.dart' show appFlavor;

enum FarmlyAppFlavor { development, staging, production }

class FarmlyAppConfig {
  const FarmlyAppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.aiEnabled,
  });

  final FarmlyAppFlavor flavor;
  final Uri apiBaseUrl;

  /// A public presentation hint only; server authorization and quota remain authoritative.
  final bool aiEnabled;

  factory FarmlyAppConfig.fromEnvironment({
    String? flavorOverride,
    String? apiBaseUrlOverride,
    bool? aiEnabledOverride,
  }) {
    final flavorName = flavorOverride ?? appFlavor ?? 'development';
    final flavor = switch (flavorName) {
      'development' => FarmlyAppFlavor.development,
      'staging' => FarmlyAppFlavor.staging,
      'production' => FarmlyAppFlavor.production,
      _ => throw const FormatException('Invalid Farmly app flavor'),
    };

    final rawBaseUrl =
        apiBaseUrlOverride ??
        const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://127.0.0.1:3000',
        );
    final uri = Uri.tryParse(rawBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid Farmly API_BASE_URL');
    }
    final isHttps = uri.scheme == 'https';
    final isLocalDevelopment =
        flavor == FarmlyAppFlavor.development &&
        uri.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    if (!isHttps && !isLocalDevelopment) {
      throw const FormatException(
        'Farmly staging and production require an HTTPS API_BASE_URL',
      );
    }

    return FarmlyAppConfig(
      flavor: flavor,
      apiBaseUrl: uri,
      aiEnabled:
          aiEnabledOverride ??
          const bool.fromEnvironment('AI_ENABLED', defaultValue: false),
    );
  }
}
