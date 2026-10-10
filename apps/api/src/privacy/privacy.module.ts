import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import { FarmlyPrivacyController } from './privacy.controller.js';
import { FarmlyPrivacyService } from './privacy.service.js';

@Module({
  imports: [AuthModule],
  controllers: [FarmlyPrivacyController],
  providers: [VerifiedSessionGuard, TenantDatabaseService, FarmlyPrivacyService],
})
export class FarmlyPrivacyModule {}
