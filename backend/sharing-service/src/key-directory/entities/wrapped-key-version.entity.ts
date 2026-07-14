import { Entity, PrimaryColumn, Column, OneToMany, CreateDateColumn, Index } from 'typeorm';
import { WrappedKeyRecipient } from './wrapped-key-recipient.entity';

@Entity('wrapped_key_versions')
@Index(['folderId', 'keyVersion']) // For efficient version lookup
export class WrappedKeyVersion {
  @PrimaryColumn({ type: 'uuid' })
  folderId!: string;

  @PrimaryColumn({ type: 'varchar', length: 255 })
  keyVersion!: string; // Monotonically increasing version counter

  @CreateDateColumn({ type: 'timestamp' })
  publishedAt!: Date;

  @OneToMany(() => WrappedKeyRecipient, (recipient) => recipient.wrappedKeyVersion, { cascade: true })
  recipients!: WrappedKeyRecipient[];
}
