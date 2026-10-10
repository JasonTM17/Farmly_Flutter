import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { betterAuth } from 'better-auth';
import { prismaAdapter } from 'better-auth/adapters/prisma';
import type { ApiEnvironment } from '../config/environment.js';
import { createFarmlyAuthOptions } from './auth-options.js';
import { AuthDatabaseService } from './auth-database.service.js';
import { FarmlySmtpEmailSender } from './smtp-email-sender.js';

export const FARMLY_AUTH = Symbol('FARMLY_AUTH');
export type FarmlyAuth = ReturnType<typeof betterAuth>;

@Module({
  imports: [ConfigModule],
  providers: [
    AuthDatabaseService,
    FarmlySmtpEmailSender,
    {
      provide: FARMLY_AUTH,
      inject: [ConfigService, AuthDatabaseService, FarmlySmtpEmailSender],
      useFactory: (
        config: ConfigService,
        database: AuthDatabaseService,
        emailSender: FarmlySmtpEmailSender,
      ): FarmlyAuth => {
        const environment = config.get<ApiEnvironment>('farmlyEnvironment');
        if (!environment) throw new Error('FARMLY_API_ENVIRONMENT_MISSING');
        const adapter = prismaAdapter(database.client, { provider: 'postgresql', transaction: true });
        return betterAuth(createFarmlyAuthOptions(environment, adapter, emailSender, database.verificationTokens));
      },
    },
  ],
  exports: [FARMLY_AUTH],
})
export class AuthModule {}
