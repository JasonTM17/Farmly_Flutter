import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/network/farmly_api_client.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../app/app_routes.dart';
import 'organization_repository.dart';
import 'organization_scope_controller.dart';

typedef FarmlyOrganizationListKey = ({int generation, String userId});

final farmlyOrganizationsProvider = FutureProvider.autoDispose
    .family<List<FarmlyOrganization>, FarmlyOrganizationListKey>((
      ref,
      key,
    ) async {
      final generation = ref.watch(farmlyAuthSessionGenerationProvider);
      final session = ref.watch(farmlyAuthSessionProvider).asData?.value;
      if (generation != key.generation || session?.user.id != key.userId) {
        return const <FarmlyOrganization>[];
      }
      final organizations = await ref
          .watch(organizationRepositoryProvider)
          .listAll();
      final currentSession = ref.read(farmlyAuthSessionProvider).asData?.value;
      if (ref.read(farmlyAuthSessionGenerationProvider) != key.generation ||
          currentSession?.user.id != key.userId) {
        return const <FarmlyOrganization>[];
      }
      return organizations;
    });

FarmlyOrganizationListKey? _activeOrganizationListKey(WidgetRef ref) {
  final session = ref.read(farmlyAuthSessionProvider).asData?.value;
  if (session == null) return null;
  return (
    generation: ref.read(farmlyAuthSessionGenerationProvider),
    userId: session.user.id,
  );
}

void _invalidateActiveOrganizationList(WidgetRef ref) {
  final key = _activeOrganizationListKey(ref);
  if (key != null) ref.invalidate(farmlyOrganizationsProvider(key));
}

class OrganizationFlowScreen extends ConsumerStatefulWidget {
  const OrganizationFlowScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  ConsumerState<OrganizationFlowScreen> createState() =>
      _OrganizationFlowScreenState();
}

