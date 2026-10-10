import 'package:flutter_riverpod/flutter_riverpod.dart';

final authFlowDraftProvider =
    NotifierProvider<AuthFlowDraftController, AuthFlowDraft>(
      AuthFlowDraftController.new,
    );

final class AuthFlowDraft {
  const AuthFlowDraft({this.email, this.returnTo});

  final String? email;
  final String? returnTo;
}

class AuthFlowDraftController extends Notifier<AuthFlowDraft> {
  @override
  AuthFlowDraft build() => const AuthFlowDraft();

  void setEmail(String? email) {
    state = AuthFlowDraft(email: email, returnTo: state.returnTo);
  }

  void setReturnTo(String? returnTo) {
    state = AuthFlowDraft(email: state.email, returnTo: returnTo);
  }

  void clear() => state = const AuthFlowDraft();
}
