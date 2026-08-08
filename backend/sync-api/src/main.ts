import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  // Disable NestJS's built-in body parser so we can configure our own with a
  // larger size limit. A bulk NordPass/1Password import of 300+ items produces
  // a ~4-6 MB JSON payload — far above Express's default 100 KB cap.
  const app = await NestFactory.create(AppModule, { bodyParser: false });

  // Re-enable body parsing with a 50 MB limit.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const express = require('express');
  app.use(express.json({ limit: '50mb' }));
  app.use(express.urlencoded({ extended: true, limit: '50mb' }));

  app.enableCors({
    origin: true,
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
    allowedHeaders: ['Content-Type', 'Accept', 'Authorization', 'x-user-id', 'X-Requested-With'],
    exposedHeaders: ['Authorization', 'x-user-id'],
    optionsSuccessStatus: 204,
  });

  const port = process.env.PORT || 3002;
  await app.listen(port, '0.0.0.0');
  console.log(`Sync API Service is running on port ${port}`);
}
bootstrap();