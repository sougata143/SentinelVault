// ─────────────────────────────────────────────────────────────────────────────
//  SentinelVault – Key Directory DTOs
//
//  Security rule: the server NEVER sees private keys, plaintext Folder Keys,
//  or any vault item. It only stores public keys and wrapped (ciphertext)
//  Folder Key copies. This is enforced structurally — no DTO in this service
//  accepts private keys or raw Folder Key bytes.
// ─────────────────────────────────────────────────────────────────────────────
import {
  IsString,
  IsNotEmpty,
  IsBase64,
  IsUUID,
  IsArray,
  ValidateNested,
  IsOptional,
} from 'class-validator';
import { Type } from 'class-transformer';

// ── Publish (register/rotate) a user's public key bundle ────────────────────

export class PublishKeyBundleDto {
  /** Authenticated user ID (from JWT sub claim, validated by auth-service). */
  @IsUUID()
  userId!: string;

  /** X25519 public key – base64url encoded (32 bytes → 44 chars). */
  @IsString()
  @IsNotEmpty()
  x25519PublicKey!: string;

  /** Ed25519 public key – base64url encoded (32 bytes). */
  @IsString()
  @IsNotEmpty()
  ed25519PublicKey!: string;

  /** ML-KEM-768 encapsulation key – base64url encoded (1184 bytes). */
  @IsString()
  @IsNotEmpty()
  mlkemEncapsulationKey!: string;

  /** ML-DSA-65 verifying key – base64url encoded (1952 bytes). */
  @IsString()
  @IsNotEmpty()
  mldsaVerifyingKey!: string;

  /**
   * Client-computed fingerprint: SHA-256(x25519_pub || ed25519_pub ||
   * mlkem_ek || mldsa_vk) in hex. Stored verbatim; used for out-of-band
   * verification during share acceptance.
   */
  @IsString()
  @IsNotEmpty()
  keyFingerprint!: string;
}

// ── Look up another user's public key bundle ────────────────────────────────

export class GetKeyBundleDto {
  @IsUUID()
  targetUserId!: string;
}

// ── Publish a wrapped (ciphertext) Folder Key for a recipient ────────────────
// The server stores ONLY ciphertext; it cannot derive the Folder Key.

export class WrappedKeyRecordDto {
  /** Recipient user ID. */
  @IsUUID()
  recipientUserId!: string;

  /**
   * Ephemeral X25519 public key used in the ECDH step, base64url.
   * Needed by the recipient to derive the shared secret.
   */
  @IsString()
  @IsNotEmpty()
  ephemeralX25519PublicKey!: string;

  /** ML-KEM-768 ciphertext – base64url (1088 bytes). */
  @IsString()
  @IsNotEmpty()
  mlkemCiphertext!: string;

  /** AES-GCM nonce – base64url (12 bytes). */
  @IsString()
  @IsNotEmpty()
  aesNonce!: string;

  /** AES-256-GCM-wrapped Folder Key – base64url (48 bytes = 32 + 16 GCM tag). */
  @IsString()
  @IsNotEmpty()
  wrappedFolderKey!: string;
}

// ── Publish a batch of per-recipient wrapped Folder Keys ─────────────────────

export class PublishWrappedKeysDto {
  /** Folder / vault section this key version covers. */
  @IsUUID()
  folderId!: string;

  /**
   * Monotonically increasing version counter for the Folder Key.
   * Enforced server-side to prevent rollback attacks.
   */
  @IsString()
  @IsNotEmpty()
  keyVersion!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => WrappedKeyRecordDto)
  recipients!: WrappedKeyRecordDto[];
}

// ── Revoke (remove) a recipient's access to a folder ────────────────────────

export class RevokeRecipientDto {
  @IsUUID()
  folderId!: string;

  @IsUUID()
  recipientUserId!: string;

  /**
   * New key version being issued post-revocation.
   * The calling client must have already re-wrapped the new Folder Key
   * for ALL remaining recipients before sending this request.
   */
  @IsString()
  @IsNotEmpty()
  newKeyVersion!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => WrappedKeyRecordDto)
  remainingRecipients!: WrappedKeyRecordDto[];
}

// ── Fetch the wrapped Folder Key for the authenticated caller ────────────────

export class FetchWrappedKeyDto {
  @IsUUID()
  folderId!: string;

  @IsString()
  @IsOptional()
  keyVersion?: string; // omit to get the latest version
}
