import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import nodemailer, { type Transporter } from 'nodemailer';
import type { ApiEnvironment } from '../config/environment.js';
import type { AuthEmailSender } from './auth-options.js';

type SmtpEnvironment = Pick<
  ApiEnvironment,
  'smtpHost' | 'smtpPort' | 'smtpSecure' | 'smtpRequireTls' | 'smtpUser' | 'smtpPassword' | 'smtpFrom'
>;

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character]!);
}

export class SmtpAuthEmailSender implements AuthEmailSender, OnModuleDestroy {
  private readonly transport: Pick<Transporter, 'sendMail' | 'close'>;

  constructor(environment: SmtpEnvironment, transport?: Pick<Transporter, 'sendMail' | 'close'>) {
    this.transport = transport ?? nodemailer.createTransport({
      host: environment.smtpHost,
      port: environment.smtpPort,
      secure: environment.smtpSecure,
      requireTLS: environment.smtpRequireTls,
      ...(environment.smtpUser && environment.smtpPassword
        ? { auth: { user: environment.smtpUser, pass: environment.smtpPassword } }
        : {}),
    });
    this.from = environment.smtpFrom;
  }

  private readonly from: string;

  async sendVerificationEmail(message: { readonly email: string; readonly name: string; readonly url: string }): Promise<void> {
    await this.send(message, 'Verify your Farmly email', 'Verify your email address');
  }

  async sendPasswordResetEmail(message: { readonly email: string; readonly name: string; readonly url: string }): Promise<void> {
    await this.send(message, 'Reset your Farmly password', 'Reset your password');
  }

  async onModuleDestroy(): Promise<void> {
    this.transport.close();
  }

  private async send(
    message: { readonly email: string; readonly name: string; readonly url: string },
    subject: string,
    action: string,
  ): Promise<void> {
    let link: URL;
    try {
      link = new URL(message.url);
    } catch {
      throw new Error('FARMLY_EMAIL_URL_INVALID');
    }
    if (link.protocol !== 'https:' && link.protocol !== 'http:') throw new Error('FARMLY_EMAIL_URL_INVALID');
    const safeName = escapeHtml(message.name);
    const safeUrl = escapeHtml(link.toString());

    try {
      await this.transport.sendMail({
        from: this.from,
        to: message.email,
        subject,
        text: `Hi ${message.name},\n\n${action}: ${link.toString()}\n`,
        html: `<p>Hi ${safeName},</p><p><a href="${safeUrl}">${action}</a></p>`,
      });
    } catch {
      throw new Error('FARMLY_EMAIL_DELIVERY_FAILED');
    }
  }
}

@Injectable()
export class FarmlySmtpEmailSender extends SmtpAuthEmailSender {
  constructor(config: ConfigService) {
    const environment = config.get<ApiEnvironment>('farmlyEnvironment');
    if (!environment) throw new Error('FARMLY_API_ENVIRONMENT_MISSING');
    super(environment);
  }
}
