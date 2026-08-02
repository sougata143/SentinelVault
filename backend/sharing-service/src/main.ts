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
      // Allow requests with no origin (e.g. mobile apps, curl, Postman)
      if (!origin) return callback(null, true);

      const defaultOrigins = [
        'http://localhost:8080',
        'http://localhost:8181',
        'http://localhost:3000',
        'http://localhost:4000',
        'http://localhost:59468',
      ];

      const allowedEnvOrigins = process.env.CORS_ALLOWED_ORIGINS
        ? process.env.CORS_ALLOWED_ORIGINS.split(',').map((o) => o.trim())
        : [];

      const allowedList = [...defaultOrigins, ...allowedEnvOrigins];

      if (allowedList.includes(origin)) {
        return callback(null, true);
      }

      // Allow any dynamic localhost or 127.0.0.1 port from flutter run -d chrome (e.g. port 64090)
      if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
        return callback(null, true);
      }

      callback(null, false);
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-user-id', 'Accept', 'X-Requested-With'],
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