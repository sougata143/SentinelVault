import { Injectable, Logger } from '@nestjs/common';
import { BreachEntry, BreachStore } from './breach-store';

/**
 * Calls the HIBP v3 breachedaccount API to fetch breach metadata for an
 * email address that has explicitly opted in.
 *
 * Security rule: only `{ name, breachDate, dataClasses }` are extracted and
 * returned — the raw HIBP response body is never persisted or forwarded.
 */
@Injectable()
export class BreachMonitorService {
  private readonly logger = new Logger(BreachMonitorService.name);

  constructor(private readonly breachStore: BreachStore) {}

  /**
   * Fetches breach metadata for [email] from HIBP.
   *
   * The caller is responsible for ensuring the user has explicitly opted in
   * before this method is invoked.  The raw email is used only for the HTTP
   * request and is never stored by this service.
   *
   * @param email  The plaintext email address (never logged or stored here).
   * @returns Array of breach metadata entries.
   */
  async fetchBreachesForEmail(email: string): Promise<BreachEntry[]> {
    const apiKey = process.env.HIBP_API_KEY ?? '';
    if (!apiKey) {
      this.logger.warn(
        'HIBP_API_KEY is not set — email breach checks are disabled.',
      );
      return [];
    }

    const encoded = encodeURIComponent(email);
    const url = `https://haveibeenpwned.com/api/v3/breachedaccount/${encoded}?truncateResponse=false`;

    let resp: Response;
    try {
      resp = await fetch(url, {
        headers: {
          'hibp-api-key': apiKey,
          'user-agent': 'SentinelVault-BreachMonitor/1.0',
        },
      });
    } catch (err) {
      this.logger.error('Network error reaching HIBP', err);
      return [];
    }

    // 404 = no breaches found for this email — normal happy path.
    if (resp.status === 404) return [];

    if (resp.status === 401) {
      this.logger.error('HIBP returned 401 — check HIBP_API_KEY.');
      return [];
    }
    if (resp.status === 429) {
      this.logger.warn('HIBP rate limit hit — will retry on next schedule.');
      return [];
    }
    if (!resp.ok) {
      this.logger.error(`HIBP returned unexpected status ${resp.status}`);
      return [];
    }

    // Extract ONLY the metadata fields we need — discard everything else.
    const raw: Array<Record<string, unknown>> = (await resp.json()) as Array<
      Record<string, unknown>
    >;
    return raw.map((b) => ({
      name: (b['Name'] as string) ?? 'Unknown',
      breachDate: (b['BreachDate'] as string) ?? 'Unknown',
      dataClasses: (b['DataClasses'] as string[]) ?? [],
    }));
  }

  /**
   * Runs a breach check for [emailHash], diffs against stored results, and
   * returns only *new* breaches found since the last check.
   */
  async runCheckAndDiff(emailHash: string): Promise<BreachEntry[]> {
    const email = this.breachStore.getEmail(emailHash);
    if (!email) return [];

    const incoming = await this.fetchBreachesForEmail(email);
    return this.breachStore.updateBreaches(emailHash, incoming);
  }

  /** Registers an email for opt-in monitoring. */
  optIn(emailHash: string, email: string): void {
    this.breachStore.optIn(emailHash, email);
    this.logger.log(`Email hash ${emailHash.slice(0, 8)}… opted in.`);
  }

  /** Removes an email from monitoring. */
  optOut(emailHash: string): void {
    this.breachStore.optOut(emailHash);
    this.logger.log(`Email hash ${emailHash.slice(0, 8)}… opted out.`);
  }

  /** Returns stored breach metadata for [emailHash]. */
  getStoredBreaches(emailHash: string): BreachEntry[] {
    return this.breachStore.getBreaches(emailHash);
  }

  /** Returns true if [emailHash] is currently opted in. */
  isOptedIn(emailHash: string): boolean {
    return this.breachStore.isOptedIn(emailHash);
  }

  /** Returns all opted-in email hashes for the scheduler. */
  allOptedInHashes(): string[] {
    return this.breachStore.allOptedInHashes();
  }
}
