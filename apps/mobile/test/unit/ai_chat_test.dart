import 'dart:async';

import 'package:farmly_mobile/core/ai/ai_chat_repository.dart';
import 'package:farmly_mobile/core/ai/sse_decoder.dart';
import 'package:farmly_mobile/core/network/farmly_api_client.dart';
import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/core/sync/sync_providers.dart';
import 'package:farmly_mobile/features/chat/live_chat_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SseDecoder', () {
    test('decodes id/event/data frames split across chunks', () {
      final frames = <SseFrame>[];
      final decoder = SseDecoder(onFrame: frames.add);
      decoder.addChunk('id: req-1:2\neven');
      decoder.addChunk('t: response.delta\ndata: {"textDelta":"Hel');
      decoder.addChunk('lo"}\n\nid: req-1:3\ndata: {"x":1}\n\n');
      expect(frames, hasLength(2));
      expect(frames[0].id, 'req-1:2');
      expect(frames[0].event, 'response.delta');
      expect(frames[0].data, '{"textDelta":"Hello"}');
      expect(frames[1].id, 'req-1:3');
      decoder.close();
    });

    test('joins multi-line data and skips heartbeat comments', () {
      final frames = <SseFrame>[];
      final decoder = SseDecoder(onFrame: frames.add);
      decoder.addChunk(': hb 123\n\nid: r:1\ndata: a\ndata: b\n\n: hb 456\n\n');
      expect(frames, hasLength(1));
      expect(frames[0].data, 'a\nb');
      decoder.close();
    });

    test('normalizes CRLF and drops partial trailing frame on close', () {
      final frames = <SseFrame>[];
      final decoder = SseDecoder(onFrame: frames.add);
      decoder.addChunk('id: r:1\ndata: ok\r\n\r\nid: r:2\ndata: trun');
      expect(frames, hasLength(1));
      decoder.close();
      expect(frames, hasLength(1)); // trailing partial never emitted
    });
  });

  group('LiveChatController', () {
    const scope = '00000000-0000-4000-8000-000000000001';
    const farm = '00000000-0000-4000-8000-0000000000f1';

    ProviderContainer containerWith(_FakeAiRepository repo) =>
        ProviderContainer(
          overrides: [
            aiChatRepositoryProvider.overrideWithValue(repo),
            farmlySyncScopeProvider.overrideWithValue(
              FarmlyMutationScope.farm(
                accountId: '00000000-0000-4000-8000-0000000000aa',
                organizationId: scope,
                farmId: farm,
                continuityEpoch: '1',
              ),
            ),
          ],
        );

    test('send → deltas → completed lands a final answer', () async {
      final repo = _FakeAiRepository()
        ..events = [
          const AiStreamEvent(
            type: 'response.delta',
            id: 'r:1',
            data: {'textDelta': 'Hôm nay '},
          ),
          const AiStreamEvent(
            type: 'response.delta',
            id: 'r:2',
            data: {'textDelta': 'có 3 việc.'},
          ),
          const AiStreamEvent(
            type: 'response.references',
            id: 'r:3',
            data: {'sources': ['tasks:v1']},
          ),
          const AiStreamEvent(type: 'response.completed', id: 'r:4', data: {}),
        ];
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Tóm tắt việc hôm nay', contextMode: 'farm');
      await _drain();
      final state = container.read(liveChatControllerProvider);
      expect(state.phase, LiveChatPhase.terminal);
      final answer = state.messages.last;
      expect(answer.isUser, isFalse);
      expect(answer.text, 'Hôm nay có 3 việc.');
      expect(answer.footerSources, ['tasks:v1']);
      expect(repo.cancelled, isNull);
    });

    test('stop lands a labelled partial answer', () async {
      final repo = _FakeAiRepository()
        ..events = [
          const AiStreamEvent(
            type: 'response.delta',
            id: 'r:1',
            data: {'textDelta': 'Phần trả lời đã tạo'},
          ),
          const AiStreamEvent(type: 'response.cancelled', id: 'r:2', data: {}),
        ];
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Hỏi', contextMode: 'general');
      await _drain();
      await controller.stop();
      await _drain();
      final state = container.read(liveChatControllerProvider);
      expect(state.phase, LiveChatPhase.terminal);
      expect(state.messages.last.partialLabel, isNotNull);
      expect(repo.cancelled, isNotNull);
    });

    test('consent missing blocks the request without billing', () async {
      final repo = _FakeAiRepository()..consentGranted = false;
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Hỏi', contextMode: 'farm');
      final state = container.read(liveChatControllerProvider);
      expect(state.consentRequired, isTrue);
      expect(state.phase, LiveChatPhase.error);
      expect(repo.created, isNull); // no durable request was ever created
    });

    test('grantConsent resends the held prompt as a new request', () async {
      final repo = _FakeAiRepository()..consentGranted = false;
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Hỏi', contextMode: 'farm');
      expect(
        container.read(liveChatControllerProvider).consentRequired,
        isTrue,
      );
      await controller.grantConsent();
      await _drain();
      await _drain();
      expect(repo.grantCalled, isTrue);
      expect(repo.created, isNotNull); // fresh clientRequestId was created
      final state = container.read(liveChatControllerProvider);
      expect(state.consentRequired, isFalse);
      expect(state.messages.any((m) => m.isUser && m.text == 'Hỏi'), isTrue);
    });

    test('grantConsent failure keeps the consent-required state', () async {
      final repo = _FakeAiRepository()
        ..consentGranted = false
        ..failGrant = true;
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Hỏi', contextMode: 'farm');
      await controller.grantConsent();
      final state = container.read(liveChatControllerProvider);
      expect(state.phase, LiveChatPhase.error);
      expect(state.errorCode, 'UNAVAILABLE');
      expect(repo.created, isNull);
    });

    test('create failure surfaces error without a fake answer', () async {
      final repo = _FakeAiRepository()
        ..failCreate = const FarmlyApiFailure(FarmlyApiFailureCode.rateLimited);
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Hỏi', contextMode: 'farm');
      await _drain();
      final state = container.read(liveChatControllerProvider);
      expect(state.phase, LiveChatPhase.error);
      expect(state.errorCode, 'rateLimited');
      expect(state.messages.where((m) => m.isPlaceholder), isEmpty);
      expect(
        state.messages.where((m) => !m.isUser).map((m) => m.text),
        everyElement(isNot(contains('Hôm nay'))),
      );
    });

    test('stream error settles from durable status, never hangs', () async {
      final repo = _FakeAiRepository()
        ..streamError = true
        ..terminalStatus = 'completed';
      final container = containerWith(repo);
      addTearDown(container.dispose);
      final controller = container.read(liveChatControllerProvider.notifier);
      await controller.send('Hỏi', contextMode: 'farm');
      await _drain();
      await _drain();
      final state = container.read(liveChatControllerProvider);
      expect(state.phase, LiveChatPhase.terminal);
    });
  });
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

