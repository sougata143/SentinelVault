import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

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

  const port = process.env.PORT || 3003;
  await app.listen(port);
  console.log(`Security Analysis Service is running on port ${port}`);
}
bootstrap();