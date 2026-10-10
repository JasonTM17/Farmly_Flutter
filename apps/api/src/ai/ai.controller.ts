import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Headers,
  HttpCode,
  Injectable,
  NotFoundException,
  Param,
  Post,
  Put,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { parseUuid, UUID_PATTERN } from '../common/mutations/mutation-kernel.controller.js';
import { FarmlyAiService } from './ai.service.js';
import { AiDispatcherService } from './ai-dispatcher.service.js';
import { actorPseudonym } from '../common/mutations/mutation-kernel.service.js';

// Contract AiCreateRequest: schemaVersion farmly-ai-request.v1, strict shape.
const AiCreateRequestSchema = z.object({
  schemaVersion: z.literal('farmly-ai-request.v1'),
  clientRequestId: z.string().regex(UUID_PATTERN),
  conversationId: z.string().regex(UUID_PATTERN).nullish(),
  prompt: z.string().min(1).max(12000),
  consentRevision: z.number().int().min(1),
  contextMode: z.enum(['authorized-summary', 'none']),
}).strict();

const AiCancelRequestSchema = z.object({
  reason: z.string().max(200).optional(),
}).strict();

// Contract AiConsentDecision: per-(user, org) consent singleton.
const AiConsentDecisionSchema = z.object({
  granted: z.boolean(),
  aiSafeSummaryOptedIn: z.boolean().optional().default(false),
}).strict();

const EVENT_STREAM_HEADERS = {
  'Content-Type': 'text/event-stream; charset=utf-8',
  'Cache-Control': 'private, no-cache, no-transform',
  Pragma: 'no-cache',
  Connection: 'keep-alive',
  'X-Accel-Buffering': 'no',
} as const;

const SSE_POLL_MS = 400;
const SSE_HEARTBEAT_MS = 9_000;

// Minimal structural view of the Express response used by the SSE handler —
// the project deliberately does not depend on @types/express.
interface SseResponse {
  setHeader(name: string, value: string): void;
  status(code: number): unknown;
  flushHeaders(): void;
  write(chunk: string): void;
  end(): void;
  on(event: 'close', listener: () => void): void;
}

@Controller('v1/organizations/:orgId/farms/:farmId/ai')
@UseGuards(VerifiedSessionGuard)
export class FarmlyAiController {
  constructor(
    private readonly ai: FarmlyAiService,
    private readonly dispatcher: AiDispatcherService,
  ) {}

  private ids(organizationIdInput: string, farmIdInput: string) {
    return {
      organizationId: parseUuid(organizationIdInput, 'Invalid organization ID'),
      farmId: parseUuid(farmIdInput, 'Invalid farm ID'),
    };
  }

  @Post('requests')
  @HttpCode(202)
  @Header('Cache-Control', 'private, no-store')
  async createRequest(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Headers('idempotency-key') idempotencyKey: string | string[] | undefined,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.ids(organizationIdInput, farmIdInput);
    const parsed = AiCreateRequestSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid AI request');
    const key = Array.isArray(idempotencyKey) ? idempotencyKey[0] : idempotencyKey;
    if (!key || key !== parsed.data.clientRequestId) {
      throw new BadRequestException('Idempotency-Key must equal clientRequestId');
    }
    const result = await this.ai.createRequest(principal, organizationId, farmId, {
      clientRequestId: parsed.data.clientRequestId,
      conversationId: parsed.data.conversationId ?? null,
      prompt: parsed.data.prompt,
      consentRevision: parsed.data.consentRevision,
      contextMode: parsed.data.contextMode,
    });
    const requestId = String(result['requestId']);
    // Hand the durable request to the dispatch fence worker (spec05 §4) and
    // sweep any other queued rows still owned by this caller.
    this.dispatcher.enqueue(requestId, {
      actorId: principal.actorId,
      pseudonym: actorPseudonym(principal.actorId),
    });
    void this.dispatcher.enqueueForOwner(principal);
    return {
      data: {
        requestId,
        conversationId: result['conversationId'],
        state: result['status'],
        replayed: Boolean(result['replayed']),
        eventsUrl: `/v1/organizations/${organizationId}/farms/${farmId}/ai/requests/${requestId}/events`,
        statusUrl: `/v1/organizations/${organizationId}/farms/${farmId}/ai/requests/${requestId}`,
      },
    };
  }

  @Get('requests/:requestId')
  @Header('Cache-Control', 'private, no-store')
  async getRequest(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('requestId') requestIdInput: string,
  ) {
    const { organizationId, farmId } = this.ids(organizationIdInput, farmIdInput);
    const requestId = parseUuid(requestIdInput, 'Invalid request ID');
    const row = await this.ai.getRequest(principal, organizationId, farmId, requestId);
    return { data: row };
  }

  @Post('requests/:requestId/cancel')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async cancelRequest(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('requestId') requestIdInput: string,
    @Body() body: unknown,
  ) {
    const { organizationId, farmId } = this.ids(organizationIdInput, farmIdInput);
    const requestId = parseUuid(requestIdInput, 'Invalid request ID');
    const parsed = AiCancelRequestSchema.safeParse(body ?? {});
    if (!parsed.success) throw new BadRequestException('Invalid cancel request');
    const result = await this.ai.cancelRequest(principal, organizationId, farmId, requestId);
    return { data: { requestId, state: result['status'], dispatched: result['dispatched'] } };
  }

