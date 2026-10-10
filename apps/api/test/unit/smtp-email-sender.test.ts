import { describe, expect, it, vi } from 'vitest';
import type { ApiEnvironment } from '../../src/config/environment.js';
import { SmtpAuthEmailSender } from '../../src/auth/smtp-email-sender.js';

const smtpEnvironment: Pick<
  ApiEnvironment,
  'smtpHost' | 'smtpPort' | 'smtpSecure' | 'smtpRequireTls' | 'smtpUser' | 'smtpPassword' | 'smtpFrom'
> = {
  smtpHost: '127.0.0.1',
  smtpPort: 11025,
  smtpSecure: false,
  smtpRequireTls: false,
  smtpFrom: 'Farmly <no-reply@farmly.test>',
};

describe('SMTP auth email sender', () => {
  it('sends a text and escaped HTML link without changing the recipient or action', async () => {
    const sendMail = vi.fn(async () => undefined);
    const close = vi.fn();
    const sender = new SmtpAuthEmailSender(smtpEnvironment, { sendMail, close });

    await sender.sendVerificationEmail({
      email: 'owner@farmly.test',
      name: '<script>alert(1)</script>',
      url: 'https://auth.farmly.test/api/auth/verify-email?token=opaque&callbackURL=%2F',
    });

    expect(sendMail).toHaveBeenCalledOnce();
    const message = sendMail.mock.calls[0]![0];
    expect(message).toMatchObject({
      from: 'Farmly <no-reply@farmly.test>',
      to: 'owner@farmly.test',
      subject: 'Verify your Farmly email',
    });
    expect(message.html).toContain('&lt;script&gt;');
    expect(message.html).toContain('token=opaque&amp;callbackURL');
    expect(message.text).toContain('https://auth.farmly.test/api/auth/verify-email?token=opaque&callbackURL=%2F');
    await sender.onModuleDestroy();
    expect(close).toHaveBeenCalledOnce();
  });

  it('returns a redacted delivery error instead of SMTP or URL details', async () => {
    const sender = new SmtpAuthEmailSender(smtpEnvironment, {
      sendMail: async () => { throw new Error('private SMTP response containing token'); },
      close: () => undefined,
    });

    await expect(sender.sendPasswordResetEmail({
      email: 'owner@farmly.test',
      name: 'Farmly Owner',
      url: 'https://auth.farmly.test/reset?token=private-token',
    })).rejects.toThrow('FARMLY_EMAIL_DELIVERY_FAILED');
    await expect(sender.sendVerificationEmail({
      email: 'owner@farmly.test',
      name: 'Farmly Owner',
      url: 'invalid-private-token-url',
    })).rejects.toThrow('FARMLY_EMAIL_URL_INVALID');
  });
});
