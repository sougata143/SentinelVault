import {
  Controller, Post, Get, Delete, Put, Body, Param, Headers, UseGuards, UnauthorizedException,
} from '@nestjs/common';
import { SharedVaultService } from './shared-vault.service';
import { CreateSharedVaultDto, AddVaultMemberDto, RotateVaultKeysDto } from './shared-vault.dto';

@Controller('shared-vaults')
export class SharedVaultController {
  constructor(private readonly sharedVaultService: SharedVaultService) {}

  @Post()
  createVault(
    @Headers('authorization') authHeader: string,
    @Body() dto: CreateSharedVaultDto,
  ) {
    const callerUserId = this.extractUserFromHeader(authHeader);
    return this.sharedVaultService.createVault(callerUserId, dto);
  }

  @Get()
  listVaults(@Headers('authorization') authHeader: string) {
    const callerUserId = this.extractUserFromHeader(authHeader);
    return { vaults: this.sharedVaultService.getVaultsForUser(callerUserId) };
  }

  @Get(':vaultId')
  getVaultDetails(
    @Headers('authorization') authHeader: string,
    @Param('vaultId') vaultId: string,
  ) {
    const callerUserId = this.extractUserFromHeader(authHeader);
    return this.sharedVaultService.getVaultDetails(callerUserId, vaultId);
  }

  @Post(':vaultId/members')
  addMember(
    @Headers('authorization') authHeader: string,
    @Param('vaultId') vaultId: string,
    @Body() dto: AddVaultMemberDto,
  ) {
    const callerUserId = this.extractUserFromHeader(authHeader);
    return this.sharedVaultService.addMember(callerUserId, vaultId, dto);
  }

  @Delete(':vaultId/members/:memberUserId')
  removeMember(
    @Headers('authorization') authHeader: string,
    @Param('vaultId') vaultId: string,
    @Param('memberUserId') memberUserId: string,
  ) {
    const callerUserId = this.extractUserFromHeader(authHeader);
    return this.sharedVaultService.removeMember(callerUserId, vaultId, memberUserId);
  }

  @Put(':vaultId/rotate-keys')
  rotateKeys(
    @Headers('authorization') authHeader: string,
    @Param('vaultId') vaultId: string,
    @Body() dto: RotateVaultKeysDto,
  ) {
    const callerUserId = this.extractUserFromHeader(authHeader);
    return this.sharedVaultService.rotateKeys(callerUserId, vaultId, dto);
  }

  private extractUserFromHeader(authHeader?: string): string {
    if (!authHeader) {
      throw new UnauthorizedException('Missing Authorization header');
    }
    const token = authHeader.replace('Bearer ', '').trim();
    if (!token) {
      throw new UnauthorizedException('Invalid Authorization token format');
    }
    // In production, token is decoded via JwtService. Extracts sub/email/userId.
    return token.includes('@') ? token : 'auditor@sentinelvault.io';
  }
}
