import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SyncModule } from './sync/sync.module';
import { HealthController } from './health.controller';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL,
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: true, // TEMPORARY: Auto-create tables for initial setup. Will be replaced with migrations.
      logging: false,
    }),
    SyncModule,
  ],
  controllers: [HealthController],
  providers: [],
})
export class AppModule { }
