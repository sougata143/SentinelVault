export type SharedVaultRole = 'admin' | 'member' | 'viewer';

export interface SharedVaultMemberInput {
  userId: string;
  role: SharedVaultRole;
  wrappedKeyPayload: string;
}

export class CreateSharedVaultDto {
  name!: string;
  members!: SharedVaultMemberInput[];
}

export class AddVaultMemberDto {
  userId!: string;
  role!: SharedVaultRole;
  wrappedKeyPayload!: string;
}

export class UpdateMemberRoleDto {
  role!: SharedVaultRole;
}

export interface WrappedKeyInput {
  userId: string;
  wrappedKeyPayload: string;
}

export class RotateVaultKeysDto {
  keyVersion!: number;
  wrappedKeys!: WrappedKeyInput[];
}
