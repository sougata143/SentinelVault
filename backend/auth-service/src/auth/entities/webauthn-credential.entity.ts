import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn, CreateDateColumn, Index } from 'typeorm';
import { User } from './user.entity';

@Entity('webauthn_credentials')
export class WebauthnCredential {
  @PrimaryColumn({ type: 'varchar', length: 255 })
  credentialID!: string;

  @Column({ type: 'text' })
  publicKey!: string; // base64url or hex format

  @Column({ type: 'bigint', default: 0 })
  counter!: number;

  @Column({ type: 'simple-array', nullable: true })
  transports?: string[]; // Stored as array in PostgreSQL

  @Column({ type: 'uuid' })
  @Index() // Index for efficient user lookups
  userId!: string; // Foreign key to User.id (UUID)

  @ManyToOne(() => User, (user) => user.webauthnCredentials, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user!: User;

  @CreateDateColumn({ type: 'timestamp' })
  registeredAt!: Date;
}
