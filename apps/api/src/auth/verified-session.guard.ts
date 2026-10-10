import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Inject,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { FARMLY_AUTH } from './auth.module.js';
import type { FarmlyAuth } from './auth.module.js';

export interface VerifiedPrincipal {
  readonly actorId: string;
  readonly email: string;
  readonly displayName: string;
  readonly sessionId: string;
  readonly sessionExpiresAt: Date;
}

export interface AuthenticatedRequest {
  readonly headers: Readonly<Record<string, string | string[] | undefined>>;
  farmlyPrincipal?: VerifiedPrincipal;
}

@Injectable()
export class VerifiedSessionGuard implements CanActivate {
  constructor(@Inject(FARMLY_AUTH) private readonly auth: FarmlyAuth) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authorization = request.headers.authorization;
    if (typeof authorization !== 'string' || !/^Bearer\s+\S+$/i.test(authorization)) {
      throw new UnauthorizedException('Authentication required');
    }

    let current: Awaited<ReturnType<FarmlyAuth['api']['getSession']>>;
    try {
      current = await this.auth.api.getSession({ headers: new Headers({ authorization }) });
    } catch {
      throw new ServiceUnavailableException('Authentication service unavailable');
    }

    if (!current) throw new UnauthorizedException('Authentication required');
    if (!current.user.emailVerified) throw new ForbiddenException('Verified email required');

    request.farmlyPrincipal = Object.freeze({
      actorId: current.user.id,
      email: current.user.email,
      displayName: current.user.name,
      sessionId: current.session.id,
      sessionExpiresAt: current.session.expiresAt,
    });
    return true;
  }
}
