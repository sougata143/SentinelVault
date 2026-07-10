import { Injectable, Logger } from '@nestjs/common';

/** Reputation verdict returned by the VirusTotal hash lookup. */
export interface ReputationVerdict {
  /** Overall classification: 'clean' | 'malicious' | 'suspicious' | 'unknown' */
  verdict: 'clean' | 'malicious' | 'suspicious' | 'unknown';
  /** Number of AV engines that flagged the file (0 for clean/unknown). */
  positives: number;
  /** Total number of AV engines that processed the file. */
  total: number;
  /** SHA-256 that was queried. */
  sha256: string;
}

/** Result of a VirusTotal full-file submission (Layer 3). */
export interface FullScanResult {
  /** VirusTotal analysis ID — can be used to poll for results. */
  analysisId: string;
  /** Human-readable link to the VirusTotal analysis page. */
  analysisUrl: string;
}

/**
 * Calls the VirusTotal v3 API for:
 *  - Layer 2: SHA-256 hash-only reputation lookups (no file content transmitted).
 *  - Layer 3: Full file upload (only after explicit user consent is confirmed).
 *
 * Security rules:
 * - [lookupHash] sends ONLY the sha256 string — file contents never leave the
 *   device through this method.
 * - [submitFile] must only be called from an endpoint that has already
 *   validated the `x-user-consent: true` header (set by the client after the
 *   per-file disclosure dialog).
 * - Only `{verdict, positives, total, sha256}` is stored / returned — raw
 *   VirusTotal API responses are stripped before returning.
 */
@Injectable()
export class FileReputationService {
  private readonly logger = new Logger(FileReputationService.name);
  private readonly vtBase = 'https://www.virustotal.com/api/v3';

  private get apiKey(): string {
    return process.env.VIRUSTOTAL_API_KEY ?? '';
  }

  /**
   * Layer 2 — Queries VirusTotal for the reputation of a file by its SHA-256
   * hash alone.  No file contents are transmitted.
   *
   * Returns `verdict: 'unknown'` when the hash has never been submitted to VT
   * (404) or the API key is not configured.
   */
  async lookupHash(sha256: string): Promise<ReputationVerdict> {
    if (!this.apiKey) {
      this.logger.warn('VIRUSTOTAL_API_KEY not set — hash lookup disabled.');
      return { verdict: 'unknown', positives: 0, total: 0, sha256 };
    }

    let resp: Response;
    try {
      resp = await fetch(`${this.vtBase}/files/${sha256}`, {
        headers: { 'x-apikey': this.apiKey },
      });
    } catch (err) {
      this.logger.error('Network error reaching VirusTotal', err);
      return { verdict: 'unknown', positives: 0, total: 0, sha256 };
    }

    // 404 = hash not known to VirusTotal → verdict is unknown, not clean.
    if (resp.status === 404) {
      return { verdict: 'unknown', positives: 0, total: 0, sha256 };
    }
    if (resp.status === 401) {
      this.logger.error('VirusTotal returned 401 — check VIRUSTOTAL_API_KEY.');
      return { verdict: 'unknown', positives: 0, total: 0, sha256 };
    }
    if (resp.status === 429) {
      this.logger.warn('VirusTotal rate limit — will retry later.');
      return { verdict: 'unknown', positives: 0, total: 0, sha256 };
    }
    if (!resp.ok) {
      this.logger.error(`VirusTotal returned unexpected status ${resp.status}`);
      return { verdict: 'unknown', positives: 0, total: 0, sha256 };
    }

    // Extract only the fields we need — discard all other API response data.
    const body = (await resp.json()) as {
      data?: { attributes?: { last_analysis_stats?: Record<string, number> } };
    };
    const stats = body?.data?.attributes?.last_analysis_stats ?? {};
    const malicious = (stats['malicious'] as number) ?? 0;
    const suspicious = (stats['suspicious'] as number) ?? 0;
    const total = Object.values(stats).reduce(
      (sum: number, v) => sum + (v as number),
      0,
    );

    let verdict: ReputationVerdict['verdict'];
    if (malicious > 0) verdict = 'malicious';
    else if (suspicious > 0) verdict = 'suspicious';
    else verdict = 'clean';

    return { verdict, positives: malicious + suspicious, total, sha256 };
  }

  /**
   * Layer 3 — Submits the raw file bytes to VirusTotal for a full scan.
   *
   * **This method MUST only be called after the client has presented the
   * per-file disclosure dialog and the `x-user-consent: true` header has
   * been validated by the controller.**
   *
   * Returns the VirusTotal analysis ID and permalink.
   */
  async submitFile(
    fileBuffer: Buffer,
    filename: string,
  ): Promise<FullScanResult> {
    if (!this.apiKey) {
      throw new Error('VIRUSTOTAL_API_KEY not configured.');
    }

    const form = new FormData();
    form.append(
      'file',
      new Blob([new Uint8Array(fileBuffer)]),
      filename,
    );

    const resp = await fetch(`${this.vtBase}/files`, {
      method: 'POST',
      headers: { 'x-apikey': this.apiKey },
      body: form,
    });

    if (!resp.ok) {
      throw new Error(`VirusTotal file submit failed: ${resp.status}`);
    }

    const body = (await resp.json()) as {
      data?: { id?: string; links?: { self?: string } };
    };
    const analysisId = body?.data?.id ?? '';
    const analysisUrl = body?.data?.links?.self ?? '';
    return { analysisId, analysisUrl };
  }
}
