import { Entity, PrimaryColumn, Column, CreateDateColumn, UpdateDateColumn, Index } from 'typeorm';

@Entity('encrypted_vault_items')
export class EncryptedVaultItem {
  @PrimaryColumn({ type: 'uuid' })
  id!: string;

  @Column({ type: 'text' })
  encryptedBlob!: string;

  @Column({ type: 'varchar', length: 255 })
  nonce!: string;

  @Column({ type: 'int' })
  version!: number;

  @Column({ type: 'boolean', default: false })
  isDeleted!: boolean;

  @Column({ type: 'uuid' })
  @Index() // Index for efficient user lookups
  userId!: string; // References User.id from auth-service

  @CreateDateColumn({ type: 'timestamp' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamp' })
  updatedAt!: Date;
}