  /**
   * SSE: replay persisted events after Last-Event-ID, then tail the durable
   * log until terminal. Persisted-before-emission is structural — the stream
   * only ever reads committed rows (spec05 §5). A disconnect never cancels
   * the background generation.
   */
  @Get('requests/:requestId/events')
  async streamEvents(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('requestId') requestIdInput: string,
    @Headers('last-event-id') lastEventId: string | string[] | undefined,
    @Res() response: SseResponse,
  ) {
    const { organizationId, farmId } = this.ids(organizationIdInput, farmIdInput);
    const requestId = parseUuid(requestIdInput, 'Invalid request ID');
    const lastRaw = Array.isArray(lastEventId) ? lastEventId[0] : lastEventId;
    let lastSeq = 0;
    if (lastRaw) {
      const match = /^(.+):(\d+)$/.exec(lastRaw);
      // Last-Event-ID is bound to this exact private request (spec05 §5).
      if (!match || match[1] !== requestId) throw new BadRequestException('Invalid Last-Event-ID');
      lastSeq = Number.parseInt(match[2], 10);
    }
    if (!(await this.ai.requestExistsForOwner(principal, organizationId, farmId, requestId))) {
      throw new NotFoundException({ code: 'NOT_FOUND' });
    }
    if (lastSeq > 0) {
      // Future seq is a client-protocol error, not a replay boundary
      // (spec05 §5): wrong request id was already rejected above.
      const status = await this.ai.getRequest(principal, organizationId, farmId, requestId);
      if (lastSeq > Number.parseInt(String(status['latestSeq'] ?? '0'), 10)) {
        throw new BadRequestException('Invalid Last-Event-ID');
      }
    }

    for (const [name, value] of Object.entries(EVENT_STREAM_HEADERS)) response.setHeader(name, value);
    response.status(200);
    response.flushHeaders();

    let closed = false;
    response.on('close', () => { closed = true; });
    let lastHeartbeat = Date.now();

    while (!closed) {
      // Live grant recheck on every emission batch (spec05 §5): revoke or
      // session change closes the stream with bounded detection.
      if (!(await this.ai.canStillReadFarm(principal, organizationId, farmId))) break;
      const page = await this.ai
        .readEventPage(principal, organizationId, farmId, requestId, lastSeq)
        .catch(() => null);
      if (page === null) break;
      for (const event of page.events) {
        const seq = Number.parseInt(String(event['seq']), 10);
        response.write(`id: ${event['id']}\n`);
        response.write(`event: ${event['type']}\n`);
        response.write(`data: ${JSON.stringify(event['data'])}\n\n`);
        lastSeq = Math.max(lastSeq, seq);
      }
      if (page.terminal && page.events.length === 0) break;
      if (page.terminal) {
        // Terminal event already emitted this batch — the next loop's empty
        // page confirms; emit nothing further after terminal data.
        const tail = await this.ai
          .readEventPage(principal, organizationId, farmId, requestId, lastSeq)
          .catch(() => null);
        if (tail && tail.events.length === 0 && tail.terminal) break;
      }
      const now = Date.now();
      if (now - lastHeartbeat >= SSE_HEARTBEAT_MS) {
        // Heartbeats are comments, never persisted semantic events.
        response.write(`: hb ${now}\n\n`);
        lastHeartbeat = now;
      }
      await new Promise((done) => setTimeout(done, SSE_POLL_MS));
    }
    if (!closed) response.end();
  }

  @Get('conversations')
  @Header('Cache-Control', 'private, no-store')
  async listConversations(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
  ) {
    const { organizationId, farmId } = this.ids(organizationIdInput, farmIdInput);
    return { data: await this.ai.listConversations(principal, organizationId, farmId) };
  }

  @Get('conversations/:conversationId/messages')
  @Header('Cache-Control', 'private, no-store')
  async listMessages(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Param('farmId') farmIdInput: string,
    @Param('conversationId') conversationIdInput: string,
    @Query('before') before: string | undefined,
    @Query('limit') limitInput: string | undefined,
  ) {
    const { organizationId, farmId } = this.ids(organizationIdInput, farmIdInput);
    const conversationId = parseUuid(conversationIdInput, 'Invalid conversation ID');
    const limit = limitInput ? Number.parseInt(limitInput, 10) : undefined;
    if (limitInput !== undefined && (!Number.isInteger(limit) || (limit as number) < 1)) {
      throw new BadRequestException('Invalid limit');
    }
    return {
      data: await this.ai.listMessages(
        principal, organizationId, farmId, conversationId, before, limit,
      ),
    };
  }
}

/**
 * Organization-scoped AI consent surface (contract `setAiConsent`). Separate
 * from the farm-scoped controller: consent binds the (user, org) pair — a
 * grant must never look farm-bound.
 */
@Controller('v1/organizations/:orgId/ai')
@UseGuards(VerifiedSessionGuard)
export class FarmlyAiConsentController {
  constructor(private readonly ai: FarmlyAiService) {}

  @Put('consent')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async setConsent(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('orgId') organizationIdInput: string,
    @Body() body: unknown,
  ) {
    const organizationId = parseUuid(organizationIdInput, 'Invalid organization ID');
    const parsed = AiConsentDecisionSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException('Invalid consent decision');
    return {
      data: await this.ai.setConsent(principal, organizationId, parsed.data),
    };
  }
}
