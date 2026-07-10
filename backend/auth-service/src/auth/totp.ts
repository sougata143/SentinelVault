import * as crypto from 'crypto';

export class TotpHelper {
  /**
   * Generates a 32-character base32-encoded secret.
   * Uses cryptographically secure random bytes.
   */
  public static generateSecret(): string {
    const bytes = crypto.randomBytes(20);
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let secret = '';
    for (let i = 0; i < bytes.length; i++) {
      secret += alphabet[bytes[i] % 32];
    }
    return secret;
  }

  /**
   * Generates a provisioning URI for authenticator apps (e.g. Google Authenticator).
   */
  public static getProvisioningUri(username: string, secret: string): string {
    const label = encodeURIComponent(`SentinelVault:${username}`);
    const issuer = encodeURIComponent('SentinelVault');
    return `otpauth://totp/${label}?secret=${secret}&issuer=${issuer}`;
  }

  /**
   * Verifies a 6-digit TOTP code against a base32 secret.
   * Includes a time step window parameter to allow for network/clock skew.
   */
  public static verifyCode(secret: string, code: string, window = 1): boolean {
    const timeStep = 30; // 30-second intervals
    const currentTime = Math.floor(Date.now() / 1000);
    const currentStep = Math.floor(currentTime / timeStep);

    // Check steps in range [-window, +window]
    for (let i = -window; i <= window; i++) {
      const step = currentStep + i;
      if (this.generateCode(secret, step) === code) {
        return true;
      }
    }
    return false;
  }

  /**
   * Generates the 6-digit code for a given secret and time step.
   * Implements HMAC-SHA1 dynamic truncation per RFC 6238.
   */
  private static generateCode(secret: string, step: number): string {
    const key = this.decodeBase32(secret);

    // Convert step counter to 8-byte big-endian buffer
    const buffer = Buffer.alloc(8);
    let temp = BigInt(step);
    for (let i = 7; i >= 0; i--) {
      buffer[i] = Number(temp & 0xffn);
      temp >>= 8n;
    }

    // HMAC-SHA1
    const hmac = crypto.createHmac('sha1', key);
    hmac.update(buffer);
    const hash = hmac.digest();

    // Dynamic truncation
    const offset = hash[hash.length - 1] & 0xf;
    const binary =
      ((hash[offset] & 0x7f) << 24) |
      ((hash[offset + 1] & 0xff) << 16) |
      ((hash[offset + 2] & 0xff) << 8) |
      (hash[offset + 3] & 0xff);

    const code = binary % 1_000_000;
    return code.toString().padStart(6, '0');
  }

  /**
   * Decodes a base32 string into a raw Buffer.
   */
  private static decodeBase32(base32: string): Buffer {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    const clean = base32.toUpperCase().replace(/=+$/, '');
    const bytes: number[] = [];
    let buffer = 0;
    let bits = 0;

    for (let i = 0; i < clean.length; i++) {
      const val = alphabet.indexOf(clean[i]);
      if (val === -1) {
        throw new Error('Invalid base32 character');
      }

      buffer = (buffer << 5) | val;
      bits += 5;

      if (bits >= 8) {
        bytes.push((buffer >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return Buffer.from(bytes);
  }
}
