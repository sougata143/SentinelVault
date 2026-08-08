import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  Headers,
  HttpCode,
  HttpStatus,
  UseGuards,
  Req,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { SsoService } from './sso.service';
import { PatService } from './pat.service';
import { CreateSsoConfigDto, SsoLoginInitDto, SsoCallbackDto } from './sso-config.dto';
import { CreatePatDto } from './pat.dto';
import { JwtAuthGuard, AuthenticatedRequest } from '../common/jwt-auth.guard';

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly ssoService: SsoService,
    private readonly patService: PatService,
  ) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  public async register(
    @Body() body: { username: string; salt: string; verifier: string },
    @Headers('user-agent') userAgent?: string,
  ): Promise<{ success: boolean; token: string }> {
    return await this.authService.register(body.username, body.salt, body.verifier, userAgent);
  }

  @Get('users/lookup')
  public async lookupUser(
    @Query('email') email?: string,
    @Query('id') id?: string,
  ): Promise<{ ok: boolean; userId?: string; email?: string }> {
    if (email) {
      const user = await this.authService.lookupUserByEmail(email);
      if (!user) return { ok: false };
      return { ok: true, userId: user.id, email: user.username };
    }
    if (id) {
      const user = await this.authService.lookupUserById(id);
      if (!user) return { ok: false };
      return { ok: true, userId: user.id, email: user.username };
    }
    return { ok: false };
  }

  @Post('login/step1')
  @HttpCode(HttpStatus.OK)
  public async loginStep1(
    @Body() body: { username: string; A: string },
  ): Promise<{ salt: string; B: string; challengeId: string }> {
    return await this.authService.loginStep1(body.username, body.A);
  }

  @Post('login/step2')
  @HttpCode(HttpStatus.OK)
  public async loginStep2(
    @Body() body: { challengeId: string; M1: string },
    @Headers('user-agent') userAgent?: string,
  ): Promise<{ serverEvidence: string; token?: string; mfaRequired?: boolean; mfaToken?: string; allowedMethods?: string[] }> {
    return await this.authService.loginStep2(body.challengeId, body.M1, userAgent);
  }

  // ── TOTP Endpoints ──────────────────────────────────────────────────────

  @Post('mfa/totp/generate')
  @HttpCode(HttpStatus.OK)
  public async generateTotp(
    @Body() body: { username: string },
  ): Promise<{ secret: string; provisioningUri: string }> {
    return await this.authService.generateTotp(body.username);
  }

  @Post('mfa/totp/enable')
  @HttpCode(HttpStatus.OK)
  public async enableTotp(
    @Body() body: { username: string; code: string },
  ): Promise<{ success: boolean }> {
    return await this.authService.enableTotp(body.username, body.code);
  }

  @Post('mfa/totp/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyTotp(
    @Body() body: { mfaToken: string; code: string },
    @Headers('user-agent') userAgent?: string,
  ): Promise<{ token: string }> {
    return await this.authService.verifyTotp(body.mfaToken, body.code, userAgent);
  }

  // ── WebAuthn Endpoints ──────────────────────────────────────────────────

  @Post('mfa/webauthn/register/options')
  @HttpCode(HttpStatus.OK)
  public async generateWebAuthnRegisterOptions(
    @Body() body: { username: string },
  ): Promise<any> {
    return await this.authService.generateWebAuthnRegisterOptions(body.username);
  }

  @Post('mfa/webauthn/register/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyWebAuthnRegister(
    @Body() body: { username: string; response: any },
  ): Promise<{ success: boolean }> {
    return await this.authService.verifyWebAuthnRegister(body.username, body.response);
  }

  @Post('mfa/webauthn/login/options')
  @HttpCode(HttpStatus.OK)
  public async generateWebAuthnLoginOptions(
    @Body() body: { mfaToken: string },
  ): Promise<any> {
    return await this.authService.generateWebAuthnLoginOptions(body.mfaToken);
  }

  @Post('mfa/webauthn/login/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyWebAuthnLogin(
    @Body() body: { mfaToken: string; response: any },
    @Headers('user-agent') userAgent?: string,
  ): Promise<{ token: string }> {
    return await this.authService.verifyWebAuthnLogin(body.mfaToken, body.response, userAgent);
  }

  // ── Primary Passkey Endpoints ──────────────────────────────────────────

  @Post('passkey/register/options')
  @HttpCode(HttpStatus.OK)
  public async generatePasskeyRegisterOptions(
    @Body() body: { username: string },
  ): Promise<any> {
    return await this.authService.generatePasskeyRegisterOptions(body.username);
  }

  @Post('passkey/register/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyPasskeyRegister(
    @Body() body: { username: string; response: any },
  ): Promise<{ success: boolean }> {
    return await this.authService.verifyPasskeyRegister(body.username, body.response);
  }

  @Post('passkey/login/options')
  @HttpCode(HttpStatus.OK)
  public async generatePasskeyLoginOptions(
    @Body() body: { username?: string },
  ): Promise<any> {
    return await this.authService.generatePasskeyLoginOptions(body.username);
  }

  @Post('passkey/login/verify')
  @HttpCode(HttpStatus.OK)
  public async verifyPasskeyLogin(
    @Body() body: { challenge: string; response: any },
    @Headers('user-agent') userAgent?: string,
  ): Promise<{ token: string }> {
    return await this.authService.verifyPasskeyLogin(body.challenge, body.response, userAgent);
  }

  // ── Session Management Endpoints ──────────────────────────────────────────

  @Get('sessions')
  @UseGuards(JwtAuthGuard)
  public async getSessions(
    @Req() req: AuthenticatedRequest,
  ): Promise<any[]> {
    return await this.authService.getUserSessions(req.user!.id, req.user!.jti);
  }

  @Delete('sessions/:id')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  public async revokeSession(
    @Req() req: AuthenticatedRequest,
    @Param('id') sessionIdToRevoke: string,
  ): Promise<{ success: boolean }> {
    return await this.authService.revokeSession(
      req.user!.id,
      req.user!.jti,
      sessionIdToRevoke,
    );
  }

  // ── Audit Log Endpoints ──────────────────────────────────────────────────

  @Get('audit-log')
  public async getAuditLogs(
    @Query('userId') userId: string,
    @Query('eventType') eventType?: string,
    @Query('limit') limitStr?: string,
    @Query('offset') offsetStr?: string,
  ): Promise<{ events: any[]; total: number }> {
    const limit = limitStr ? parseInt(limitStr, 10) : 50;
    const offset = offsetStr ? parseInt(offsetStr, 10) : 0;
    return await this.authService.getAuditLogs(userId, eventType, limit, offset);
  }

  @Post('audit-log/event')
  @HttpCode(HttpStatus.CREATED)
  public async recordAuditEvent(
    @Body() body: { userId: string; eventType: string; metadata?: Record<string, any> },
  ): Promise<{ success: boolean; id: string }> {
    const event = await this.authService.recordAuditEvent(body.userId, body.eventType, body.metadata);
    return { success: true, id: event.id };
  }

  // ── SSO (OIDC / SAML) Endpoints ─────────────────────────────────────────────

  @Get('sso/config/:domain')
  public getSsoDomainConfig(@Param('domain') domain: string) {
    return this.ssoService.getConfigForDomain(domain);
  }

  @Post('sso/config')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  public createOrUpdateSsoConfig(@Body() dto: CreateSsoConfigDto) {
    return this.ssoService.createOrUpdateConfig(dto);
  }

  @Post('sso/login-init')
  @HttpCode(HttpStatus.OK)
  public initSsoLogin(@Body() dto: SsoLoginInitDto) {
    return this.ssoService.initSsoLogin(dto);
  }

  @Post('sso/callback')
  @HttpCode(HttpStatus.OK)
  public handleSsoCallback(@Body() dto: SsoCallbackDto) {
    return this.ssoService.handleSsoCallback(dto);
  }

  // ── Personal Access Tokens (PATs) Endpoints ─────────────────────────────────

  @Post('pats')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  public createPat(
    @Req() req: AuthenticatedRequest,
    @Body() dto: CreatePatDto,
  ) {
    return this.patService.createToken(req.user!.id, dto);
  }

  @Get('pats')
  @UseGuards(JwtAuthGuard)
  public getPats(@Req() req: AuthenticatedRequest) {
    return this.patService.getUserTokens(req.user!.id);
  }

  @Post('pats/:id/revoke')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  public revokePat(
    @Req() req: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.patService.revokeToken(req.user!.id, id);
  }
}

