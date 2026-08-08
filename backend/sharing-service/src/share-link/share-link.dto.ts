export interface CreateShareLinkDto {
  encryptedBlob: string;
  nonce: string;
  itemTitle?: string;
  expiryHours: number; // e.g., 1, 12, 24, 72, 168
  oneTimeView?: boolean;
}

export interface ShareLinkPublicDto {
  shareId: string;
  encryptedBlob: string;
  nonce: string;
  expiresAt: string;
  oneTimeView: boolean;
}

export interface ShareLinkOwnerDto {
  shareId: string;
  itemTitle?: string;
  expiresAt: string;
  oneTimeView: boolean;
  viewCount: number;
  isConsumed: boolean;
  isRevoked: boolean;
  createdAt: string;
}
