import { Entity, PrimaryColumn, Column } from 'typeorm';

@Entity('vault_keys')
export class VaultKey {
  @PrimaryColumn({ type: 'varchar', length: 255 })
  userId!: string; // References User.id from auth-service

  @Column({ type: 'varchar', length: 255 })
  salt!: string; // Master KDF salt (hex)

  @Column({ type: 'text' })
  wrappedKey!: string; // AES-256-GCM-wrapped vault key (hex)

  @Column({ type: 'varchar', length: 255, nullable: true })
  recoverySalt?: string; // Recovery KDF salt (hex) - for Emergency Kit

  @Column({ type: 'text', nullable: true })
  recoveryWrappedKey?: string; // Recovery-wrapped vault key (hex) - for Emergency Kit
}
