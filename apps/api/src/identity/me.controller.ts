import { Controller, Get, Header, UseGuards } from '@nestjs/common';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';

@Controller('v1/me')
@UseGuards(VerifiedSessionGuard)
export class MeController {
  @Get()
  @Header('Cache-Control', 'private, no-store')
  @Header('Pragma', 'no-cache')
  getCurrentPrincipal(@CurrentPrincipal() principal: VerifiedPrincipal) {
    return {
      data: {
        userId: principal.actorId,
        name: principal.displayName,
        email: principal.email,
        emailVerified: true,
        sessionExpiresAt: principal.sessionExpiresAt.toISOString(),
      },
      meta: { schemaVersion: 'farmly.v1', asOf: new Date().toISOString() },
    };
  }
}
