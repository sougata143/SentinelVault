// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Sharing Service – main.ts
//  Bootstraps the NestJS sharing microservice.
// ─────────────────────────────────────────────────────────────────────────────
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SharingModule } from './sharing.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(SharingModule);

  app.enableCors({
    origin: true,
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
    allowedHeaders: ['Content-Type', 'Accept', 'Authorization', 'x-user-id', 'X-Requested-With'],
    exposedHeaders: ['Authorization', 'x-user-id'],
    optionsSuccessStatus: 204,
  });

  // Strict request-body validation
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const port = process.env['PORT'] ?? 3004;
  await app.listen(port, '0.0.0.0');
  console.log(`[sharing-service] Listening on port ${port}`);
}

void bootstrap();