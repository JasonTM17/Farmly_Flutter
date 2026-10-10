import { createParamDecorator, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import type { AuthenticatedRequest, VerifiedPrincipal } from './verified-session.guard.js';

export const CurrentPrincipal = createParamDecorator(
  (_data: unknown, context: ExecutionContext): VerifiedPrincipal => {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    if (!request.farmlyPrincipal) throw new UnauthorizedException('Authentication required');
    return request.farmlyPrincipal;
  },
);
