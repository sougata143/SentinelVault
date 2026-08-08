export interface CreateSsoConfigDto {
  domain: string;
  issuerUrl: string;
  clientId: string;
  clientSecret?: string;
  teamVaultId?: string;
  isEnabled?: boolean;
}

export interface SsoDomainConfigDto {
  domain: string;
  ssoAvailable: boolean;
  issuerUrl?: string;
  teamVaultId?: string;
}

export interface SsoLoginInitDto {
  domain: string;
  redirectUri: string;
  codeChallenge: string;
  codeChallengeMethod?: string;
}

export interface SsoCallbackDto {
  code: string;
  state: string;
  codeVerifier: string;
  redirectUri: string;
}

export interface SsoSessionTokenResponseDto {
  sessionToken: string;
  user: {
    userId: string;
    email: string;
    masterKdfSalt?: string;
    wrappedVaultKey?: string;
  };
  /** Explicit security assertion flag verifying vault remains locked */
  vaultUnlocked: false;
}
