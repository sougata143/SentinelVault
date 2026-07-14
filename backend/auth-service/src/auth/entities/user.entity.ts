import { Entity, PrimaryGeneratedColumn, Column, OneToMany, CreateDateColumn, UpdateDateColumn, Index } from 'typeorm';
import { WebauthnCredential } from './webauthn-credential.entity';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id!: string; // Generated UUID primary key

  @Column({ type: 'varchar', length: 255, unique: true })
  @Index() // Index for efficient lookups
  username!: string; // Case-insensitive lookup handled in repository

  @Column({ type: 'varchar', length: 255 })
  salt!: string; // Hex string representation

  @Column({ type: 'text' })
  verifier!: string; // Hex string representation of BigInt verifier

  @Column({ type: 'int', default: 0 })
  failedAttempts!: number;

  @Column({ type: 'timestamp', nullable: true })
  lockoutUntil!: Date | null;

  // TOTP configuration
  @Column({ type: 'varchar', length: 255, nullable: true })
  totpSecret?: string;

  @Column({ type: 'boolean', default: false })
  totpEnabled!: boolean;

  // WebAuthn configuration
  @Column({ type: 'boolean', default: false })
  webauthnEnabled!: boolean;

  @OneToMany(() => WebauthnCredential, (credential) => credential.user, { cascade: true })
  webauthnCredentials!: WebauthnCredential[];

  @CreateDateColumn({ type: 'timestamp' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamp' })
  updatedAt!: Date;
}
