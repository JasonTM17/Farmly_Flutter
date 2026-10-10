import { z } from 'zod';

const postgresUrl = z.string().url().refine((value) => {
  const protocol = new URL(value).protocol;
  return protocol === 'postgres:' || protocol === 'postgresql:';
}, 'must be a PostgreSQL URL');

const positiveInteger = z.coerce.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const smtpPort = z.coerce.number().int().min(1).max(65535);
const decimalCap = z.string().regex(/^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?$/).refine((value) => /[1-9]/.test(value));

const EnvironmentSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL_TENANT: postgresUrl,
  DATABASE_URL_AUTH: postgresUrl,
  BETTER_AUTH_SECRET: z.string().min(32),
  BETTER_AUTH_URL: z.string().url(),
  SMTP_HOST: z.string().min(1).default('127.0.0.1'),
  SMTP_PORT: smtpPort.default(11025),
  SMTP_SECURE: z.enum(['true', 'false']).default('false').transform((value) => value === 'true'),
  SMTP_REQUIRE_TLS: z.enum(['true', 'false']).default('false').transform((value) => value === 'true'),
  SMTP_USER: z.string().min(1).optional(),
  SMTP_PASSWORD: z.string().min(1).optional(),
  SMTP_FROM: z.string().min(3).refine((value) => !/[\r\n]/.test(value), 'must not contain line breaks').default('Farmly <no-reply@farmly.test>'),
  CURSOR_SIGNING_KEY: z.string().min(32),
  AI_ENABLED: z.enum(['true', 'false']).default('false').transform((value) => value === 'true'),
  DEEPSEEK_API_KEY: z.string().min(1).optional(),
  DEEPSEEK_BASE_URL: z.string().url().optional(),
  DEEPSEEK_MODEL: z.string().min(1).optional(),
  AI_PROJECT_COST_CAP: decimalCap.optional(),
  AI_ORG_TOKEN_CAP: positiveInteger.optional(),
  AI_USER_RATE_LIMIT: positiveInteger.optional(),
  AI_MAX_OUTPUT_TOKENS: z.coerce.number().int().min(1).max(8192).default(1200),
  // Upper bound on the fully-serialized server prompt (context + history +
  // user text + framing), not the raw user string — spec05 §6.
  AI_MAX_INPUT_BYTES: z.coerce.number().int().min(1024).max(1048576).default(65536),
  // Identifies the operator-approved price snapshot row used for cost
  // upper-bound reservation; required when AI_ENABLED so cost bounds never
  // come from an unstamped default.
  AI_PRICE_SNAPSHOT_ID: z.string().min(1).optional(),
  AI_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(1000).max(300000).default(60000),
  WEATHER_ENABLED: z.enum(['true', 'false']).default('false').transform((value) => value === 'true'),
  WEATHER_FRESH_TTL_SECONDS: z.coerce.number().int().min(60).max(86400).default(3600),
}).strict().superRefine((value, context) => {
  if (value.NODE_ENV === 'production' && new URL(value.BETTER_AUTH_URL).protocol !== 'https:') {
    context.addIssue({ code: 'custom', path: ['BETTER_AUTH_URL'], message: 'must use HTTPS in production' });
  }
  if ((value.SMTP_USER === undefined) !== (value.SMTP_PASSWORD === undefined)) {
    context.addIssue({ code: 'custom', path: ['SMTP_USER'], message: 'SMTP_USER and SMTP_PASSWORD must be configured together' });
  }
  if (value.NODE_ENV === 'production' && !value.SMTP_SECURE && !value.SMTP_REQUIRE_TLS) {
    context.addIssue({ code: 'custom', path: ['SMTP_REQUIRE_TLS'], message: 'production SMTP must require TLS' });
  }
  if (!value.AI_ENABLED) return;

  for (const key of ['DEEPSEEK_API_KEY', 'DEEPSEEK_BASE_URL', 'DEEPSEEK_MODEL', 'AI_PROJECT_COST_CAP', 'AI_ORG_TOKEN_CAP', 'AI_USER_RATE_LIMIT', 'AI_PRICE_SNAPSHOT_ID'] as const) {
    if (value[key] === undefined) context.addIssue({ code: 'custom', path: [key], message: 'required when AI_ENABLED=true' });
  }
  if (value.DEEPSEEK_MODEL !== undefined && value.DEEPSEEK_MODEL !== 'deepseek-flash') {
    context.addIssue({ code: 'custom', path: ['DEEPSEEK_MODEL'], message: 'must match the approved model alias' });
  }
  if (value.DEEPSEEK_BASE_URL !== undefined) {
    const providerUrl = new URL(value.DEEPSEEK_BASE_URL);
    if (value.NODE_ENV === 'production' && providerUrl.protocol !== 'https:') {
      context.addIssue({ code: 'custom', path: ['DEEPSEEK_BASE_URL'], message: 'must use HTTPS in production' });
    }
  }
});

