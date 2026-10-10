import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_chat_repository.dart';
import '../../core/network/farmly_api_client.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';

/// One message in the live AI lane — same display model the demo path uses.
final class LiveChatMessage {
  const LiveChatMessage({
    required this.isUser,
    required this.text,
    this.isPlaceholder = false,
    this.partialLabel,
    this.footerSources,
  });

  final bool isUser;
  final String text;
  final bool isPlaceholder;
  final String? partialLabel;

  /// `response.references` source ids — rendered as the data-source footer.
  final List<String>? footerSources;
}

enum LiveChatPhase {
  idle,
  sending,
  generating,
  stopping,

  /// Terminal reached (completed/cancelled/interrupted) — composer re-enabled.
  terminal,
  error,
}

final class LiveChatState {
  const LiveChatState({
    required this.phase,
    required this.messages,
    this.requestId,
    this.conversationId,
    this.note,
    this.errorCode,
    this.consentRequired = false,
  });

  const LiveChatState.idle()
    : phase = LiveChatPhase.idle,
      messages = const <LiveChatMessage>[],
      requestId = null,
      conversationId = null,
      note = null,
      errorCode = null,
      consentRequired = false;

  final LiveChatPhase phase;
  final List<LiveChatMessage> messages;
  final String? requestId;
  final String? conversationId;

  /// Small status line under the app bar (queued/generating/stopping notes).
  final String? note;
  final String? errorCode;
  final bool consentRequired;

  bool get busy =>
      phase == LiveChatPhase.sending ||
      phase == LiveChatPhase.generating ||
      phase == LiveChatPhase.stopping;

  LiveChatState copyWith({
    LiveChatPhase? phase,
    List<LiveChatMessage>? messages,
    String? requestId,
    String? conversationId,
    String? note,
    String? errorCode,
    bool? consentRequired,
    bool clearNote = false,
    bool clearError = false,
  }) => LiveChatState(
    phase: phase ?? this.phase,
    messages: messages ?? this.messages,
    requestId: requestId ?? this.requestId,
    conversationId: conversationId ?? this.conversationId,
    note: clearNote ? null : (note ?? this.note),
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    consentRequired: consentRequired ?? this.consentRequired,
  );
}

final aiChatRepositoryProvider = Provider<AiChatRepository>(
  (ref) => AiChatRepository(ref.watch(farmlyApiClientProvider)),
);

/// Live AI lane bound to the current signed-in org+farm scope. Replaces the
/// demo generation path when a scope + server consent exist; every state the
/// UI shows comes from durable server truth — queued/generating/stopping/
/// interrupted/completed/error. Never fabricates an answer locally.
final class LiveChatController extends Notifier<LiveChatState> {
  StreamSubscription<AiStreamEvent>? _subscription;
  String? _lastEventId;
  String? _attachedRequestId;
  String? _pendingPrompt;
  String? _pendingContextMode;

  @override
  LiveChatState build() {
    // Scope changes dispose in-flight state — a stream must never cross an
    // organization/farm boundary (spec05 §7).
    ref.watch(farmlySyncScopeProvider);
    ref.onDispose(() => _subscription?.cancel());
    return const LiveChatState.idle();
  }

  AiChatRepository get _repository => ref.read(aiChatRepositoryProvider);

  ({String organizationId, String farmId})? get _scope {
    final scope = ref.read(farmlySyncScopeProvider);
    final farmId = scope?.farmId;
    if (scope == null || farmId == null) return null;
    return (organizationId: scope.organizationId, farmId: farmId);
  }

  /// Send a new durable request — costs quota (spec05 §3). Replay/reconnect
  /// of an existing request is a separate, free path ([resume]).
  Future<void> send(String prompt, {required String contextMode}) async {
    final scope = _scope;
    final repository = _repository;
    if (scope == null) {
      state = state.copyWith(
        phase: LiveChatPhase.error,
        errorCode: 'OFFLINE_OR_SIGNED_OUT',
        note: 'Đăng nhập và chọn nông trại để dùng Farmly AI.',
      );
      return;
    }
    final consent = await repository
        .consent(organizationId: scope.organizationId, farmId: scope.farmId)
        .catchError((_) => null);
    if (!ref.mounted) return;
    if (consent == null || !consent.granted) {
      _pendingPrompt = prompt;
      _pendingContextMode = contextMode;
      state = state.copyWith(
        phase: LiveChatPhase.error,
        consentRequired: true,
        errorCode: 'AI_CONSENT_REQUIRED',
        note: 'Cần đồng ý sử dụng dữ liệu trang trại cho Farmly AI.',
      );
      return;
    }
    _pendingPrompt = null;
    _pendingContextMode = null;
    state = state.copyWith(
      phase: LiveChatPhase.sending,
      messages: [
        ...state.messages,
        LiveChatMessage(isUser: true, text: prompt),
        const LiveChatMessage(
          isUser: false,
          text: 'Đang tạo câu trả lời…',
          isPlaceholder: true,
        ),
      ],
      note: 'Yêu cầu mới — sẽ tính vào hạn mức AI của bạn.',
      clearError: true,
    );
    try {
      final created = await repository.createRequest(
        organizationId: scope.organizationId,
        farmId: scope.farmId,
        clientRequestId: newOperationId(),
        prompt: prompt,
        contextMode: contextMode,
        consentRevision: consent.revision,
        conversationId: state.conversationId,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        requestId: created.requestId,
        conversationId: created.conversationId,
      );
      _attach(created.requestId);
    } on FarmlyApiFailure catch (failure) {
      _popPlaceholder();
      state = state.copyWith(
        phase: LiveChatPhase.error,
        errorCode: failure.code.name,
        consentRequired: failure.code == FarmlyApiFailureCode.permissionDenied,
        note: _noteForFailure(failure),
      );
    } catch (_) {
      _popPlaceholder();
      state = state.copyWith(
        phase: LiveChatPhase.error,
        errorCode: 'UNAVAILABLE',
        note: 'Không kết nối được máy chủ — tin nhắn chưa được gửi.',
      );
    }
  }

