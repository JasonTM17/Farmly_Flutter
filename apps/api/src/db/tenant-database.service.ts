import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import type { ApiEnvironment } from '../config/environment.js';

@Injectable()
export class TenantDatabaseService implements OnModuleInit, OnModuleDestroy {
  readonly client: PrismaClient;

  constructor(config: ConfigService) {
    const environment = config.get<ApiEnvironment>('farmlyEnvironment');
    if (!environment) throw new Error('FARMLY_API_ENVIRONMENT_MISSING');
    this.client = new PrismaClient({
      adapter: new PrismaPg({ connectionString: environment.databaseUrlTenant }),
    });
  }

  async onModuleInit(): Promise<void> {
    await this.client.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.$disconnect();
  }
}
