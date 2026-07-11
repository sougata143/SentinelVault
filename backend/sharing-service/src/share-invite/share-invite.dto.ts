import { IsString, IsNotEmpty, IsUUID, IsOptional } from 'class-validator';

// ── Create / send a share invitation ─────────────────────────────────────────

export class CreateInviteDto {
  /** Folder being shared. */
  @IsUUID()
  folderId!: string;

  /** User being invited. */
  @IsUUID()
  recipientUserId!: string;

  /**
   * Signed invitation payload – base64url.
   * The backend does NOT verify the dual signature; that is done by the
   * recipient's device using the sender's public keys fetched from the key
   * directory. The server only stores opaque ciphertext payloads.
   */
  @IsString()
  @IsNotEmpty()
  signedPayload!: string;

  /** Ed25519 signature over signedPayload – base64url (64 bytes). */
  @IsString()
  @IsNotEmpty()
  ed25519Signature!: string;

  /** ML-DSA-65 signature over signedPayload – base64url (3309 bytes). */
  @IsString()
  @IsNotEmpty()
  mldsaSignature!: string;

  /**
   * Pre-wrapped Folder Key for the recipient (ciphertext).
   * Only stored after the recipient accepts AND confirms the fingerprint.
   */
  @IsString()
  @IsNotEmpty()
  wrappedFolderKeyPayload!: string;
}

// ── Accept a share invitation ─────────────────────────────────────────────────

export class AcceptInviteDto {
  @IsUUID()
  inviteId!: string;

  /**
   * The recipient must confirm they have verified the sender's key
   * fingerprint out-of-band before accepting. This flag being true is a
   * prerequisite — the server enforces it as a gate.
   *
   * Surface this as a deliberate user action in the UI, never auto-set it.
   */
  @IsString()
  fingerprintConfirmed!: 'true'; // strict: only the string 'true' is valid
}

// ── Decline / revoke a share invitation ──────────────────────────────────────

export class DeclineInviteDto {
  @IsUUID()
  inviteId!: string;

  @IsString()
  @IsOptional()
  reason?: string;
}