  /// Grant private AI consent on the server (PUT /ai/consent), then resend the
  /// prompt that was held. The grant binds the returned revision — the resent
  /// request is a new clientRequestId, never a retry of a rejected create.
  Future<void> grantConsent() async {
    final scope = _scope;
    final repository = _repository;
    final prompt = _pendingPrompt;
    if (scope == null || prompt == null) return;
    try {
      await repository.grantConsent(organizationId: scope.organizationId);
    } catch (_) {
      state = state.copyWith(
        phase: LiveChatPhase.error,
        errorCode: 'UNAVAILABLE',
        note: 'Chưa lưu được đồng thuận — hãy thử lại.',
      );
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(consentRequired: false, clearError: true);
    await send(prompt, contextMode: _pendingContextMode ?? 'farm');
  }

  /// Re-attach to an in-flight request after a disconnect — free, replays the
  /// durable event log at the persisted cursor (spec05 §5).
  Future<void> resume(String requestId, {String? resumeAfterId}) async {
    final scope = _scope;
    if (scope == null) return;
    state = state.copyWith(
      phase: LiveChatPhase.generating,
      requestId: requestId,
      note: 'Kết nối lại yêu cầu đang chạy — không tính hạn mức thêm.',
    );
    _attach(requestId, resumeAfterId: resumeAfterId ?? _lastEventId);
  }

  /// POST cancel — distinguishes queued vs post-fence on the server; the
  /// partial answer stays labelled when the terminal event lands.
  Future<void> stop() async {
    final scope = _scope;
    final repository = _repository;
    final requestId = state.requestId;
    if (scope == null || requestId == null) return;
    state = state.copyWith(
      phase: LiveChatPhase.stopping,
      note: 'Đang dừng yêu cầu…',
    );
    try {
      await repository.cancelRequest(
        organizationId: scope.organizationId,
        farmId: scope.farmId,
        requestId: requestId,
      );
      // Terminal 'response.cancelled' arrives on the stream; if the stream
      // already closed, poll once so the UI never wedges in 'stopping'.
      if (_subscription == null) await _settleFromStatus(requestId);
    } on FarmlyApiFailure catch (failure) {
      if (failure.code == FarmlyApiFailureCode.notFound) {
        await _subscription?.cancel();
        _subscription = null;
        state = state.copyWith(
          phase: LiveChatPhase.error,
          errorCode: 'NOT_FOUND',
          clearNote: true,
        );
      }
    }
  }

  void clearError() {
    if (state.phase == LiveChatPhase.error) {
      state = state.copyWith(
        phase: LiveChatPhase.idle,
        clearError: true,
        clearNote: true,
      );
    }
  }

  void _attach(String requestId, {String? resumeAfterId}) {
    if (_attachedRequestId == requestId && _subscription != null) return;
    _subscription?.cancel();
    _attachedRequestId = requestId;
    _lastEventId = resumeAfterId;
    final scope = _scope;
    final repository = _repository;
    if (scope == null) return;
    if (state.phase != LiveChatPhase.stopping) {
      state = state.copyWith(
        phase: LiveChatPhase.generating,
        note: state.note ?? 'Đang tạo câu trả lời…',
      );
    }
    _subscription = repository
        .streamEvents(
          organizationId: scope.organizationId,
          farmId: scope.farmId,
          requestId: requestId,
          resumeAfterId: resumeAfterId,
        )
        .listen(
          _onEvent,
          onError: (_) => _settleFromStatus(requestId),
          onDone: () {
            _subscription = null;
            if (ref.mounted && state.busy) _settleFromStatus(requestId);
          },
        );
  }

  void _onEvent(AiStreamEvent event) {
    if (!ref.mounted) return;
    if (event.id.isNotEmpty) _lastEventId = event.id;
    switch (event.type) {
      case 'request.status':
        final next = event.data['status'] as String?;
        if (next == 'stopping') {
          state = state.copyWith(phase: LiveChatPhase.stopping);
        }
      case 'response.delta':
        final delta = event.data['textDelta'] as String? ?? '';
        _appendDelta(delta);
      case 'response.references':
        final sources = (event.data['sources'] as List?)
            ?.whereType<String>()
            .toList();
        _setFooter(sources);
      case 'response.completed':
        _complete();
      case 'response.cancelled':
        _cancelled();
      case 'response.error':
        state = state.copyWith(
          phase: LiveChatPhase.error,
          errorCode: 'RESPONSE_ERROR',
          note: 'Yêu cầu gặp lỗi — bạn không bị tính phí phần không hoàn thành.',
        );
      case 'request.started' || 'usage.reported':
        break; // provenance/usage — nothing to render
    }
  }

  void _appendDelta(String delta) {
    if (delta.isEmpty) return;
    final messages = [...state.messages];
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && !last.isUser && last.isPlaceholder) {
      messages[messages.length - 1] = LiveChatMessage(
        isUser: false,
        text: last.text == 'Đang tạo câu trả lời…' ? delta : last.text + delta,
        isPlaceholder: true,
      );
    } else {
      messages.add(
        LiveChatMessage(isUser: false, text: delta, isPlaceholder: true),
      );
    }
    state = state.copyWith(messages: messages);
  }

