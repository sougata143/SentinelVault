// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Sharing Service – main.ts
//  Bootstraps the NestJS sharing microservice.
// ─────────────────────────────────────────────────────────────────────────────
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SharingModule } from './sharing.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(SharingModule);

  // Strict request-body validation
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const port = process.env['PORT'] ?? 3002;
  await app.listen(port);
  console.log(`[sharing-service] Listening on port ${port}`);
}

void bootstrap();
