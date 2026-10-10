import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { TenantDatabaseService } from '../db/tenant-database.service.js';
import { OrganizationsController } from './organizations.controller.js';
import { OrganizationsService } from './organizations.service.js';
import { OrganizationInvitationsController } from './organization-invitations.controller.js';
import { OrganizationInvitationsService } from './organization-invitations.service.js';
import { OrganizationMembershipsController } from './organization-memberships.controller.js';
import { OrganizationMembershipsService } from './organization-memberships.service.js';

@Module({
  imports: [AuthModule],
  controllers: [OrganizationsController, OrganizationInvitationsController, OrganizationMembershipsController],
  providers: [VerifiedSessionGuard, TenantDatabaseService, OrganizationsService, OrganizationInvitationsService, OrganizationMembershipsService],
})
export class OrganizationsModule {}
