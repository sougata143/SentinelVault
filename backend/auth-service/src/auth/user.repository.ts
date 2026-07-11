import { Injectable } from '@nestjs/common';

export interface UserRecord {
  username: string;
  salt: string; // Hex string representation
  verifier: string; // Hex string representation of BigInt verifier
  failedAttempts: number;
  lockoutUntil: Date | null;
  // TOTP configuration
  totpSecret?: string;
  totpEnabled: boolean;
  // WebAuthn configuration
  webauthnEnabled: boolean;
  webauthnCredentials?: Array<{
    credentialID: string;
    publicKey: string; // base64url or hex format
    counter: number;
    transports?: string[];
  }>;
}

@Injectable()
export class UserRepository {
  private readonly users: Map<string, UserRecord> = new Map();

  /**
   * Finds a user record by their username (case-insensitive).
   */
  public async findByUsername(username: string): Promise<UserRecord | null> {
    const record = this.users.get(username.toLowerCase());
    if (!record) return null;
    return { ...record };
  }

  /**
   * Saves or updates a user record.
   */
  public async save(record: UserRecord): Promise<UserRecord> {
    const copy = Object.assign({ totpEnabled: false, webauthnEnabled: false }, record);
    this.users.set(record.username.toLowerCase(), copy);
    return copy;
  }

  /**
   * Finds a user record by a registered credential ID.
   */
  public async findByCredentialId(credentialId: string): Promise<UserRecord | null> {
    for (const user of this.users.values()) {
      const match = user.webauthnCredentials?.some((c) => c.credentialID === credentialId);
      if (match) {
        return { ...user };
      }
    }
    return null;
  }

  /**
   * Resets all user records (used for test cleanup).
   */
  public async clear(): Promise<void> {
    this.users.clear();
  }
}
