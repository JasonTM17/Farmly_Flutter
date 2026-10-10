import { Controller, Get, Res } from '@nestjs/common';
import { ReadinessService } from './readiness.service.js';

interface StatusResponse {
  status(code: number): StatusResponse;
}

@Controller('health')
export class HealthController {
  constructor(private readonly readiness: ReadinessService) {}

  @Get('live')
  live(): { status: 'live' } {
    return { status: 'live' };
  }

  @Get('ready')
  async ready(@Res({ passthrough: true }) response: StatusResponse): Promise<{ status: 'ready' | 'not_ready' }> {
    const isReady = await this.readiness.isReady();
    response.status(isReady ? 200 : 503);
    return { status: isReady ? 'ready' : 'not_ready' };
  }
}
