import { Entity, PrimaryColumn, Column, OneToMany, CreateDateColumn } from 'typeorm';
import { BreachEntry } from './breach-entry.entity';

@Entity('breach_opt_ins')
export class BreachOptIn {
  @PrimaryColumn({ type: 'varchar', length: 64 })
  emailHash!: string; // SHA-256 of email (64 hex chars) - independent identity space

  /**
   * Encrypted email address for scheduling periodic checks.
   * The raw email is never stored in plaintext.
   */
  @Column({ type: 'text' })
  encryptedEmail!: string;

  @CreateDateColumn({ type: 'timestamp' })
  optedInAt!: Date;

  @OneToMany(() => BreachEntry, (breach) => breach.breachOptIn, { cascade: true })
  breaches!: BreachEntry[];
}
