import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn, CreateDateColumn, Index } from 'typeorm';
import { BreachOptIn } from './breach-opt-in.entity';

@Entity('breach_entries')
@Index(['emailHash', 'breachSource'], { unique: true }) // For upsert on unique constraint
export class BreachEntry {
  @PrimaryColumn({ type: 'uuid', generated: 'uuid' })
  id!: string;

  @Column({ type: 'varchar', length: 64 })
  emailHash!: string; // References BreachOptIn.emailHash (independent identity space)

  /**
   * Breach source identifier (e.g., 'hibp', 'custom-source').
   * Combined with emailHash for unique constraint to support upsert logic.
   */
  @Column({ type: 'varchar', length: 100 })
  breachSource!: string;

  @Column({ type: 'varchar', length: 255 })
  name!: string; // Breach name (e.g., "Adobe", "LinkedIn")

  @Column({ type: 'varchar', length: 50 })
  breachDate!: string; // ISO date string (e.g., "2013-10-04")

  @Column({ type: 'simple-array' })
  dataClasses!: string[]; // Array of data class strings

  @CreateDateColumn({ type: 'timestamp' })
  firstSeenAt!: Date;

  @ManyToOne(() => BreachOptIn, (optIn) => optIn.breaches, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'emailHash' })
  breachOptIn!: BreachOptIn;
}
