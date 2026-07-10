import { Module } from '@nestjs/common';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { FileReputationService } from './file-reputation.service';
import { FileReputationController } from './file-reputation.controller';
import { AiInsightsModule } from '../ai-insights/ai-insights.module';

@Module({
  imports: [
    // Store uploaded files in memory as Buffer — never written to disk.
    // The buffer is passed directly to VirusTotal and then discarded.
    MulterModule.register({ storage: memoryStorage() }),
    // Shared AI insights — guards and LLM call in one place.
    AiInsightsModule,
  ],
  controllers: [FileReputationController],
  providers: [FileReputationService],
  exports: [FileReputationService],
})
export class FileReputationModule {}

