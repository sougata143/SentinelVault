import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

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

  const port = process.env.PORT || 3001;
  await app.listen(port);
  console.log(`Auth Service is running on port ${port}`);
}
bootstrap();