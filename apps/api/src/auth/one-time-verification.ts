import { createHash } from 'node:crypto';
import { APIError, createAuthMiddleware } from 'better-auth/api';
import type { BetterAuthPlugin } from 'better-auth';

/** Implementations must consume atomically: only one concurrent caller may succeed. */
export interface VerificationTokenStore {
  issue(tokenDigest: string, expiresAt: Date): Promise<void>;
  consume(tokenDigest: string, now: Date): Promise<boolean>;
}

export function digestVerificationToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

/** Adds Farmly's single-use boundary around Better Auth's signed verification route. */
export function createOneTimeVerificationPlugin(store: VerificationTokenStore): BetterAuthPlugin {
  return {
    id: 'farmly-one-time-email-verification',
    hooks: {
      before: [{
        matcher: ({ path }) => path === '/verify-email',
        handler: createAuthMiddleware(async (context) => {
          if (!context.request) {
            throw APIError.fromStatus('UNAUTHORIZED', { message: 'Invalid or expired verification token' });
          }

          const requestUrl = new URL(context.request.url);
          const requestOrigin = context.request.headers.get('origin');
          if (requestOrigin) {
            let canonicalOrigin: string | null = null;
            try {
              const parsedOrigin = new URL(requestOrigin);
              if (parsedOrigin.origin === requestOrigin) canonicalOrigin = parsedOrigin.origin;
            } catch {
              // An invalid Origin is rejected below without logging its value.
            }
            if (!canonicalOrigin || !context.context.isTrustedOrigin(canonicalOrigin, { allowRelativePaths: false })) {
              throw APIError.fromStatus('FORBIDDEN', { message: 'Invalid verification request' });
            }
          }

          const callbackUrl = requestUrl.searchParams.get('callbackURL');
          if (callbackUrl && !context.context.isTrustedOrigin(callbackUrl, { allowRelativePaths: true })) {
            throw APIError.fromStatus('FORBIDDEN', { message: 'Invalid verification request' });
          }

          const token = requestUrl.searchParams.get('token');
          if (!token || !await store.consume(digestVerificationToken(token), new Date())) {
            throw APIError.fromStatus('UNAUTHORIZED', { message: 'Invalid or expired verification token' });
          }
        }),
      }],
    },
  };
}
