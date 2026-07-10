import {
  Body,
  Controller,
  ForbiddenException,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  FileReputationService,
  FullScanResult,
  ReputationVerdict,
} from './file-reputation.service';
import { AiInsightsService } from '../ai-insights/ai-insights.service';
import { InsightsResult } from '../ai-insights/insights-payload';

/** Combined hash-lookup response including AI insights. */
interface HashLookupResponse {
  verdict: ReputationVerdict;
  /** AI-generated summary of the file's risk profile. */
  aiInsights: InsightsResult;
}

/**
 * REST endpoints for the three-layer file reputation system.
 *
 * Security rules enforced here:
 * - `/hash-lookup` accepts ONLY a sha256 string — never file bytes.
 * - `/full-scan` requires the `x-user-consent: true` header, which the client
 *   sets only after displaying the per-file disclosure dialog.  Requests
 *   without it are rejected with HTTP 403 — no file bytes are processed.
 * - AI insights receive ONLY `{ file_extension, signature_mismatch,
 *   double_extension, macro_detected, reputation_verdict }` — no filenames,
 *   paths, or file content.
 */
@Controller('file-reputation')
export class FileReputationController {
  constructor(
    private readonly fileRepService: FileReputationService,
    private readonly aiInsights: AiInsightsService,
  ) {}


  /**
   * Layer 2 — SHA-256 hash reputation lookup.
   *
   * Only the sha256 string is accepted.  File contents must never be included
   * in this request.
   *
   * AI signal: `{ file_extension, signature_mismatch, double_extension,
   * macro_detected, reputation_verdict }` — no filename or file content.
   */
  @Post('hash-lookup')
  @HttpCode(HttpStatus.OK)
  async hashLookup(
    @Body()
    dto: {
      sha256: string;
      /** Lowercased file extension from the client-side Layer-1 scan. */
      file_extension?: string;
      signature_mismatch?: boolean;
      double_extension?: boolean;
      macro_detected?: boolean;
    },
  ): Promise<HashLookupResponse> {
    // Basic validation: sha256 must be 64 hex chars.
    if (!/^[a-f0-9]{64}$/i.test(dto.sha256)) {
      throw new ForbiddenException('Invalid SHA-256 format.');
    }
    const verdict = await this.fileRepService.lookupHash(dto.sha256);

    // AI insights — only structured Layer-1 signals + reputation verdict.
    const aiInsights = await this.aiInsights.generateInsights({
      finding_type: 'file_scan',
      file_extension: dto.file_extension ?? 'unknown',
      signature_mismatch: dto.signature_mismatch ?? false,
      double_extension: dto.double_extension ?? false,
      macro_detected: dto.macro_detected ?? false,
      reputation_verdict: verdict.verdict,
    });

    return { verdict, aiInsights };
  }

  /**
   * Layer 3 — Full file upload to VirusTotal.
   *
   * **REQUIRES `x-user-consent: true` header.**
   * This header must be set by the client *only* after the user has explicitly
   * confirmed the per-file disclosure dialog naming the file and VirusTotal.
   *
   * Without this header the request is rejected with HTTP 403 and the file
   * bytes are never forwarded.
   */
  @Post('full-scan')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file'))
  async fullScan(
    @Headers('x-user-consent') consent: string,
    @UploadedFile() file: Express.Multer.File,
  ): Promise<FullScanResult> {
    // Gate: consent header must be present and explicitly set to 'true'.
    if (consent !== 'true') {
      throw new ForbiddenException(
        'Full file scan requires explicit user consent. ' +
          'Send x-user-consent: true after displaying the disclosure dialog.',
      );
    }
    if (!file) {
      throw new ForbiddenException('No file provided.');
    }
    return this.fileRepService.submitFile(file.buffer, file.originalname);
  }
}
