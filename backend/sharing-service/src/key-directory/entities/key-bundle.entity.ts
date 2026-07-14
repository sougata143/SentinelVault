import { Entity, PrimaryColumn, Column, CreateDateColumn, UpdateDateColumn, Index } from 'typeorm';

@Entity('key_bundles')
export class KeyBundle {
  @PrimaryColumn({ type: 'uuid' })
  userId!: string; // References User.id from auth-service (shared identity space)

  @Column({ type: 'varchar', length: 255 })
  x25519PublicKey!: string; // base64url encoded (32 bytes → 44 chars)

  @Column({ type: 'varchar', length: 255 })
  ed25519PublicKey!: string; // base64url encoded (32 bytes)

  @Column({ type: 'text' })
  mlkemEncapsulationKey!: string; // base64url encoded (1184 bytes)

  @Column({ type: 'text' })
  mldsaVerifyingKey!: string; // base64url encoded (1952 bytes)

  @Column({ type: 'varchar', length: 64 })
  keyFingerprint!: string; // SHA-256 in hex (64 chars)

  @CreateDateColumn({ type: 'timestamp' })
  publishedAt!: Date;

  @UpdateDateColumn({ type: 'timestamp' })
  updatedAt!: Date;
}
