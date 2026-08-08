import {
  Controller, Get, Post, Body, Param, HttpCode, HttpStatus, UseGuards,
} from '@nestjs/common';
import { ShareLinkService } from './share-link.service';
import { CreateShareLinkDto } from './share-link.dto';

// Minimal inline decorator/guard matching sharing-service common patterns
import { CurrentUser } from '../common/current-user.decorator';
import { JwtAuthGuard } from '../common/jwt-auth.guard';

@Controller('share-links')
export class ShareLinkController {
  constructor(private readonly shareLinkService: ShareLinkService) {}

  /**
   * Public unauthenticated endpoint for recipients.
   * Atomically checks expiry, consumption, revocation, and returns ciphertext.
   */
  @Get(':shareId')
  getPublicShareLink(@Param('shareId') shareId: string) {
    return this.shareLinkService.getAndConsumeShareLink(shareId);
  }

  /**
   * Authenticated endpoint for vault owners to create a new share link.
   */
  @Post()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.CREATED)
  createShareLink(
    @CurrentUser() userId: string,
    @Body() dto: CreateShareLinkDto,
  ) {
    return this.shareLinkService.createShareLink(userId, dto);
  }

  /**
   * Authenticated endpoint for vault owners to list their created share links.
   */
  @Get('my-links/all')
  @UseGuards(JwtAuthGuard)
  getOwnerShareLinks(@CurrentUser() userId: string) {
    return this.shareLinkService.getOwnerShareLinks(userId);
  }

  /**
   * Authenticated endpoint for vault owners to manually revoke a share link.
   */
  @Post(':shareId/revoke')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  revokeShareLink(
    @CurrentUser() userId: string,
    @Param('shareId') shareId: string,
  ) {
    return this.shareLinkService.revokeShareLink(userId, shareId);
  }
}
