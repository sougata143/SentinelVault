import { Controller, Get } from '@nestjs/common';

/** Lightweight liveness probe — returns 200 OK so start-sentinelvault.sh health checks pass. */
@Controller('health')
export class HealthController {
  @Get()
  check(): { status: string } {
    return { status: 'ok' };
  }
}
