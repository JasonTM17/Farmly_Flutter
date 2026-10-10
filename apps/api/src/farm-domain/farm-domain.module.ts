import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { MutationKernelModule } from '../common/mutations/mutation-kernel.module.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import { FarmDomainController } from './farm-domain.controller.js';
import { FarmDomainService } from './farm-domain.service.js';

@Module({
  imports: [AuthModule, MutationKernelModule],
  controllers: [FarmDomainController],
  providers: [VerifiedSessionGuard, TenantDatabaseService, FarmDomainService],
})
export class FarmDomainModule {}
