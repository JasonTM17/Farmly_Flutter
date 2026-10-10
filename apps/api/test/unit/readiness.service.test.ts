import { describe, expect, it } from 'vitest';
import { ReadinessService } from '../../src/health/readiness.service.js';

describe('readiness checks', () => {
  it('fails closed until both database and migration compatibility are registered', async () => {
    const readiness = new ReadinessService();
    expect(await readiness.isReady()).toBe(false);

    readiness.register('database', () => true);
    expect(await readiness.isReady()).toBe(false);
  });

  it('returns ready only when both probes pass and never exposes probe errors', async () => {
    const readiness = new ReadinessService();
    readiness.register('database', async () => true);
    readiness.register('migrations', () => true);
    expect(await readiness.isReady()).toBe(true);

    readiness.register('database', () => { throw new Error('private connection detail'); });
    expect(await readiness.isReady()).toBe(false);
  });
});
