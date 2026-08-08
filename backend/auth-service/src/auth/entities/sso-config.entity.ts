import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('sso_configs')
export class SsoConfigEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ unique: true })
  domain!: string; // e.g. "@acme.corp" or "acme.corp"

  @Column({ name: 'issuer_url' })
  issuerUrl!: string; // e.g. "https://dev-12345.okta.com/oauth2/default"

  @Column({ name: 'client_id' })
  clientId!: string;

  @Column({ name: 'client_secret', nullable: true })
  clientSecret?: string;

  @Column({ name: 'team_vault_id', nullable: true })
  teamVaultId?: string;

  @Column({ name: 'is_enabled', default: true })
  isEnabled!: boolean;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;
}
