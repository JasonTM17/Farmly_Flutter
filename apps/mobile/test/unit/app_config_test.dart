import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/config/app_config.dart';

void main() {
  group('FarmlyAppConfig', () {
    test('uses the native flavor and public local API URL in development', () {
      final config = FarmlyAppConfig.fromEnvironment(
        flavorOverride: 'development',
        apiBaseUrlOverride: 'http://10.0.2.2:3000',
      );

      expect(config.flavor, FarmlyAppFlavor.development);
      expect(config.apiBaseUrl.host, '10.0.2.2');
      expect(config.aiEnabled, isFalse);
    });

    test('requires HTTPS outside local development', () {
      expect(
        () => FarmlyAppConfig.fromEnvironment(
          flavorOverride: 'staging',
          apiBaseUrlOverride: 'http://staging.example.test',
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyAppConfig.fromEnvironment(
          flavorOverride: 'production',
          apiBaseUrlOverride: 'https://api.example.test',
        ),
        returnsNormally,
      );
    });

    test('rejects unknown flavor and credentials embedded in the API URL', () {
      expect(
        () => FarmlyAppConfig.fromEnvironment(flavorOverride: 'preview'),
        throwsFormatException,
      );
      expect(
        () => FarmlyAppConfig.fromEnvironment(
          flavorOverride: 'development',
          apiBaseUrlOverride: 'http://user:password@localhost:3000',
        ),
        throwsFormatException,
      );
    });
  });
}
