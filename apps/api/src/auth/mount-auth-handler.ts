import { toNodeHandler } from 'better-auth/node';
import type { FarmlyAuth } from './auth.module.js';

interface ExpressServerAdapter {
  use(path: string, handler: unknown): unknown;
}

interface NestAuthApplication {
  getHttpAdapter(): { getInstance(): ExpressServerAdapter };
}

export function mountFarmlyAuthHandler(app: NestAuthApplication, auth: FarmlyAuth): void {
  app.getHttpAdapter().getInstance().use('/api/auth', toNodeHandler(auth));
}
