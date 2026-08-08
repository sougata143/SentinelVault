import { Entity, PrimaryColumn, Column, CreateDateColumn, UpdateDateColumn, Index } from 'typeorm';

@Entity('user_vaults')
export class UserVault {
  @PrimaryColumn({ type: 'uuid' })
  id!: string; // vaultId (UUID v4)

  @Column({ type: 'uuid' })
  @Index()
  userId!: string; // References User.id from auth-service

  @Column({ type: 'varchar', length: 255 })
  name!: string; // e.g. "Personal", "Work", "Finances"

  @Column({ type: 'varchar', length: 255 })
  salt!: string; // Master KDF salt (hex)

  @Column({ type: 'text' })
  wrappedKey!: string; // AES-256-GCM wrapped vault key (hex)

  @Column({ type: 'varchar', length: 255, nullable: true })
  recoverySalt?: string; // Emergency Kit salt (hex)

  @Column({ type: 'text', nullable: true })
  recoveryWrappedKey?: string; // Emergency Kit wrapped vault key (hex)

  @Column({ type: 'boolean', default: false })
  isDefault!: boolean;

  @CreateDateColumn({ type: 'timestamp' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamp' })
  updatedAt!: Date;
}
