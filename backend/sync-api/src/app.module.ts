import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
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
    /** JWT_SECRET is the same root .env secret shared by all four backend services.
     *  auth-service signs tokens with it; sync-api verifies them with the same key. */
    JwtModule.registerAsync({
      global: true,
      useFactory: () => ({
        secret: process.env.JWT_SECRET,
        signOptions: { expiresIn: '24h' },
      }),
    }),
    SyncModule,
  ],
  controllers: [HealthController],
  providers: [],
})
export class AppModule { }
