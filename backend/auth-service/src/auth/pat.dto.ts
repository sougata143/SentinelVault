export interface CreatePatDto {
  name: string;
  scopes: string[]; // e.g., ['vault:read', 'vault:write', 'sharing:read']
  expiryDays?: number; // e.g., 30, 90, 365, or null/0 for Never
}

export interface CreatePatResponseDto {
  id: string;
  name: string;
  rawToken: string; // SHOWN ONLY ONCE UPON CREATION
  tokenPrefix: string;
  scopes: string[];
  expiresAt?: string;
  createdAt: string;
}

export interface PatListItemDto {
  id: string;
  name: string;
  tokenPrefix: string;
  scopes: string[];
  expiresAt?: string;
  lastUsedAt?: string;
  isRevoked: boolean;
  createdAt: string;
}