const CONFIG_KEYS = [
  'NODE_ENV', 'PORT', 'DATABASE_URL_TENANT', 'DATABASE_URL_AUTH',
  'BETTER_AUTH_SECRET', 'BETTER_AUTH_URL', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_SECURE',
  'SMTP_REQUIRE_TLS', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'CURSOR_SIGNING_KEY', 'AI_ENABLED',
  'DEEPSEEK_API_KEY', 'DEEPSEEK_BASE_URL', 'DEEPSEEK_MODEL', 'AI_PROJECT_COST_CAP',
  'AI_ORG_TOKEN_CAP', 'AI_USER_RATE_LIMIT', 'AI_MAX_OUTPUT_TOKENS',
  'AI_MAX_INPUT_BYTES', 'AI_PRICE_SNAPSHOT_ID', 'AI_REQUEST_TIMEOUT_MS',
  'WEATHER_ENABLED', 'WEATHER_FRESH_TTL_SECONDS',
] as const;

export interface ApiEnvironment {
  readonly nodeEnv: 'development' | 'test' | 'production';
  readonly port: number;
  readonly databaseUrlTenant: string;
  readonly databaseUrlAuth: string;
  readonly betterAuthSecret: string;
  readonly betterAuthUrl: string;
  readonly smtpHost: string;
  readonly smtpPort: number;
  readonly smtpSecure: boolean;
  readonly smtpRequireTls: boolean;
  readonly smtpUser?: string;
  readonly smtpPassword?: string;
  readonly smtpFrom: string;
  readonly cursorSigningKey: string;
  readonly aiEnabled: boolean;
  readonly deepSeekApiKey?: string;
  readonly deepSeekBaseUrl?: string;
  readonly deepSeekModel?: string;
  readonly aiProjectCostCap?: string;
  readonly aiOrgTokenCap?: number;
  readonly aiUserRateLimit?: number;
  readonly aiMaxOutputTokens: number;
  readonly aiMaxInputBytes: number;
  readonly aiPriceSnapshotId?: string;
  readonly aiRequestTimeoutMs: number;
  readonly weatherEnabled: boolean;
  readonly weatherFreshTtlSeconds: number;
}

export const API_ENVIRONMENT = 'FARMLY_API_ENVIRONMENT';

export function parseEnvironment(source: Record<string, unknown>): ApiEnvironment {
  if (source.MIGRATION_DATABASE_URL !== undefined) {
    throw new Error('Invalid Farmly API environment variables: MIGRATION_DATABASE_URL');
  }
  const selected = Object.fromEntries(CONFIG_KEYS
    .filter((key) => source[key] !== undefined)
    .map((key) => [key, source[key]]));
  const result = EnvironmentSchema.safeParse(selected);
  if (!result.success) {
    const invalidKeys = [...new Set(result.error.issues.map((issue) => issue.path.join('.')).filter(Boolean))];
    throw new Error(`Invalid Farmly API environment variables: ${invalidKeys.join(', ') || 'configuration'}`);
  }
  const value = result.data;
  return Object.freeze({
    nodeEnv: value.NODE_ENV,
    port: value.PORT,
    databaseUrlTenant: value.DATABASE_URL_TENANT,
    databaseUrlAuth: value.DATABASE_URL_AUTH,
    betterAuthSecret: value.BETTER_AUTH_SECRET,
    betterAuthUrl: value.BETTER_AUTH_URL,
    smtpHost: value.SMTP_HOST,
    smtpPort: value.SMTP_PORT,
    smtpSecure: value.SMTP_SECURE,
    smtpRequireTls: value.SMTP_REQUIRE_TLS,
    smtpUser: value.SMTP_USER,
    smtpPassword: value.SMTP_PASSWORD,
    smtpFrom: value.SMTP_FROM,
    cursorSigningKey: value.CURSOR_SIGNING_KEY,
    aiEnabled: value.AI_ENABLED,
    deepSeekApiKey: value.DEEPSEEK_API_KEY,
    deepSeekBaseUrl: value.DEEPSEEK_BASE_URL,
    deepSeekModel: value.DEEPSEEK_MODEL,
    aiProjectCostCap: value.AI_PROJECT_COST_CAP,
    aiOrgTokenCap: value.AI_ORG_TOKEN_CAP,
    aiUserRateLimit: value.AI_USER_RATE_LIMIT,
    aiMaxOutputTokens: value.AI_MAX_OUTPUT_TOKENS,
    aiMaxInputBytes: value.AI_MAX_INPUT_BYTES,
    aiPriceSnapshotId: value.AI_PRICE_SNAPSHOT_ID,
    aiRequestTimeoutMs: value.AI_REQUEST_TIMEOUT_MS,
    weatherEnabled: value.WEATHER_ENABLED,
    weatherFreshTtlSeconds: value.WEATHER_FRESH_TTL_SECONDS,
  });
}

export function validateEnvironment(source: Record<string, unknown>): Record<string, unknown> {
  return { ...source, farmlyEnvironment: parseEnvironment(source) };
}
