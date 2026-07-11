import { Controller, Post, Body, HttpCode, HttpStatus, Get, Query } from '@nestjs/common';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  public async register(
    @Body() body: { username: string; salt: string; verifier: string },
  ): Promise<{ success: boolean }> {
    return await this.authService.register(body.username, body.salt, body.verifier);
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
  ): Promise<{ serverEvidence: string; token?: string; mfaRequired?: boolean; mfaToken?: string; allowedMethods?: string[] }> {
    return await this.authService.loginStep2(body.challengeId, body.M1);
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
  ): Promise<{ token: string }> {
    return await this.authService.verifyTotp(body.mfaToken, body.code);
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
  ): Promise<{ token: string }> {
    return await this.authService.verifyWebAuthnLogin(body.mfaToken, body.response);
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
  ): Promise<{ token: string }> {
    return await this.authService.verifyPasskeyLogin(body.challenge, body.response);
  }
}
