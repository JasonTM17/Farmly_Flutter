import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../../generated/auth-client/index.js';
import type { ApiEnvironment } from '../config/environment.js';
import type { VerificationTokenStore } from './one-time-verification.js';

@Injectable()
export class PrismaVerificationTokenStore implements VerificationTokenStore {
  constructor(private readonly prisma: PrismaClient) {}

  async issue(tokenDigest: string, expiresAt: Date): Promise<void> {
    this.assertDigest(tokenDigest);
    const now = new Date();
    await this.prisma.verificationTokenDigest.deleteMany({ where: { expiresAt: { lte: now } } });
    await this.prisma.verificationTokenDigest.upsert({
      where: { digest: tokenDigest },
      create: { digest: tokenDigest, expiresAt },
      update: { expiresAt },
    });
  }

  async consume(tokenDigest: string, now: Date): Promise<boolean> {
    this.assertDigest(tokenDigest);
    const result = await this.prisma.verificationTokenDigest.deleteMany({
      where: { digest: tokenDigest, expiresAt: { gt: now } },
    });
    return result.count === 1;
  }

  private assertDigest(tokenDigest: string): void {
    if (!/^[a-f0-9]{64}$/.test(tokenDigest)) {
      throw new Error('FARMLY_VERIFICATION_DIGEST_INVALID');
    }
  }
}

@Injectable()
export class AuthDatabaseService implements OnModuleInit, OnModuleDestroy {
  readonly client: PrismaClient;
  readonly verificationTokens: PrismaVerificationTokenStore;

  constructor(config: ConfigService) {
    const environment = config.get<ApiEnvironment>('farmlyEnvironment');
    if (!environment) throw new Error('FARMLY_API_ENVIRONMENT_MISSING');
    this.client = new PrismaClient({
      adapter: new PrismaPg({ connectionString: environment.databaseUrlAuth }),
    });
    this.verificationTokens = new PrismaVerificationTokenStore(this.client);
  }

  async onModuleInit(): Promise<void> {
    await this.client.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.$disconnect();
  }
}