  void _setFooter(List<String>? sources) {
    if (sources == null || sources.isEmpty) return;
    final messages = [...state.messages];
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && !last.isUser) {
      messages[messages.length - 1] = LiveChatMessage(
        isUser: false,
        text: last.text,
        isPlaceholder: last.isPlaceholder,
        partialLabel: last.partialLabel,
        footerSources: sources,
      );
      state = state.copyWith(messages: messages);
    }
  }

  void _complete() {
    final messages = [...state.messages];
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && !last.isUser && last.isPlaceholder) {
      messages[messages.length - 1] = LiveChatMessage(
        isUser: false,
        text: last.text == 'Đang tạo câu trả lời…' ? '(trống)' : last.text,
        footerSources: last.footerSources,
      );
    }
    state = state.copyWith(
      phase: LiveChatPhase.terminal,
      messages: messages,
      clearNote: true,
    );
  }

  void _cancelled() {
    final messages = [...state.messages];
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && !last.isUser && last.isPlaceholder) {
      messages[messages.length - 1] = LiveChatMessage(
        isUser: false,
        text: last.text,
        partialLabel:
            'Đã dừng tạo — câu trả lời một phần, chưa hoàn chỉnh.',
        footerSources: last.footerSources,
      );
    }
    state = state.copyWith(
      phase: LiveChatPhase.terminal,
      messages: messages,
      clearNote: true,
    );
  }

  void _popPlaceholder() {
    final messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.isPlaceholder) {
      messages.removeLast();
    }
    state = state.copyWith(messages: messages);
  }

  /// Stream ended without a terminal frame (drop/revoke) — settle from the
  /// durable status once so the UI lands on truth, not a spinner.
  Future<void> _settleFromStatus(String requestId) async {
    final scope = _scope;
    final repository = _repository;
    if (scope == null) return;
    try {
      final status = await repository.getRequest(
        organizationId: scope.organizationId,
        farmId: scope.farmId,
        requestId: requestId,
      );
      if (!ref.mounted) return;
      if (status.status == 'interrupted') {
        state = state.copyWith(
          phase: LiveChatPhase.terminal,
          note:
              'Yêu cầu bị gián đoạn — có thể kết nối lại để xem phần đã tạo.',
        );
      } else if (status.isTerminal) {
        state = state.copyWith(phase: LiveChatPhase.terminal, clearNote: true);
      } else {
        // Still running — keep generating state; the caller may re-attach.
        state = state.copyWith(phase: LiveChatPhase.generating);
      }
    } on FarmlyApiFailure catch (failure) {
      state = state.copyWith(
        phase: LiveChatPhase.error,
        errorCode: failure.code.name,
      );
    }
  }

  String _noteForFailure(FarmlyApiFailure failure) => switch (failure.code) {
    FarmlyApiFailureCode.rateLimited =>
      'Đã tới hạn mức hoặc tần suất AI — thử lại sau.',
    FarmlyApiFailureCode.permissionDenied =>
      'Cần quyền truy cập hoặc đồng ý dữ liệu cho Farmly AI.',
    FarmlyApiFailureCode.conflict =>
      'Yêu cầu xung đột trạng thái — đã giữ nguyên bản ghi hiện tại.',
    FarmlyApiFailureCode.unavailable =>
      'Máy chủ AI tạm thời không sẵn sàng — tin nhắn chưa được gửi.',
    _ => 'Không gửi được yêu cầu — thử lại sau.',
  };
}

final liveChatControllerProvider =
    NotifierProvider<LiveChatController, LiveChatState>(
      LiveChatController.new,
    );
