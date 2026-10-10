import { describe, expect, it } from 'vitest';
import { parseEnvironment } from '../../src/config/environment.js';

const validEnvironment = {
  NODE_ENV: 'test',
  PORT: '3400',
  DATABASE_URL_TENANT: 'postgresql://farmly:placeholder@127.0.0.1:5432/farmly_tenant',
  DATABASE_URL_AUTH: 'postgresql://farmly:placeholder@127.0.0.1:5432/farmly_auth',
  BETTER_AUTH_SECRET: 'unit-test-secret-that-is-long-enough-32',
  BETTER_AUTH_URL: 'http://localhost:3000',
  CURSOR_SIGNING_KEY: 'unit-test-cursor-key-that-is-long-enough-32',
};

describe('API environment validation', () => {
  it('parses required server settings and ignores unrelated operating-system variables', () => {
    const parsed = parseEnvironment({ ...validEnvironment, PATH: 'must not be parsed as app config' });

    expect(parsed.port).toBe(3400);
    expect(parsed.aiEnabled).toBe(false);
    expect(parsed.aiMaxOutputTokens).toBe(1200);
    expect(Object.isFrozen(parsed)).toBe(true);
  });

  it('reports invalid variable names without echoing their values', () => {
    expect(() => parseEnvironment({ ...validEnvironment, BETTER_AUTH_SECRET: 'short-sensitive-value' }))
      .toThrow(/BETTER_AUTH_SECRET/);
    try {
      parseEnvironment({ ...validEnvironment, BETTER_AUTH_SECRET: 'short-sensitive-value' });
    } catch (error) {
      expect(String(error)).not.toContain('short-sensitive-value');
    }
  });

  it('rejects the migration-only credential at the API runtime boundary without echoing it', () => {
    const migrationUrl = 'postgresql://migration:private-test-value@127.0.0.1:5432/farmly_test_261005';

    expect(() => parseEnvironment({ ...validEnvironment, MIGRATION_DATABASE_URL: migrationUrl }))
      .toThrow(/MIGRATION_DATABASE_URL/);
    try {
      parseEnvironment({ ...validEnvironment, MIGRATION_DATABASE_URL: migrationUrl });
    } catch (error) {
      expect(String(error)).not.toContain(migrationUrl);
      expect(String(error)).not.toContain('private-test-value');
    }
  });

  it('fails closed when AI is enabled without a key and approved hard limits', () => {
    expect(() => parseEnvironment({ ...validEnvironment, AI_ENABLED: 'true' }))
      .toThrow(/DEEPSEEK_API_KEY/);
  });

  it('requires the approved provider alias and complete caps before enabling AI', () => {
    expect(() => parseEnvironment({
      ...validEnvironment,
      AI_ENABLED: 'true',
      DEEPSEEK_API_KEY: 'local-test-key-not-a-real-secret',
      DEEPSEEK_BASE_URL: 'https://api.deepseek.com',
      DEEPSEEK_MODEL: 'unapproved-fallback',
      AI_PROJECT_COST_CAP: '1.00',
      AI_ORG_TOKEN_CAP: '5000',
      AI_USER_RATE_LIMIT: '5',
    })).toThrow(/DEEPSEEK_MODEL/);
  });

  it('rejects incomplete SMTP credentials and plaintext production SMTP', () => {
    expect(() => parseEnvironment({ ...validEnvironment, SMTP_USER: 'relay-user' }))
      .toThrow(/SMTP_USER/);
    expect(() => parseEnvironment({
      ...validEnvironment,
      NODE_ENV: 'production',
      BETTER_AUTH_URL: 'https://api.farmly.example',
    })).toThrow(/SMTP_REQUIRE_TLS/);
  });
});
