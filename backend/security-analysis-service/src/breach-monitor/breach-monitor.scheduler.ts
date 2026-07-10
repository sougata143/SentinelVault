import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { BreachMonitorService } from './breach-monitor.service';

/**
 * Background scheduler that runs a daily breach check for all opted-in users.
 *
 * Only *new* breaches (not previously seen) are logged/notified to avoid
 * alert fatigue.  The check fires at 03:00 UTC every day.
 */
@Injectable()
export class BreachMonitorScheduler {
  private readonly logger = new Logger(BreachMonitorScheduler.name);

  constructor(private readonly breachMonitorService: BreachMonitorService) {}

  /**
   * Daily job: for each opted-in email hash, re-check HIBP and surface any
   * new breaches discovered since the previous run.
   */
  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async runDailyBreachCheck(): Promise<void> {
    const hashes = this.breachMonitorService.allOptedInHashes();
    this.logger.log(
      `Daily breach check starting for ${hashes.length} opted-in address(es).`,
    );

    for (const hash of hashes) {
      try {
        const newBreaches = await this.breachMonitorService.runCheckAndDiff(hash);
        if (newBreaches.length > 0) {
          this.logger.warn(
            `[${hash.slice(0, 8)}…] ${newBreaches.length} new breach(es) found: ` +
              newBreaches.map((b) => b.name).join(', '),
          );
          // In a full implementation this would emit an in-app notification.
          // The payload sent is ONLY breach metadata — never the email address.
        } else {
          this.logger.log(`[${hash.slice(0, 8)}…] No new breaches.`);
        }
      } catch (err) {
        this.logger.error(
          `Error checking breaches for hash ${hash.slice(0, 8)}…`,
          err,
        );
      }
    }

    this.logger.log('Daily breach check complete.');
  }
}