final class _FakeAiRepository implements AiChatRepository {
  List<AiStreamEvent> events = const [];
  bool consentGranted = true;
  bool streamError = false;
  String terminalStatus = 'completed';
  FarmlyApiFailure? failCreate;
  String? created;
  String? cancelled;

  @override
  Future<AiCreatedRequest> createRequest({
    required String organizationId,
    required String farmId,
    required String clientRequestId,
    required String prompt,
    required String contextMode,
    required int consentRevision,
    String? conversationId,
  }) async {
    if (failCreate != null) throw failCreate!;
    created = clientRequestId;
    return const AiCreatedRequest(
      requestId: 'req-1',
      conversationId: 'conv-1',
      state: 'queued',
      replayed: false,
    );
  }

  @override
  Future<AiRequestStatus> getRequest({
    required String organizationId,
    required String farmId,
    required String requestId,
  }) async => AiRequestStatus(
    requestId: requestId,
    status: terminalStatus,
    usageState: 'reported',
  );

  @override
  Future<AiRequestStatus> cancelRequest({
    required String organizationId,
    required String farmId,
    required String requestId,
  }) async {
    cancelled = requestId;
    return AiRequestStatus(
      requestId: requestId,
      status: 'stopping',
      usageState: 'reserved',
    );
  }

  @override
  Future<AiConsentSnapshot?> consent({
    required String organizationId,
    required String farmId,
  }) async => AiConsentSnapshot(
    granted: consentGranted,
    revision: 3,
    summaryOptedIn: false,
  );

  bool grantCalled = false;
  bool failGrant = false;

  @override
  Future<AiConsentSnapshot> grantConsent({
    required String organizationId,
    bool summaryOptedIn = false,
  }) async {
    if (failGrant) throw const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
    grantCalled = true;
    consentGranted = true;
    return const AiConsentSnapshot(
      granted: true,
      revision: 4,
      summaryOptedIn: false,
    );
  }

  @override
  Stream<AiStreamEvent> streamEvents({
    required String organizationId,
    required String farmId,
    required String requestId,
    String? resumeAfterId,
  }) {
    if (streamError) {
      return Stream<AiStreamEvent>.error(
        const FarmlyApiFailure(FarmlyApiFailureCode.unavailable),
      );
    }
    return Stream.fromIterable(events);
  }
}
