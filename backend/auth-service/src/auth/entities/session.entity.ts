import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, Index } from 'typeorm';

@Entity('sessions')
export class SessionEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id', type: 'varchar', length: 255 })
  @Index()
  userId!: string;

  @Column({ name: 'device_label', type: 'varchar', length: 255 })
  deviceLabel!: string;

  @Column({ name: 'login_method', type: 'varchar', length: 100 })
  loginMethod!: string;

  @Column({ name: 'token_hash', type: 'varchar', length: 255, nullable: true })
  tokenHash?: string;

  @Column({ name: 'is_revoked', type: 'boolean', default: false })
  @Index()
  isRevoked!: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamp' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'last_active_at', type: 'timestamp' })
  lastActiveAt!: Date;
}
