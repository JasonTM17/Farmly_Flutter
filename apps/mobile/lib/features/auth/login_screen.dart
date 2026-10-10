import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/farmly_auth_models.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/illustrations.dart';
import '../app/app_routes.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _keepSignedIn = false;
  bool _submitting = false;
  String? _error;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(AppLocalizations l10n) {
    final value = _email.text.trim();
    if (value.isEmpty) return l10n.emailRequired;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return l10n.emailInvalid;
    }
    return null;
  }

  String? _validatePassword(AppLocalizations l10n) {
    if (_password.text.isEmpty) return l10n.passwordRequired;
    if (_password.text.length < 8) return l10n.passwordTooShort;
    if (_password.text.length > 128) return l10n.passwordTooLong;
    return null;
  }

  String _message(AppLocalizations l10n, FarmlyAuthFailure error) =>
      switch (error.code) {
        FarmlyAuthFailureCode.invalidCredentials => l10n.invalidCredentials,
        FarmlyAuthFailureCode.emailNotVerified => l10n.emailNotVerified,
        FarmlyAuthFailureCode.rateLimited => l10n.rateLimited,
        FarmlyAuthFailureCode.invalidLink => l10n.invalidLinkBody,
        FarmlyAuthFailureCode.unavailable => l10n.authUnavailable,
        FarmlyAuthFailureCode.offlineLeaseExpired =>
          l10n.offlineLeaseExpiredBody,
        FarmlyAuthFailureCode.signOutUnconfirmed => l10n.signOutUnconfirmed,
        FarmlyAuthFailureCode.unexpected => l10n.authUnexpected,
      };

  Future<void> _submit(AppLocalizations l10n) async {
    if (_submitting) return;
    setState(() {
      _emailError = _validateEmail(l10n);
      _passwordError = _validatePassword(l10n);
      _error = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(farmlyAuthSessionProvider.notifier)
          .signIn(
            email: _email.text.trim(),
            password: _password.text,
            keepSignedIn: _keepSignedIn,
          );
      if (!mounted) return;
      final returnTo = safeFarmlyReturnTo(widget.returnTo);
      context.go(returnTo ?? AppRoutes.organizations);
    } on FarmlyAuthFailure catch (error) {
      if (mounted) setState(() => _error = _message(l10n, error));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.authUnexpected);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Full-bleed illustrated header (reference login).
                    SizedBox(
                      height: 240,
                      width: double.infinity,
                      child: ExcludeSemantics(
                        child: CustomPaint(
                          painter: const FarmScenePainter(),
                          child: Padding(
                            padding: const EdgeInsets.all(FarmSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SproutMark(size: 26),
                                const SizedBox(width: FarmSpacing.sm),
                                Text(
                                  l10n.appName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: tokens.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(FarmSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.loginTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: FarmSpacing.sm),
                          Text(
                            l10n.loginDescription,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                          const SizedBox(height: FarmSpacing.lg),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            autocorrect: false,
                            onChanged: (_) {
                              if (_emailError != null) {
                                setState(() => _emailError = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: l10n.emailLabel,
                              errorText: _emailError,
                              prefixIcon: const Icon(Icons.mail_outline),
                            ),
                          ),
                          const SizedBox(height: FarmSpacing.md),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(l10n),
                            onChanged: (_) {
                              if (_passwordError != null) {
                                setState(() => _passwordError = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: l10n.passwordLabel,
                              errorText: _passwordError,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? l10n.showPassword
                                    : l10n.hidePassword,
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _keepSignedIn,
                                  onChanged: (value) => setState(
                                    () => _keepSignedIn = value ?? false,
                                  ),
                                  title: Text(
                                    l10n.keepSignedIn,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    context.go(AppRoutes.forgotPassword),
                                child: Text(l10n.forgotPassword),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: FarmSpacing.sm),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: tokens.semanticError),
                              ),
                            ),
                          ],
                          const SizedBox(height: FarmSpacing.md),
                          FilledButton.icon(
                            onPressed: _submitting ? null : () => _submit(l10n),
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(
                              _submitting ? l10n.signingIn : l10n.signIn,
                            ),
                          ),
                          Center(
                            child: TextButton(
                              onPressed: () =>
                                  context.go(_signupPath(widget.returnTo)),
                              child: Text(
                                l10n.createAccountPrompt,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _signupPath(String? returnTo) {
  return farmlyRouteWithReturnTo(
    AppRoutes.signup,
    safeFarmlyReturnTo(returnTo),
  );
}
