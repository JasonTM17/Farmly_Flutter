import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/farmly_auth_models.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/illustrations.dart';
import '../app/app_routes.dart';
import 'auth_flow_draft.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String _authError(AppLocalizations l10n, FarmlyAuthFailure error) =>
    switch (error.code) {
      FarmlyAuthFailureCode.invalidCredentials => l10n.invalidCredentials,
      FarmlyAuthFailureCode.emailNotVerified => l10n.emailNotVerified,
      FarmlyAuthFailureCode.rateLimited => l10n.rateLimited,
      FarmlyAuthFailureCode.invalidLink => l10n.invalidLinkBody,
      FarmlyAuthFailureCode.unavailable => l10n.authUnavailable,
      FarmlyAuthFailureCode.offlineLeaseExpired => l10n.offlineLeaseExpiredBody,
      FarmlyAuthFailureCode.signOutUnconfirmed => l10n.signOutUnconfirmed,
      FarmlyAuthFailureCode.unexpected => l10n.authUnexpected,
    };

String? _emailError(AppLocalizations l10n, String value) {
  if (value.trim().isEmpty) return l10n.emailRequired;
  if (!_emailPattern.hasMatch(value.trim())) return l10n.emailInvalid;
  return null;
}

Widget _authPage({
  required BuildContext context,
  required String title,
  required String description,
  required List<Widget> children,
}) {
  final tokens = FarmThemeExtension.of(context);
  return Scaffold(
    backgroundColor: tokens.background,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(FarmSpacing.lg),
            children: [
              const SizedBox(height: FarmSpacing.lg),
              const ExcludeSemantics(
                child: SizedBox(
                  height: 132,
                  child: CustomPaint(painter: FarmScenePainter()),
                ),
              ),
              const SizedBox(height: FarmSpacing.lg),
              Container(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
                  border: Border.all(color: tokens.divider),
                ),
                padding: const EdgeInsets.all(FarmSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: FarmSpacing.sm),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.lg),
                    ...children,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations l10n) async {
    final emailError = _emailError(l10n, _email.text);
    final password = _password.text;
    final name = _name.text.trim();
    if (name.isEmpty ||
        emailError != null ||
        password.length < 8 ||
        password.length > 128 ||
        password != _confirm.text) {
      setState(
        () => _error =
            emailError ??
            (name.isEmpty
                ? l10n.nameRequired
                : (password.length < 8 || password.isEmpty
                      ? l10n.passwordTooShort
                      : (password.length > 128
                            ? l10n.passwordTooLong
                            : l10n.passwordsDoNotMatch))),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(farmlyAuthSessionProvider.notifier)
          .signUp(
            name: name,
            email: _email.text.trim(),
            password: password,
            returnTo: widget.returnTo,
          );
      ref.read(authFlowDraftProvider.notifier)
        ..setEmail(_email.text.trim())
        ..setReturnTo(widget.returnTo);
      if (mounted) context.go(AppRoutes.verifyEmail);
    } on FarmlyAuthFailure catch (error) {
      if (mounted) setState(() => _error = _authError(l10n, error));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.authUnexpected);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _authPage(
      context: context,
      title: l10n.createAccountTitle,
      description: l10n.loginDescription,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: InputDecoration(labelText: l10n.fullNameLabel),
        ),
        const SizedBox(height: FarmSpacing.md),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          autocorrect: false,
          decoration: InputDecoration(labelText: l10n.emailLabel),
        ),
        const SizedBox(height: FarmSpacing.md),
        _PasswordField(
          controller: _password,
          label: l10n.passwordLabel,
          autofillHint: AutofillHints.newPassword,
        ),
        const SizedBox(height: FarmSpacing.md),
        _PasswordField(
          controller: _confirm,
          label: l10n.confirmPasswordLabel,
          autofillHint: AutofillHints.newPassword,
          onSubmitted: (_) => _submit(l10n),
        ),
        if (_error != null) ...[
          const SizedBox(height: FarmSpacing.md),
          _InlineError(message: _error!),
        ],
        const SizedBox(height: FarmSpacing.lg),
        FilledButton(
          onPressed: _submitting ? null : () => _submit(l10n),
          child: _submitting
              ? Text(l10n.creatingAccount)
              : Text(l10n.createAccount),
        ),
        TextButton(
          onPressed: () => context.go(_loginPath(widget.returnTo)),
          child: Text(l10n.haveAccountPrompt),
        ),
      ],
    );
  }
}

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _message;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email.text.isEmpty) {
      _email.text = ref.read(authFlowDraftProvider).email ?? '';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _resend(AppLocalizations l10n) async {
    final emailError = _emailError(l10n, _email.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(farmlyAuthSessionProvider.notifier)
          .resendVerification(
            _email.text.trim(),
            returnTo: ref.read(authFlowDraftProvider).returnTo,
          );
      ref.read(authFlowDraftProvider.notifier).setEmail(_email.text.trim());
      if (mounted) setState(() => _message = l10n.verificationSent);
    } on FarmlyAuthFailure catch (error) {
      if (mounted) setState(() => _error = _authError(l10n, error));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.authUnexpected);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _authPage(
      context: context,
      title: l10n.verifyEmailTitle,
      description: l10n.verifyEmailBody,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: l10n.emailLabel),
        ),
        if (_message != null) ...[
          const SizedBox(height: FarmSpacing.md),
          Text(_message!, key: const ValueKey('verification-message')),
        ],
        if (_error != null) ...[
          const SizedBox(height: FarmSpacing.md),
          _InlineError(message: _error!),
        ],
        const SizedBox(height: FarmSpacing.lg),
        OutlinedButton(
          onPressed: _sending ? null : () => _resend(l10n),
          child: Text(_sending ? l10n.loading : l10n.resendVerification),
        ),
        TextButton(
          onPressed: () =>
              context.go(_loginPath(ref.read(authFlowDraftProvider).returnTo)),
          child: Text(l10n.signIn),
        ),
      ],
    );
  }
}

