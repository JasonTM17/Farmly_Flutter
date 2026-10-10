import { bearer } from 'better-auth/plugins/bearer';
import type { BetterAuthOptions } from 'better-auth';
import type { ApiEnvironment } from '../config/environment.js';
import { createOneTimeVerificationPlugin, digestVerificationToken, type VerificationTokenStore } from './one-time-verification.js';

export interface AuthEmailSender {
  sendVerificationEmail(message: { readonly email: string; readonly name: string; readonly url: string }): Promise<void>;
  sendPasswordResetEmail(message: { readonly email: string; readonly name: string; readonly url: string }): Promise<void>;
}

type AuthEnvironment = Pick<ApiEnvironment, 'nodeEnv' | 'betterAuthUrl' | 'betterAuthSecret'>;
type AuthDatabase = NonNullable<BetterAuthOptions['database']>;

/** Shared production/test configuration; the caller supplies the pinned database adapter and mail transport. */
export function createFarmlyAuthOptions(
  environment: AuthEnvironment,
  database: AuthDatabase,
  emailSender: AuthEmailSender,
  verificationTokenStore: VerificationTokenStore,
): BetterAuthOptions {
  const authOrigin = new URL(environment.betterAuthUrl).origin;
  const verificationExpiresIn = 60 * 60;

  const options: BetterAuthOptions = {
    appName: 'Farmly',
    baseURL: environment.betterAuthUrl,
    secret: environment.betterAuthSecret,
    database,
    trustedOrigins: [authOrigin, 'farmly://'],
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: true,
      autoSignIn: false,
      revokeSessionsOnPasswordReset: true,
      sendResetPassword: async ({ user, url }) => emailSender.sendPasswordResetEmail({
        email: user.email,
        name: user.name,
        url,
      }),
    },
    emailVerification: {
      sendOnSignUp: true,
      autoSignInAfterVerification: false,
      expiresIn: verificationExpiresIn,
      sendVerificationEmail: async ({ user, url, token }) => {
        await verificationTokenStore.issue(
          digestVerificationToken(token),
          new Date(Date.now() + verificationExpiresIn * 1_000),
        );
        await emailSender.sendVerificationEmail({ email: user.email, name: user.name, url });
      },
    },
    session: {
      expiresIn: 60 * 60 * 24 * 7,
      cookieCache: { enabled: false },
    },
    rateLimit: {
      enabled: true,
      window: 60,
      max: 100,
      storage: 'database',
    },
    advanced: {
      disableCSRFCheck: false,
      disableOriginCheck: false,
      useSecureCookies: environment.nodeEnv === 'production',
    },
    plugins: [bearer(), createOneTimeVerificationPlugin(verificationTokenStore)],
  };

  return options;
}
