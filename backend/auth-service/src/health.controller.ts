import { Controller, Get } from '@nestjs/common';

/** Lightweight liveness probe — returns 200 OK so Docker / start-sentinelvault.sh
 *  health checks pass without needing an external health library. */
@Controller('health')
export class HealthController {
  @Get()
  check(): { status: string } {
    return { status: 'ok' };
  }
}
