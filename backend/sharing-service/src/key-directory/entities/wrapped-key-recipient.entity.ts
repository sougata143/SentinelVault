import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn, CreateDateColumn, Index } from 'typeorm';
import { WrappedKeyVersion } from './wrapped-key-version.entity';

/**
 * One row per (recipient, folder, keyVersion) triple.
 *
 * Composite primary key (recipientUserId, folderId, keyVersion) so a user can
 * hold wrapped copies across multiple folders and multiple key-rotations of the
 * same folder.  The former single-column PK was wrong — it allowed only one
 * wrapped copy per recipient globally.
 */
@Entity('wrapped_key_recipients')
@Index(['recipientUserId', 'folderId', 'keyVersion'], { unique: true })
export class WrappedKeyRecipient {
  /** Part 1 of the composite PK — the recipient's user UUID. */
  @PrimaryColumn({ type: 'uuid' })
  recipientUserId!: string; // References User.id from auth-service

  /** Part 2 of the composite PK — the folder UUID. */
  @PrimaryColumn({ type: 'uuid' })
  folderId!: string;

  /** Part 3 of the composite PK — the key version string. */
  @PrimaryColumn({ type: 'varchar', length: 255 })
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
