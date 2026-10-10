import {
  BadRequestException,
  Controller,
  Get,
  Header,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentPrincipal } from '../auth/current-principal.decorator.js';
import { VerifiedPrincipal, VerifiedSessionGuard } from '../auth/verified-session.guard.js';
import { parseUuid } from '../common/mutations/mutation-kernel.controller.js';
import { FarmlyNotificationsService } from './notifications.service.js';

@Controller('v1/me/notifications')
@UseGuards(VerifiedSessionGuard)
export class FarmlyNotificationsController {
  constructor(private readonly notifications: FarmlyNotificationsService) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  async list(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Query('limit') limitInput?: string,
    @Query('cursor') cursor?: string,
  ) {
    const limit = limitInput === undefined ? 25 : Number.parseInt(limitInput, 10);
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
      throw new BadRequestException({ code: 'VALIDATION_FAILED' });
    }
    return {
      data: await this.notifications.listNotifications(principal, {
        limit,
        cursor,
      }),
    };
  }

  @Post(':notificationId/read')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async markRead(
    @CurrentPrincipal() principal: VerifiedPrincipal,
    @Param('notificationId') notificationIdInput: string,
  ) {
    const notificationId = parseUuid(notificationIdInput, 'Invalid notification ID');
    return {
      data: await this.notifications.markRead(principal, notificationId),
    };
  }
}
