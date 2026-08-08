import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, Index } from 'typeorm';

@Entity('emergency_contacts')
export class EmergencyContactEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'owner_user_id' })
  @Index()
  ownerUserId!: string;

  @Column({ name: 'contact_user_id' })
  @Index()
  contactUserId!: string;

  @Column({ name: 'contact_email' })
  contactEmail!: string;

  @Column({ name: 'waiting_period_hours', default: 72 })
  waitingPeriodHours!: number;

  @Column({ default: 'active' })
  status!: 'active' | 'revoked';

  @Column({ name: 'vault_id', type: 'uuid', nullable: true })
  @Index()
  vaultId?: string;

  @Column({ name: 'wrapped_vault_key', type: 'text', nullable: true })
  wrappedVaultKey?: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
