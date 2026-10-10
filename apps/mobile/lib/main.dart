import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_session_controller.dart';
import 'app/farmly_app.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = FarmlyAppConfig.fromEnvironment();
  runApp(
    ProviderScope(
      overrides: [farmlyAppConfigProvider.overrideWithValue(config)],
      child: FarmlyApp(config: config),
    ),
  );
}
