import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, Index } from 'typeorm';

@Entity('personal_access_tokens')
export class PersonalAccessTokenEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'user_id' })
  @Index()
  userId!: string;

  @Column()
  name!: string; // e.g. "CI/CD Pipeline Bot"

  @Column({ name: 'token_prefix', length: 24 })
  tokenPrefix!: string; // e.g. "pat_sv_live_a1b2..." for UI display

  @Column({ name: 'token_hash', unique: true })
  tokenHash!: string; // SHA-256(raw_token)

  @Column('simple-array')
  scopes!: string[]; // e.g. ['vault:read', 'vault:write']

  @Column({ name: 'expires_at', type: 'timestamp', nullable: true })
  expiresAt?: Date;

  @Column({ name: 'last_used_at', type: 'timestamp', nullable: true })
  lastUsedAt?: Date;

  @Column({ name: 'is_revoked', default: false })
  isRevoked!: boolean;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
