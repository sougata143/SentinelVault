import { Entity, PrimaryColumn, Column, CreateDateColumn, Index } from 'typeorm';

@Entity('share_links')
export class ShareLinkEntity {
  @PrimaryColumn({ type: 'uuid' })
  shareId!: string;

  @Column({ name: 'owner_user_id' })
  @Index()
  ownerUserId!: string;

  @Column({ name: 'item_title', nullable: true })
  itemTitle?: string; // Optional metadata for owner UI

  @Column({ name: 'encrypted_blob', type: 'text' })
  encryptedBlob!: string; // Base64 ciphertext C_share

  @Column({ type: 'varchar', length: 255 })
  nonce!: string; // Base64 12-byte IV N_share

  @Column({ name: 'one_time_view', default: true })
  oneTimeView!: boolean;

  @Column({ name: 'view_count', default: 0 })
  viewCount!: number;

  @Column({ name: 'is_consumed', default: false })
  isConsumed!: boolean;

  @Column({ name: 'is_revoked', default: false })
  isRevoked!: boolean;

  @Column({ name: 'expires_at', type: 'timestamp' })
  expiresAt!: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
