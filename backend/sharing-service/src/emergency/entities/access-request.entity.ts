import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, Index } from 'typeorm';

@Entity('access_requests')
export class AccessRequestEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'contact_id' })
  @Index()
  contactId!: string;

  @Column({ name: 'owner_user_id' })
  @Index()
  ownerUserId!: string;

  @Column({ name: 'contact_user_id' })
  @Index()
  contactUserId!: string;

  @Column({ default: 'pending' })
  status!: 'pending' | 'denied' | 'granted' | 'cancelled';

  @CreateDateColumn({ name: 'requested_at' })
  requestedAt!: Date;

  @Column({ name: 'grants_at' })
  grantsAt!: Date;

  @Column({ name: 'resolved_at', nullable: true })
  resolvedAt?: Date;
}
