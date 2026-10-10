import {
  BadRequestException,
  Body,
  Controller,
  Header,
  HttpCode,
  Post,
  UseGuards,
} from '@nestjs/common';
import { z } from 'zod';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { UUID_PATTERN } from '../common/mutations/mutation-kernel.controller.js';
import { FarmlyPrivacyService } from './privacy.service.js';

const DeviceRegistrationSchema = z.object({
  operationId: z.string().regex(UUID_PATTERN),
  action: z.enum(['register', 'revoke']),
  deviceId: z.string().min(1).max(200),
  pushToken: z.string().max(4096).optional(),
}).strict();

const PrivacyRequestSchema = z.object({
  operationId: z.string().regex(UUID_PATTERN),
  action: z.enum(['export', 'delete-history', 'withdraw-ai-consent']),
  confirmation: z.string().max(120).optional(),
}).strict();

@Controller('v1/me')
@UseGuards(VerifiedSessionGuard)
export class FarmlyPrivacyController {
  constructor(private readonly privacy: FarmlyPrivacyService) {}

  @Post('device-registrations')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async mutateDeviceRegistration(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Body() body: unknown,
  ) {
    const parsed = DeviceRegistrationSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException({ code: 'VALIDATION_FAILED' });
    if (parsed.data.action === 'register' && !parsed.data.pushToken) {
      // A register without a token is meaningless — revoke is the tokenless path.
      throw new BadRequestException({ code: 'VALIDATION_FAILED' });
    }
    return { data: await this.privacy.mutateDeviceRegistration(principal, parsed.data) };
  }

  @Post('privacy-requests')
  @HttpCode(202)
  @Header('Cache-Control', 'private, no-store')
  async createPrivacyRequest(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Body() body: unknown,
  ) {
    const parsed = PrivacyRequestSchema.safeParse(body);
    if (!parsed.success) throw new BadRequestException({ code: 'VALIDATION_FAILED' });
    return { data: await this.privacy.createPrivacyRequest(principal, parsed.data) };
  }
}
