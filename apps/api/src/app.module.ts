import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { API_ENVIRONMENT, ApiEnvironment, validateEnvironment } from './config/environment.js';
import { HealthController } from './health/health.controller.js';
import { ReadinessService } from './health/readiness.service.js';
import { AuthModule } from './auth/auth.module.js';
import { VerifiedSessionGuard } from './auth/verified-session.guard.js';
import { MeController } from './identity/me.controller.js';
import { OrganizationsModule } from './organizations/organizations.module.js';
import { MutationKernelModule } from './common/mutations/mutation-kernel.module.js';
import { FarmDomainModule } from './farm-domain/farm-domain.module.js';
import { FarmlyAiModule } from './ai/ai.module.js';
import { FarmlyNotificationsModule } from './notifications/notifications.module.js';
import { FarmlyPrivacyModule } from './privacy/privacy.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
      validate: validateEnvironment,
    }),
    AuthModule,
    OrganizationsModule,
    MutationKernelModule,
    FarmDomainModule,
    FarmlyAiModule,
    FarmlyNotificationsModule,
    FarmlyPrivacyModule,
  ],
  controllers: [HealthController, MeController],
  providers: [
    ReadinessService,
    VerifiedSessionGuard,
    {
      provide: API_ENVIRONMENT,
      inject: [ConfigService],
      useFactory: (config: ConfigService): ApiEnvironment => {
        const environment = config.get<ApiEnvironment>('farmlyEnvironment');
        if (!environment) throw new Error('FARMLY_API_ENVIRONMENT_MISSING');
        return environment;
      },
    },
  ],
  exports: [ReadinessService, API_ENVIRONMENT],
})
export class AppModule {}
