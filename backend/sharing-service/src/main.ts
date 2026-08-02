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
    origin: (origin, callback) => {
      if (!origin) return callback(null, true);

      const allowedEnvOrigins = process.env.CORS_ALLOWED_ORIGINS
        ? process.env.CORS_ALLOWED_ORIGINS.split(',').map((o) => o.trim())
        : [];
      if (allowedEnvOrigins.includes(origin)) {
        return callback(null, true);
      }

      if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
        return callback(null, true);
      }

      callback(new Error(`Origin ${origin} not allowed by CORS`), false);
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-user-id'],
    credentials: true,
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
  await app.listen(port);
  console.log(`[sharing-service] Listening on port ${port}`);
}

void bootstrap();