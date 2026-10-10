import { Module } from '@nestjs/common';
import { AuthModule } from '../../auth/auth.module.js';
import { VerifiedSessionGuard } from '../../auth/verified-session.guard.js';
import { TenantDatabaseService } from '../../db/tenant-database.service.js';
import { MutationKernelController } from './mutation-kernel.controller.js';
import { MutationKernelService } from './mutation-kernel.service.js';

@Module({
  imports: [AuthModule],
  controllers: [MutationKernelController],
  providers: [VerifiedSessionGuard, TenantDatabaseService, MutationKernelService],
  exports: [MutationKernelService],
})
export class MutationKernelModule {}
