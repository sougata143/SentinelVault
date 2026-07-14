import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn, CreateDateColumn, Index } from 'typeorm';
import { WrappedKeyVersion } from './wrapped-key-version.entity';

@Entity('wrapped_key_recipients')
@Index(['recipientUserId', 'folderId', 'keyVersion'], { unique: true }) // Unique constraint for composite key
export class WrappedKeyRecipient {
  @PrimaryColumn({ type: 'uuid' })
  recipientUserId!: string; // References User.id from auth-service

  @Column({ type: 'uuid' })
  folderId!: string;

  @Column({ type: 'varchar', length: 255 })
  keyVersion!: string;

  /**
   * Ephemeral X25519 public key used in the ECDH step, base64url.
   * Needed by the recipient to derive the shared secret.
   */
  @Column({ type: 'varchar', length: 255 })
  ephemeralX25519PublicKey!: string;

  /** ML-KEM-768 ciphertext – base64url (1088 bytes). */
  @Column({ type: 'text' })
  mlkemCiphertext!: string;

  /** AES-GCM nonce – base64url (12 bytes). */
  @Column({ type: 'varchar', length: 255 })
  aesNonce!: string;

  /** AES-256-GCM-wrapped Folder Key – base64url (48 bytes = 32 + 16 GCM tag). */
  @Column({ type: 'varchar', length: 255 })
  wrappedFolderKey!: string;

  /**
   * Timestamp when this recipient's access was revoked (if applicable).
   * NULL means access is still active for this key version.
   */
  @Column({ type: 'timestamp', nullable: true })
  revokedAt?: Date;

  @CreateDateColumn({ type: 'timestamp' })
  createdAt!: Date;

  // Composite foreign key to wrapped_key_versions
  @ManyToOne(() => WrappedKeyVersion, (version) => version.recipients, {
    onDelete: 'CASCADE',
  })
  @JoinColumn([
    { name: 'folderId', referencedColumnName: 'folderId' },
    { name: 'keyVersion', referencedColumnName: 'keyVersion' },
  ])
  wrappedKeyVersion!: WrappedKeyVersion;
}
