import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors({
    origin: true,
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
    allowedHeaders: ['Content-Type', 'Accept', 'Authorization', 'x-user-id', 'X-Requested-With'],
    exposedHeaders: ['Authorization', 'x-user-id'],
    optionsSuccessStatus: 204,
  });

  const port = process.env.PORT || 3003;
  await app.listen(port, '0.0.0.0');
  console.log(`Security Analysis Service is running on port ${port}`);
}
bootstrap();