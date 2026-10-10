import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { ApiEnvironment } from '../config/environment.js';

// The single approved model alias (spec05 §1 — no third-party gateway names,
// no Pro fallback, no client-supplied model).
export const AI_MODEL_ALIAS = 'deepseek-flash';
export const AI_EVENT_SCHEMA = 'farmly-ai-events.v1';
export const AI_SNAPSHOT_SCHEMA = 'farmly-ai-snapshot.v1';

export interface AiProviderMessage {
  readonly role: 'system' | 'user' | 'assistant';
  readonly content: string;
}

export interface AiProviderRequest {
  readonly messages: readonly AiProviderMessage[];
  readonly maxTokens: number;
  readonly signal: AbortSignal;
}

export type AiProviderChunk =
  | { readonly type: 'delta'; readonly text: string }
  | { readonly type: 'finish'; readonly reason: 'stop' | 'length' }
  | {
      readonly type: 'usage';
      readonly inputTokens: number;
      readonly outputTokens: number;
      readonly totalTokens: number;
    }
  | { readonly type: 'error'; readonly code: string; readonly retryable: boolean };

// The dispatcher only ever sees this seam — tests bind a simulated provider,
// production binds DeepSeekAdapter. No SDK hidden retries: one fenced attempt
// means at most one upstream HTTP request (spec05 §4).
export interface AiProvider {
  readonly name: string;
  stream(request: AiProviderRequest): AsyncIterable<AiProviderChunk>;
}

export const AI_PROVIDER = 'FARMLY_AI_PROVIDER';

// Returned when AI is configured off (or the key is absent) but a request
// somehow reaches the dispatcher — fail closed, never a silent fake answer.
export class UnavailableAiProvider implements AiProvider {
  readonly name = 'unavailable';
  async *stream(): AsyncIterable<AiProviderChunk> {
    yield { type: 'error', code: 'AI_UNAVAILABLE', retryable: true };
  }
}

// Deterministic simulated provider for the test seam: no network, stable
// chunks, optional injected faults controlled by the caller's prompt prefix.
export class SimulatedAiProvider implements AiProvider {
  readonly name = 'simulated';

  constructor(
    private readonly options: {
      readonly delayMs?: number;
      readonly emitUsage?: boolean;
      readonly finishReason?: 'stop' | 'length';
    } = {},
  ) {}

  async *stream(request: AiProviderRequest): AsyncIterable<AiProviderChunk> {
    const userMessages = request.messages.filter((message) => message.role === 'user');
    const userText = userMessages[userMessages.length - 1]?.content ?? '';
    const reply = `Simulated answer for: ${userText.slice(0, 80)}`;
    const words = reply.split(' ');
    let index = 0;
    for (const word of words) {
      if (request.signal.aborted) return;
      if (this.options.delayMs) await new Promise((done) => setTimeout(done, this.options.delayMs));
      index += 1;
      yield { type: 'delta', text: index === 1 ? word : ` ${word}` };
    }
    if (this.options.emitUsage !== false) {
      const input = Math.max(1, Math.ceil(request.messages.map((m) => m.content.length).reduce((a, b) => a + b, 0) / 4));
      yield { type: 'usage', inputTokens: input, outputTokens: reply.length / 4 | 0 || 1, totalTokens: input + 8 };
    }
    yield { type: 'finish', reason: this.options.finishReason ?? 'stop' };
  }
}

// Official DeepSeek Chat Completions adapter (spec05 §1): fixed model alias,
// thinking disabled, stream=true with include_usage. The API key never leaves
// the server and is never placed in logs or event payloads.
@Injectable()
export class DeepSeekAdapter implements AiProvider {
  readonly name = 'deepseek';
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly model: string;

  constructor(config: ConfigService) {
    const environment = config.get<ApiEnvironment>('farmlyEnvironment');
    this.apiKey = environment?.deepSeekApiKey ?? '';
    this.baseUrl = (environment?.deepSeekBaseUrl ?? 'https://api.deepseek.com').replace(/\/+$/, '');
    this.model = environment?.deepSeekModel ?? AI_MODEL_ALIAS;
    if (this.model !== AI_MODEL_ALIAS) throw new Error('DEEPSEEK_MODEL_MISMATCH');
  }

  async *stream(request: AiProviderRequest): AsyncIterable<AiProviderChunk> {
    if (!this.apiKey) {
      yield { type: 'error', code: 'AI_UNAVAILABLE', retryable: true };
      return;
    }
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${this.apiKey}`,
          'content-type': 'application/json',
          accept: 'text/event-stream',
        },
        body: JSON.stringify({
          model: this.model,
          messages: request.messages,
          max_tokens: request.maxTokens,
          stream: true,
          stream_options: { include_usage: true },
          thinking: { type: 'disabled' },
        }),
        signal: request.signal,
      });
    } catch (error) {
      if (request.signal.aborted) return;
      yield { type: 'error', code: 'AI_UPSTREAM_UNREACHABLE', retryable: true };
      return;
    }
    if (!response.ok || !response.body) {
      yield {
        type: 'error',
        code: 'AI_UPSTREAM_ERROR',
        retryable: response.status >= 500 || response.status === 429,
      };
      return;
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) return;
        buffer += decoder.decode(value, { stream: true });
        let boundary: number;
        while ((boundary = buffer.indexOf('\n\n')) >= 0) {
          const frame = buffer.slice(0, boundary);
          buffer = buffer.slice(boundary + 2);
          const data = frame
            .split('\n')
            .filter((line) => line.startsWith('data:'))
            .map((line) => line.slice(5).trimStart())
            .join('\n');
          if (!data) continue;
          if (data === '[DONE]') return;
          const chunk = safeParse(data);
          if (!chunk) continue;
          const parsed = mapChunk(chunk);
          if (parsed) yield parsed;
        }
      }
    } catch {
      // Aborted mid-read or upstream EOF: the dispatcher decides interrupted
      // vs cancelled — a partial stream never claims completion.
      return;
    } finally {
      reader.releaseLock();
    }
  }
}

function safeParse(data: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(data) as unknown;
    return value && typeof value === 'object' ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function mapChunk(chunk: Record<string, unknown>): AiProviderChunk | null {
  const usage = chunk['usage'] as Record<string, unknown> | null | undefined;
  if (usage && typeof usage['prompt_tokens'] === 'number') {
    const input = Math.max(0, Math.trunc(usage['prompt_tokens'] as number));
    const output = Math.max(0, Math.trunc((usage['completion_tokens'] as number) ?? 0));
    const total = Math.max(0, Math.trunc((usage['total_tokens'] as number) ?? input + output));
    return { type: 'usage', inputTokens: input, outputTokens: output, totalTokens: total };
  }
  const choices = chunk['choices'] as readonly Record<string, unknown>[] | undefined;
  const first = choices?.[0];
  if (!first) return null;
  const finishReason = first['finish_reason'];
  if (finishReason === 'stop' || finishReason === 'length') {
    return { type: 'finish', reason: finishReason };
  }
  const delta = first['delta'] as Record<string, unknown> | undefined;
  // Never surface or persist reasoning_content (spec05 §1).
  const content = delta?.['content'];
  if (typeof content === 'string' && content.length > 0) {
    return { type: 'delta', text: content };
  }
  return null;
}
