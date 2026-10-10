import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import { FarmlyAiConsentController, FarmlyAiController } from './ai.controller.js';
import { AiDispatcherService } from './ai-dispatcher.service.js';
import { AI_PROVIDER, DeepSeekAdapter, UnavailableAiProvider } from './ai-provider.js';
import { FarmlyAiService } from './ai.service.js';
import type { ApiEnvironment } from '../config/environment.js';
import { ConfigService } from '@nestjs/config';

@Module({
  imports: [AuthModule],
  controllers: [FarmlyAiConsentController, FarmlyAiController],
  providers: [
    VerifiedSessionGuard,
    TenantDatabaseService,
    FarmlyAiService,
    AiDispatcherService,
    {
      provide: AI_PROVIDER,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const environment = config.get<ApiEnvironment>('farmlyEnvironment');
        return environment?.aiEnabled ? new DeepSeekAdapter(config) : new UnavailableAiProvider();
      },
    },
  ],
})
export class FarmlyAiModule {}
