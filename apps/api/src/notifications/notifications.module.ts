import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import { FarmlyNotificationsController } from './notifications.controller.js';
import { FarmlyNotificationsService } from './notifications.service.js';

@Module({
  imports: [AuthModule],
  controllers: [FarmlyNotificationsController],
  providers: [VerifiedSessionGuard, TenantDatabaseService, FarmlyNotificationsService],
})
export class FarmlyNotificationsModule {}
