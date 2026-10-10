import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_session_controller.dart';
import 'farmly_auth_models.dart';

class FarmlyAuthSessionLifecycleGate extends ConsumerStatefulWidget {
  const FarmlyAuthSessionLifecycleGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<FarmlyAuthSessionLifecycleGate> createState() =>
      _FarmlyAuthSessionLifecycleGateState();
}

class _FarmlyAuthSessionLifecycleGateState
    extends ConsumerState<FarmlyAuthSessionLifecycleGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final session = ref.read(farmlyAuthSessionProvider);
    if (session is AsyncData<FarmlyAuthSession?> && session.value != null) {
      unawaited(
        ref.read(farmlyAuthSessionProvider.notifier).refreshFromServer(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
