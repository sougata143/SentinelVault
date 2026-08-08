import { SsoService } from '../src/auth/sso.service';
import { JwtService } from '@nestjs/jwt';
import { NotFoundException, UnauthorizedException } from '@nestjs/common';

describe('SsoService Zero-Knowledge & OIDC Flow Tests', () => {
  let service: SsoService;
  let jwtService: JwtService;

  beforeEach(() => {
    jwtService = new JwtService({ secret: 'test-secret-key-1234' });
    service = new SsoService(jwtService);
  });

  afterEach(() => {
    service.clear();
  });

  it('1. Domain lookup returns ssoAvailable = false when domain is unconfigured', () => {
    const config = service.getConfigForDomain('@unknown-corp.com');
    expect(config.ssoAvailable).toBe(false);
    expect(config.domain).toBe('@unknown-corp.com');
  });

  it('2. Admin registers domain SSO and lookup returns active configuration', () => {
    const created = service.createOrUpdateConfig({
      domain: 'acme.corp',
      issuerUrl: 'https://dev-12345.okta.com/oauth2/default',
      clientId: 'okta-client-id-999',
    });

    expect(created.domain).toBe('@acme.corp');
    expect(created.isEnabled).toBe(true);

    const lookup = service.getConfigForDomain('@acme.corp');
    expect(lookup.ssoAvailable).toBe(true);
    expect(lookup.issuerUrl).toBe('https://dev-12345.okta.com/oauth2/default');
  });

  it('3. Inits OIDC login PKCE flow and constructs authorize URL with S256 challenge', () => {
    service.createOrUpdateConfig({
      domain: 'acme.corp',
      issuerUrl: 'https://login.microsoftonline.com/tenant/v2.0',
      clientId: 'azure-client-id',
    });

    finalInit = service.initSsoLogin({
      domain: 'acme.corp',
      redirectUri: 'https://sentinelvault.app/sso/callback',
      codeChallenge: 'E9Mel-b5q6LuUJL2G5355P095DC447907542187654321',
      codeChallengeMethod: 'S256',
    });

    expect(finalInit.state).toBeDefined();
    expect(finalInit.authorizationUrl).toContain('login.microsoftonline.com');
    expect(finalInit.authorizationUrl).toContain('code_challenge=E9Mel-b5q6LuUJL2G5355P095DC447907542187654321');
    expect(finalInit.authorizationUrl).toContain('code_challenge_method=S256');
  });

  let finalInit: { authorizationUrl: string; state: string };

  it('4. Handles OIDC callback and issues account session JWT', async () => {
    service.createOrUpdateConfig({
      domain: 'acme.corp',
      issuerUrl: 'https://dev-12345.okta.com/oauth2/default',
      clientId: 'okta-client-id',
    });

    const init = service.initSsoLogin({
      domain: 'acme.corp',
      redirectUri: 'https://sentinelvault.app/sso/callback',
      codeChallenge: 'E9Mel-b5q6LuUJL2G5355P095DC447907542187654321',
    });

    const res = await service.handleSsoCallback({
      code: 'mock-authorization-code-123',
      state: init.state,
      codeVerifier: 'mock-code-verifier-string',
      redirectUri: 'https://sentinelvault.app/sso/callback',
    });

    expect(res.sessionToken).toBeDefined();
    expect(res.user.email).toContain('@acme.corp');

    const decoded = jwtService.verify(res.sessionToken);
    expect(decoded.domain).toBe('@acme.corp');
    expect(decoded.authMethod).toBe('oidc_sso');
  });

  it('5. ZERO-KNOWLEDGE BOUNDARY ASSERTION: SSO completion leaves vault strictly LOCKED', async () => {
    service.createOrUpdateConfig({
      domain: 'enterprise.corp',
      issuerUrl: 'https://sso.enterprise.corp',
      clientId: 'ent-client-id',
    });

    const init = service.initSsoLogin({
      domain: 'enterprise.corp',
      redirectUri: 'https://sentinelvault.app/sso/callback',
      codeChallenge: 'challenge',
    });

    const res = await service.handleSsoCallback({
      code: 'auth-code',
      state: init.state,
      codeVerifier: 'verifier',
      redirectUri: 'https://sentinelvault.app/sso/callback',
    });

    // Explicit security invariant assertion:
    // The SSO response MUST specify vaultUnlocked: false
    expect(res.vaultUnlocked).toBe(false);
    expect(res.user).not.toHaveProperty('vaultKey');
    expect(res.user).not.toHaveProperty('masterPassword');
  });

  it('6. Rejects callback with invalid or expired state parameter', async () => {
    await expect(
      service.handleSsoCallback({
        code: 'auth-code',
        state: 'invalid-state-uuid',
        codeVerifier: 'verifier',
        redirectUri: 'https://sentinelvault.app/sso/callback',
      }),
    ).rejects.toThrow(UnauthorizedException);
  });
});
