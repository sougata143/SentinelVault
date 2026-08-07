import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { EmergencyContactEntity } from './entities/emergency-contact.entity';
import { AccessRequestEntity } from './entities/access-request.entity';
import { EmergencyService } from './emergency.service';
import { EmergencyController } from './emergency.controller';

@Module({
  imports: [TypeOrmModule.forFeature([EmergencyContactEntity, AccessRequestEntity])],
  controllers: [EmergencyController],
  providers: [EmergencyService],
  exports: [EmergencyService],
})
export class EmergencyModule {}