class _OrganizationFlowScreenState
    extends ConsumerState<OrganizationFlowScreen> {
  final _name = TextEditingController();
  String? _loadingOrganizationId;
  String? _pendingCreateOperationId;
  bool _creating = false;
  String? _error;
  int _selectionGeneration = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _select(FarmlyOrganization organization) async {
    final l10n = AppLocalizations.of(context);
    final scopeController = ref.read(
      selectedOrganizationScopeProvider.notifier,
    );
    final ticket = scopeController.beginSelection();
    final generation = ++_selectionGeneration;
    setState(() {
      _loadingOrganizationId = organization.id;
      _error = null;
    });
    try {
      final directory = await ref
          .read(organizationRepositoryProvider)
          .loadFarmDirectory(organization.id);
      if (!mounted || !scopeController.isCurrent(ticket)) return;
      final selected = await scopeController.select(
        organization,
        directory,
        ticket: ticket,
      );
      if (!mounted || !selected || !scopeController.isCurrent(ticket)) return;
      _returnToPreviousOrTarget();
    } on FarmlyApiFailure catch (error) {
      if (mounted && scopeController.isCurrent(ticket)) {
        setState(
          () => _error = error.code == FarmlyApiFailureCode.permissionDenied
              ? l10n.farmDirectoryLoadFailed
              : l10n.organizationLoadFailed,
        );
      }
    } catch (_) {
      if (mounted && scopeController.isCurrent(ticket)) {
        setState(() => _error = l10n.organizationLoadFailed);
      }
    } finally {
      if (mounted && generation == _selectionGeneration) {
        setState(() => _loadingOrganizationId = null);
      }
    }
  }

  Future<void> _create(AppLocalizations l10n) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.organizationNameRequired);
      return;
    }
    final operationId = _pendingCreateOperationId ??= newFarmlyOperationId();
    final scopeController = ref.read(
      selectedOrganizationScopeProvider.notifier,
    );
    final ticket = scopeController.beginSelection();
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final repository = ref.read(organizationRepositoryProvider);
      final organization = await repository.create(
        name: name,
        operationId: operationId,
      );
      final directory = await repository.loadFarmDirectory(organization.id);
      if (!mounted || !scopeController.isCurrent(ticket)) return;
      final selected = await scopeController.select(
        organization,
        directory,
        ticket: ticket,
      );
      if (!mounted || !selected || !scopeController.isCurrent(ticket)) return;
      _pendingCreateOperationId = null;
      _invalidateActiveOrganizationList(ref);
      _returnToPreviousOrTarget();
    } on FarmlyApiFailure catch (error) {
      if (mounted && scopeController.isCurrent(ticket)) {
        setState(
          () => _error = error.code == FarmlyApiFailureCode.permissionDenied
              ? l10n.farmDirectoryLoadFailed
              : l10n.organizationCreateFailed,
        );
      }
    } catch (_) {
      if (mounted && scopeController.isCurrent(ticket)) {
        setState(() => _error = l10n.organizationCreateFailed);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _returnToPreviousOrTarget() {
    final target = safeFarmlyReturnTo(widget.returnTo);
    if (target != null) {
      context.go(target);
      return;
    }
    context.go(AppRoutes.home);
  }

  String _roleLabel(AppLocalizations l10n, FarmlyOrganizationRole role) =>
      switch (role) {
        FarmlyOrganizationRole.owner => l10n.roleOwner,
        FarmlyOrganizationRole.admin => l10n.roleAdmin,
        FarmlyOrganizationRole.member => l10n.roleWorker,
        FarmlyOrganizationRole.viewer => l10n.roleViewer,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final session = ref.watch(farmlyAuthSessionProvider).asData?.value;
    final generation = ref.watch(farmlyAuthSessionGenerationProvider);
    final organizations = session == null
        ? const AsyncLoading<List<FarmlyOrganization>>()
        : ref.watch(
            farmlyOrganizationsProvider((
              generation: generation,
              userId: session.user.id,
            )),
          );
    return FarmScaffold(
      topBar: FarmTopBar(title: l10n.organizationTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          0,
          FarmSpacing.lg,
          FarmSpacing.xxl,
        ),
        children: [
          Text(
            l10n.organizationTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: FarmSpacing.md),
          organizations.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(FarmSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => FarmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.organizationLoadFailed),
                  TextButton(
                    onPressed: () => _invalidateActiveOrganizationList(ref),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
            data: (items) => Column(
              children: [
                if (items.isEmpty)
                  FarmCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.organizationEmptyTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: FarmSpacing.xs),
                        Text(
                          l10n.organizationEmptyBody,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                for (final organization in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
                    child: FarmCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(organization.name),
                        subtitle: Text(_roleLabel(l10n, organization.role)),
                        trailing:
                            organization.status ==
                                FarmlyOrganizationStatus.active
                            ? const Icon(Icons.chevron_right)
                            : Text(l10n.organizationStatusSuspended),
                        onTap:
                            organization.status ==
                                    FarmlyOrganizationStatus.active &&
                                _loadingOrganizationId == null
                            ? () => _select(organization)
                            : null,
                        leading: _loadingOrganizationId == organization.id
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.apartment_outlined,
                                color: tokens.brandAction,
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: FarmSpacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: tokens.semanticError),
              ),
            ),
          ],
          const SizedBox(height: FarmSpacing.lg),
          FarmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.organizationNameLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: FarmSpacing.sm),
                TextField(
                  controller: _name,
                  enabled: !_creating,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _pendingCreateOperationId = null,
                  onSubmitted: (_) => _create(l10n),
                  decoration: InputDecoration(
                    labelText: l10n.organizationNameLabel,
                  ),
                ),
                const SizedBox(height: FarmSpacing.md),
                FilledButton(
                  onPressed: _creating ? null : () => _create(l10n),
                  child: Text(
                    _creating
                        ? l10n.creatingOrganization
                        : l10n.createOrganization,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InvitationAcceptanceScreen extends ConsumerStatefulWidget {
  const InvitationAcceptanceScreen({
    required this.organizationId,
    required this.invitationId,
    required this.token,
    super.key,
  });

  final String? organizationId;
  final String? invitationId;
  final String? token;

  @override
  ConsumerState<InvitationAcceptanceScreen> createState() =>
      _InvitationAcceptanceScreenState();
}

class _InvitationAcceptanceScreenState
    extends ConsumerState<InvitationAcceptanceScreen> {
  String? _operationId;
  bool _accepting = false;
  String? _error;

  String _message(AppLocalizations l10n, FarmlyApiFailure error) =>
      switch (error.code) {
        FarmlyApiFailureCode.invitationExpired => l10n.inviteExpired,
        FarmlyApiFailureCode.invitationRevoked => l10n.inviteRevoked,
        FarmlyApiFailureCode.invitationEmailMismatch =>
          l10n.inviteEmailMismatch,
        FarmlyApiFailureCode.invitationAlreadyAccepted =>
          l10n.inviteAlreadyAccepted,
        FarmlyApiFailureCode.invitationUnavailable ||
        FarmlyApiFailureCode.notFound => l10n.inviteUnavailable,
        _ => l10n.inviteAcceptFailed,
      };

  Future<void> _accept(AppLocalizations l10n) async {
    final organizationId = widget.organizationId;
    final invitationId = widget.invitationId;
    final token = widget.token;
    if (organizationId == null || invitationId == null || token == null) {
      setState(() => _error = l10n.inviteInvalidBody);
      return;
    }
    final operationId = _operationId ??= newFarmlyOperationId();
    final scopeController = ref.read(
      selectedOrganizationScopeProvider.notifier,
    );
    final ticket = scopeController.beginSelection();
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      final repository = ref.read(organizationRepositoryProvider);
      await repository.acceptInvitation(
        organizationId: organizationId,
        invitationId: invitationId,
        token: token,
        operationId: operationId,
      );
      final organizations = await repository.listAll();
      FarmlyOrganization? organization;
      for (final item in organizations) {
        if (item.id == organizationId) {
          organization = item;
          break;
        }
      }
      if (organization == null) {
        throw const FarmlyApiFailure(FarmlyApiFailureCode.unexpected);
      }
      final directory = await repository.loadFarmDirectory(organization.id);
      if (!mounted || !scopeController.isCurrent(ticket)) return;
      final selected = await scopeController.select(
        organization,
        directory,
        ticket: ticket,
      );
      if (!mounted || !selected || !scopeController.isCurrent(ticket)) return;
      _invalidateActiveOrganizationList(ref);
      context.go(AppRoutes.home);
    } on FarmlyApiFailure catch (error) {
      if (mounted && scopeController.isCurrent(ticket)) {
        setState(() => _error = _message(l10n, error));
      }
    } catch (_) {
      if (mounted && scopeController.isCurrent(ticket)) {
        setState(() => _error = l10n.inviteAcceptFailed);
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final valid =
        widget.organizationId != null &&
        widget.invitationId != null &&
        widget.token != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(widget.token!);
    return FarmScaffold(
      topBar: FarmTopBar(title: l10n.inviteAccept),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(FarmSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: FarmCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        valid ? l10n.inviteAccept : l10n.inviteInvalidTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: FarmSpacing.md),
                      Text(
                        valid ? l10n.organizationTitle : l10n.inviteInvalidBody,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: FarmSpacing.md),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: FarmThemeExtension.of(
                                context,
                              ).semanticError,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: FarmSpacing.lg),
                      FilledButton(
                        onPressed: valid && !_accepting
                            ? () => _accept(l10n)
                            : null,
                        child: Text(
                          _accepting ? l10n.inviteAccepting : l10n.inviteAccept,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