class EmailVerifiedScreen extends StatelessWidget {
  const EmailVerifiedScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _authPage(
      context: context,
      title: l10n.verifiedTitle,
      description: l10n.verifiedBody,
      children: [
        FilledButton(
          onPressed: () => context.go(
            farmlyRouteWithReturnTo(
              AppRoutes.login,
              safeFarmlyReturnTo(returnTo),
            ),
          ),
          child: Text(l10n.signIn),
        ),
      ],
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations l10n) async {
    final emailError = _emailError(l10n, _email.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    setState(() {
      _sending = true;
      _sent = false;
      _error = null;
    });
    try {
      await ref
          .read(farmlyAuthSessionProvider.notifier)
          .requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on FarmlyAuthFailure catch (error) {
      if (mounted) setState(() => _error = _authError(l10n, error));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.authUnexpected);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _authPage(
      context: context,
      title: l10n.forgotPasswordTitle,
      description: l10n.forgotPasswordBody,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: l10n.emailLabel),
        ),
        if (_sent) ...[
          const SizedBox(height: FarmSpacing.md),
          Text(l10n.resetRequested, key: const ValueKey('reset-requested')),
        ],
        if (_error != null) ...[
          const SizedBox(height: FarmSpacing.md),
          _InlineError(message: _error!),
        ],
        const SizedBox(height: FarmSpacing.lg),
        FilledButton(
          onPressed: _sending ? null : () => _submit(l10n),
          child: Text(l10n.sendResetLink),
        ),
        TextButton(
          onPressed: () =>
              context.go(_loginPath(ref.read(authFlowDraftProvider).returnTo)),
          child: Text(l10n.back),
        ),
      ],
    );
  }
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _complete = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations l10n) async {
    final password = _password.text;
    if (widget.token == null || widget.token!.trim().isEmpty) {
      setState(() => _error = l10n.invalidLinkBody);
      return;
    }
    if (password.length < 8 ||
        password.length > 128 ||
        password != _confirm.text) {
      setState(
        () => _error = password.length < 8 || password.isEmpty
            ? l10n.passwordTooShort
            : password.length > 128
            ? l10n.passwordTooLong
            : l10n.passwordsDoNotMatch,
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(farmlyAuthSessionProvider.notifier)
          .resetPassword(token: widget.token!, newPassword: password);
      if (mounted) setState(() => _complete = true);
    } on FarmlyAuthFailure catch (error) {
      if (mounted) setState(() => _error = _authError(l10n, error));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.authUnexpected);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasToken = widget.token?.trim().isNotEmpty ?? false;
    return _authPage(
      context: context,
      title: _complete
          ? l10n.passwordResetComplete
          : hasToken
          ? l10n.resetPasswordTitle
          : l10n.invalidLinkTitle,
      description: _complete
          ? l10n.passwordResetComplete
          : hasToken
          ? l10n.resetLinkInstructions
          : l10n.invalidLinkBody,
      children: [
        if (!_complete && hasToken) ...[
          _PasswordField(
            controller: _password,
            label: l10n.passwordLabel,
            autofillHint: AutofillHints.newPassword,
          ),
          const SizedBox(height: FarmSpacing.md),
          _PasswordField(
            controller: _confirm,
            label: l10n.confirmPasswordLabel,
            autofillHint: AutofillHints.newPassword,
          ),
          if (_error != null) ...[
            const SizedBox(height: FarmSpacing.md),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: FarmSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : () => _submit(l10n),
            child: Text(l10n.saveNewPassword),
          ),
        ] else if (!_complete) ...[
          const SizedBox(height: FarmSpacing.lg),
          TextButton(
            onPressed: () => context.go(AppRoutes.forgotPassword),
            child: Text(l10n.sendResetLink),
          ),
        ] else ...[
          FilledButton(
            onPressed: () => context.go(AppRoutes.login),
            child: Text(l10n.signIn),
          ),
        ],
      ],
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.autofillHint,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String autofillHint;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: [widget.autofillHint],
      inputFormatters: [LengthLimitingTextInputFormatter(128)],
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? l10n.showPassword : l10n.hidePassword,
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: FarmThemeExtension.of(context).semanticError,
      ),
    ),
  );
}

String _loginPath(String? returnTo) {
  return farmlyRouteWithReturnTo(AppRoutes.login, safeFarmlyReturnTo(returnTo));
}
