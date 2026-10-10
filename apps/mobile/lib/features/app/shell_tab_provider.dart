import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the visible bottom tab; lets any screen (e.g. the Home avatar)
/// switch tabs while the shell keeps every tab's state alive.
class ShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index < 0 || index > 4) return;
    state = index;
  }
}

final shellTabProvider = NotifierProvider<ShellTabNotifier, int>(
  ShellTabNotifier.new,
);
