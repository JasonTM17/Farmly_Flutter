import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/chat_components.dart';
import '../../ui/farm_card.dart';
import '../../ui/illustrations.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../app/app_router.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';
import 'live_chat_controller.dart';

/// Contextual prompt chips on the welcome screen (localized).
List<String> _demoPrompts(AppLocalizations l10n) => [
  l10n.chatPromptTasksToday,
  l10n.chatPromptProductionMonth,
  l10n.chatPromptDataToCheck,
];

/// Chat welcome: Farmly AI title, scope chip, consent copy with data details
/// and history links, three useful prompts (spec 02 §6). Static UI only.
class ChatWelcomeScreen extends ConsumerWidget {
  const ChatWelcomeScreen({super.key});

  void _openConversation(
    BuildContext context,
    WidgetRef ref, {
    required bool contextual,
    String? prompt,
  }) {
    context.push(
      AppRoutes.chatConversation,
      extra: ChatRouteArguments(prompt: prompt, contextual: contextual),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final farm = farmById(state, state.selectedFarmId);
    final organization = organizationById(state, state.selectedOrganizationId);
    final consent = ref.watch(aiConsentProvider);
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Farmly AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FarmSpacing.lg),
          children: [
            const Center(child: SproutMark(size: 64)),
            const SizedBox(height: FarmSpacing.md),
            Center(
              child: Text(
                l10n.chatWelcomeTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
                softWrap: true,
              ),
            ),
            const SizedBox(height: FarmSpacing.md),
            Center(
              child: Semantics(
                label: l10n.chatScopeSemantics(
                  organization?.name ?? '',
                  farm?.name ?? '',
                ),
                child: Chip(
                  avatar: const Icon(Icons.landscape_outlined, size: 16),
                  label: Text(
                    '${organization?.name ?? ''} · ${farm?.name ?? ''}',
                    softWrap: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: FarmSpacing.lg),
            FarmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.chatPrivacyTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  Text(
                    l10n.chatConsentCopy,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => _showDataDetailsSheet(context),
                        child: Text(l10n.chatDataDetails),
                      ),
                      TextButton(
                        onPressed: () => _showHistorySheet(context),
                        child: Text(l10n.chatHistory),
                      ),
                    ],
                  ),
                  if (consent.decisionRecorded) ...[
                    const SizedBox(height: FarmSpacing.xs),
                    Text(
                      consent.contextualAccepted
                          ? l10n.chatConsentAccepted(consent.revision)
                          : l10n.chatGeneralModeActive,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              onPressed: () async {
                final liveScope =
                    ref.read(farmlySyncScopeProvider).value;
                final signedIn =
                    ref.read(farmlyAuthSessionProvider).value?.user != null;
                if (signedIn && liveScope != null) {
                  // Live lane: consent is a server decision bound to revision.
                  try {
                    await ref
                        .read(aiChatRepositoryProvider)
                        .grantConsent(
                          organizationId: liveScope.organizationId,
                        );
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.chatConsentFailed)),
                      );
                    }
                    return;
                  }
                } else {
                  ref.read(aiConsentProvider.notifier).acceptContextual();
                }
                if (!context.mounted) return;
                _openConversation(context, ref, contextual: true);
              },
              child: Text(l10n.chatConsentCta),
            ),
            const SizedBox(height: FarmSpacing.sm),
            OutlinedButton(
              onPressed: () {
                ref.read(aiConsentProvider.notifier).chooseGeneralMode();
                _openConversation(context, ref, contextual: false);
              },
              child: Text(l10n.chatGeneralModeCta),
            ),
            const SizedBox(height: FarmSpacing.xl),
            Text(
              l10n.chatSuggestionsTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FarmSpacing.sm),
            for (final prompt in _demoPrompts(l10n))
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
                child: FarmCard(
                  onTap: () {
                    // Contextual prompts never silently override a general-mode
                    // choice; ask the user to accept contextual data first.
                    final accepted = ref
                        .read(aiConsentProvider)
                        .contextualAccepted;
                    if (!accepted) {
                      showFarmToast(context, l10n.chatPromptNeedsConsent);
                      return;
                    }
                    _openConversation(
                      context,
                      ref,
                      contextual: true,
                      prompt: prompt,
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 18),
                      const SizedBox(width: FarmSpacing.sm),
                      Expanded(
                        child: Text(
                          prompt,
                          style: Theme.of(context).textTheme.bodyMedium,
                          softWrap: true,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDataDetailsSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(FarmSpacing.lg),
          children: [
            Text(
              l10n.chatDataDetailsTitle,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              l10n.chatDataDetailsBody,
              style: Theme.of(sheetContext).textTheme.bodyMedium,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }

  void _showHistorySheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(FarmSpacing.lg),
          children: [
            Text(
              l10n.chatHistory,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              l10n.chatHistoryBody,
              style: Theme.of(sheetContext).textTheme.bodyMedium,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ChatMessage {
  const _ChatMessage({
    required this.isUser,
    required this.text,
    this.isPlaceholder = false,
    this.footerSource,
    this.partialLabel,
  });

  final bool isUser;
  final String text;

  /// True while the assistant answer is still being generated.
  final bool isPlaceholder;
  final String? footerSource;

  /// Present on a stopped generation: labels the bubble as a partial answer.
  final String? partialLabel;
}

/// Conversation view: bubbles, source footer, stop/replay/new-request
/// separation and a 48dp+ composer. Every demo resource state is reachable
/// through the state switcher (spec 02 §5/§6). Generation is simulated
/// locally — no network call happens in this build — but the send →
/// generating → complete/stop transitions are real UI state, not toasts.
class ChatConversationScreen extends ConsumerStatefulWidget {
  const ChatConversationScreen({
    required this.contextual,
    this.initialPrompt,
    super.key,
  });

  final bool contextual;
  final String? initialPrompt;

  @override
  ConsumerState<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState
    extends ConsumerState<ChatConversationScreen> {
  static const _screenKey = 'chat-conversation';

  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _generationTimer;
  bool _generating = false;
  bool _showNewMessages = false;
  String? _generationNote;

  /// Demo seed conversation. `late final` so the arb-backed strings resolve
  /// against Localizations on first access (post-mount), not in initState.
  late final List<_ChatMessage> _messages = [
    _ChatMessage(
      isUser: true,
      text: widget.initialPrompt ?? AppLocalizations.of(context).chatDefaultPrompt,
    ),
    _ChatMessage(
      isUser: false,
      text: AppLocalizations.of(context).chatDemoAnswer,
      footerSource: AppLocalizations.of(context).chatDemoSource,
    ),
  ];

  /// Live lane is active only with a real auth session + farm scope; the demo
  /// simulation stays the fallback for unsigned/preview use.
  bool get _isLive =>
      ref.read(farmlyAuthSessionProvider).value?.user != null &&
      ref.read(farmlySyncScopeProvider).value?.farmId != null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_isLive && widget.initialPrompt != null) {
      // The user intentionally tapped a suggestion — that IS the request.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(widget.initialPrompt!);
      });
    }
  }

  @override
  void dispose() {
    _generationTimer?.cancel();
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 80;
  }

  void _onScroll() {
    if (_showNewMessages && _isNearBottom) {
      setState(() => _showNewMessages = false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: context.farmStateDuration(),
        curve: Curves.easeOut,
      );
    });
  }

  /// Autoscroll only when the user is near the bottom (spec 02 §6); scrolled
  /// away, new content raises the [NewMessagesButton] instead.
  void _appendMessage(_ChatMessage message) {
    final nearBottom = _isNearBottom;
    setState(() => _messages.add(message));
    if (nearBottom || message.isUser) {
      _scrollToBottomSoon();
    } else {
      setState(() => _showNewMessages = true);
    }
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_isLive) {
      final live = ref.read(liveChatControllerProvider);
      if (live.busy) return; // one durable request at a time (§6)
      _composerController.clear();
      ref
          .read(liveChatControllerProvider.notifier)
          .send(trimmed, contextMode: widget.contextual ? 'farm' : 'general');
      return;
    }
    if (_generating) return;
    _composerController.clear();
    _appendMessage(_ChatMessage(isUser: true, text: trimmed));
    _startGeneration(replay: false);
  }

  /// Live equivalents of the demo actions — replay re-attaches the same
  /// request (free); "new" re-sends the last prompt (billed, §6).
  void _liveStop() =>
      ref.read(liveChatControllerProvider.notifier).stop();

  void _liveResume() {
    final live = ref.read(liveChatControllerProvider);
    final requestId = live.requestId;
    if (requestId != null) {
      ref.read(liveChatControllerProvider.notifier).resume(requestId);
    }
  }

  void _liveNew() {
    final live = ref.read(liveChatControllerProvider);
    final lastPrompt = live.messages
        .where((m) => m.isUser)
        .map((m) => m.text)
        .lastOrNull;
    if (lastPrompt != null) _send(lastPrompt);
  }

  void _startGeneration({required bool replay}) {
    final l10n = AppLocalizations.of(context);
    _generationTimer?.cancel();
    setState(() {
      _generating = true;
      // §6: replay is the same request again (free); a new request bills.
      _generationNote = replay
          ? l10n.chatReplayNote
          : l10n.chatNewRequestNote;
      final placeholder = _ChatMessage(
        isUser: false,
        text: l10n.chatGenerating,
        isPlaceholder: true,
      );
      if (_messages.isNotEmpty && _messages.last.isPlaceholder) {
        _messages[_messages.length - 1] = placeholder;
      } else {
        _messages.add(placeholder);
      }
    });
    _scrollToBottomSoon();
    _generationTimer = Timer(
      const Duration(milliseconds: 1600),
      _completeGeneration,
    );
  }

  void _completeGeneration() {
    if (!mounted || !_generating) return;
    setState(() {
      _generating = false;
      if (_messages.isNotEmpty && _messages.last.isPlaceholder) {
        _messages[_messages.length - 1] = _ChatMessage(
          isUser: false,
          text: AppLocalizations.of(context).chatDemoAnswer,
          footerSource: AppLocalizations.of(context).chatDemoSource,
        );
      }
    });
    _scrollToBottomSoon();
  }

  /// Stop reaches the terminal partial state immediately; the partial answer
  /// stays visible and labelled (spec 02 §6).
  void _stopGeneration() {
    final l10n = AppLocalizations.of(context);
    _generationTimer?.cancel();
    setState(() {
      _generating = false;
      if (_messages.isNotEmpty && _messages.last.isPlaceholder) {
        _messages[_messages.length - 1] = _ChatMessage(
          isUser: false,
          text: l10n.chatPartialAnswer,
          partialLabel: l10n.chatPartialLabel,
        );
      }
    });
    _scrollToBottomSoon();
  }

  void _jumpToLatest() {
    setState(() => _showNewMessages = false);
    _scrollToBottomSoon();
  }

  Widget _messageBubble(BuildContext context, _ChatMessage message) {
    final tokens = FarmThemeExtension.of(context);
    if (message.isUser) {
      return ChatBubble(
        isUser: true,
        child: Text(message.text, softWrap: true),
      );
    }
    return ChatBubble(
      isUser: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.isPlaceholder)
            Semantics(
              liveRegion: true,
              label: AppLocalizations.of(context).chatGeneratingSemantics,
              child: Row(
                children: [
                  Expanded(child: Text(message.text, softWrap: true)),
                  const SizedBox(width: FarmSpacing.sm),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            )
          else
            Text(message.text, softWrap: true),
          if (message.partialLabel != null) ...[
            const SizedBox(height: FarmSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                message.partialLabel!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.semanticWarning),
                softWrap: true,
              ),
            ),
          ],
          if (message.footerSource != null)
            ChatSourceFooter(asOf: '06:30', source: message.footerSource!),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoDataProvider);
    final farm = farmById(state, state.selectedFarmId);
    final organization = organizationById(state, state.selectedOrganizationId);
    final tokens = FarmThemeExtension.of(context);
    final screenState = effectiveDemoState(ref, _screenKey, dataEmpty: false);
    final conflictCount = state.syncItems
        .where((item) => item.status == DemoSyncStatus.conflict)
        .length;
    final inputsEnabled = switch (screenState) {
      DemoLoadState.loading ||
      DemoLoadState.recoverableError ||
      DemoLoadState.permissionDenied => false,
      _ => true,
    };
    // Live lane: durable server state replaces the demo simulation whenever a
    // signed-in farm scope exists (spec05 §5–§7). Watching the scope keeps
    // the lane reactive; an errored scope renders the translated banner below
    // instead of throwing during build (spec02 §5).
    final liveScope = ref.watch(farmlySyncScopeProvider);
    final live = _isLive ? ref.watch(liveChatControllerProvider) : null;
    final l10n = AppLocalizations.of(context);
    final displayedMessages = live == null
        ? _messages
        : live.messages
              .map(
                (m) => _ChatMessage(
                  isUser: m.isUser,
                  text: m.text,
                  isPlaceholder: m.isPlaceholder,
                  partialLabel: m.partialLabel,
                  footerSource: m.footerSources == null
                      ? null
                      : l10n.chatSourcesCount(m.footerSources!.length),
                ),
              )
              .toList();
    final generating = live?.busy ?? _generating;
    final generationNote = live?.note ?? _generationNote;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Farmly AI')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                FarmSpacing.lg,
                FarmSpacing.sm,
                FarmSpacing.lg,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DemoStateSwitcher(screenKey: _screenKey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
              child: Row(
                children: [
                  Icon(
                    widget.contextual
                        ? Icons.landscape_outlined
                        : Icons.public_outlined,
                    size: 16,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: FarmSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.contextual
                          ? '${organization?.name ?? ''} · ${farm?.name ?? ''}'
                          : l10n.chatGeneralScope,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
            // Scope error: compact translated notice inside the safe area —
            // never the raw provider exception (spec02 §5).
            liveScope.when(
              data: (_) => const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  FarmSpacing.lg,
                  0,
                  FarmSpacing.lg,
                  FarmSpacing.sm,
                ),
                child: FarmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chatLiveScopeError,
                        style: Theme.of(context).textTheme.bodyMedium,
                        softWrap: true,
                      ),
                      const SizedBox(height: FarmSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(farmlySyncScopeProvider),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text(l10n.retry),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: switch (screenState) {
                DemoLoadState.loading => const _ChatSkeleton(),
                DemoLoadState.recoverableError => FarmErrorView(
                  onRetry: () => ref
                      .read(demoScreenStateProvider.notifier)
                      .reset(_screenKey),
                ),
                DemoLoadState.permissionDenied => PermissionDeniedView(
                  message: l10n.chatPermissionBody,
                  onSwitchScope: () => showFarmPickerSheet(context),
                ),
                DemoLoadState.empty => EmptyStateView(
                  title: l10n.chatEmptyTitle,
                  message: l10n.chatEmptyBody,
                ),
                DemoLoadState.offline ||
                DemoLoadState.pendingConflict ||
                DemoLoadState.success => Column(
                  children: [
                    if (screenState == DemoLoadState.offline) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: FarmSpacing.lg,
                        ),
                        child: OfflineBanner(asOf: '06:30'),
                      ),
                      const SizedBox(height: FarmSpacing.md),
                    ],
                    if (screenState == DemoLoadState.pendingConflict &&
                        conflictCount > 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FarmSpacing.lg,
                        ),
                        child: PendingConflictBanner(
                          count: conflictCount,
                          onOpen: () => context.push(AppRoutes.syncCenter),
                        ),
                      ),
                      const SizedBox(height: FarmSpacing.md),
                    ],
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(FarmSpacing.lg),
                            itemCount: displayedMessages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == displayedMessages.length) {
                                return _ConversationActions(
                                  generating: generating,
                                  note: generationNote,
                                  onStop: live != null
                                      ? _liveStop
                                      : _stopGeneration,
                                  onReplay: live != null
                                      ? (live.requestId != null
                                            ? _liveResume
                                            : () {})
                                      : () => _startGeneration(replay: true),
                                  onNew: live != null
                                      ? _liveNew
                                      : () => _startGeneration(replay: false),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: FarmSpacing.md,
                                ),
                                child: _messageBubble(
                                  context,
                                  displayedMessages[index],
                                ),
                              );
                            },
                          ),
                          if (_showNewMessages)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: FarmSpacing.md,
                              child: Center(
                                child: NewMessagesButton(onTap: _jumpToLatest),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              },
            ),
            if (live?.consentRequired == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FarmSpacing.lg,
                  0,
                  FarmSpacing.lg,
                  FarmSpacing.sm,
                ),
                child: FarmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chatConsentRequired,
                        style: Theme.of(context).textTheme.bodyMedium,
                        softWrap: true,
                      ),
                      const SizedBox(height: FarmSpacing.sm),
                      FilledButton(
                        onPressed: () => ref
                            .read(liveChatControllerProvider.notifier)
                            .grantConsent(),
                        child: Text(l10n.chatGrantConsent),
                      ),
                    ],
                  ),
                ),
              ),
            ChatComposer(
              controller: _composerController,
              enabled: inputsEnabled && !generating,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// Stop / replay / new-request controls. Replay and new request are separate
/// buttons with distinct quota semantics — never one ambiguous button (§6).
class _ConversationActions extends StatelessWidget {
  const _ConversationActions({
    required this.generating,
    required this.note,
    required this.onStop,
    required this.onReplay,
    required this.onNew,
  });

  final bool generating;
  final String? note;
  final VoidCallback onStop;
  final VoidCallback onReplay;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.start,
          spacing: FarmSpacing.sm,
          children: [
            TextButton(
              // Stop only applies while a request is in flight.
              onPressed: generating ? onStop : null,
              child: Text(l10n.chatStop),
            ),
            TextButton(
              onPressed: generating ? null : onReplay,
              child: Text(l10n.chatReplay),
            ),
            TextButton(
              onPressed: generating ? null : onNew,
              child: Text(l10n.chatNewAnswer),
            ),
          ],
        ),
        if (note != null)
          Semantics(
            liveRegion: true,
            child: Text(
              note!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
          ),
      ],
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FarmSpacing.lg),
      children: const [
        Align(
          alignment: Alignment.centerRight,
          child: SkeletonSurface(
            width: 220,
            height: 56,
            radius: FarmSpacing.cardRadius,
          ),
        ),
        SizedBox(height: FarmSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: SkeletonSurface(
            width: 280,
            height: 96,
            radius: FarmSpacing.cardRadius,
          ),
        ),
        SizedBox(height: FarmSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: SkeletonSurface(
            width: 180,
            height: 48,
            radius: FarmSpacing.cardRadius,
          ),
        ),
      ],
    );
  }
}
