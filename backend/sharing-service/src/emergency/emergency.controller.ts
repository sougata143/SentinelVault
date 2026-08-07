import { Controller, Post, Get, Body, Param, Query, HttpCode, HttpStatus, UseGuards, Request } from '@nestjs/common';
import { EmergencyService } from './emergency.service';

@Controller('emergency')
export class EmergencyController {
  constructor(private readonly emergencyService: EmergencyService) {}

  @Post('contacts')
  @HttpCode(HttpStatus.CREATED)
  async addContact(
    @Body() body: { ownerUserId: string; contactEmail: string; contactUserId: string; waitingPeriodHours?: number; wrappedVaultKey?: string },
  ) {
    const contact = await this.emergencyService.addContact(
      body.ownerUserId,
      body.contactEmail,
      body.contactUserId,
      body.waitingPeriodHours ?? 72,
      body.wrappedVaultKey,
    );
    return { success: true, contact };
  }

  @Get('contacts/owner')
  async getOwnerContacts(@Query('ownerUserId') ownerUserId: string) {
    const contacts = await this.emergencyService.getContactsForOwner(ownerUserId);
    return { success: true, contacts };
  }

  @Get('contacts/designated')
  async getDesignatedContacts(@Query('contactUserId') contactUserId: string) {
    const contacts = await this.emergencyService.getContactsForContactUser(contactUserId);
    return { success: true, contacts };
  }

  @Post('contacts/:id/revoke')
  @HttpCode(HttpStatus.OK)
  async revokeContact(@Param('id') id: string, @Body() body: { ownerUserId: string }) {
    await this.emergencyService.revokeContact(body.ownerUserId, id);
    return { success: true };
  }

  @Post('requests')
  @HttpCode(HttpStatus.CREATED)
  async requestAccess(@Body() body: { contactUserId: string; contactId: string }) {
    const request = await this.emergencyService.requestAccess(body.contactUserId, body.contactId);
    return { success: true, request };
  }

  @Post('requests/:id/deny')
  @HttpCode(HttpStatus.OK)
  async denyRequest(@Param('id') id: string, @Body() body: { ownerUserId: string }) {
    const request = await this.emergencyService.denyRequest(body.ownerUserId, id);
    return { success: true, request };
  }

  @Get('requests/pending')
  async getPendingRequests(@Query('ownerUserId') ownerUserId: string) {
    const requests = await this.emergencyService.getPendingRequestsForOwner(ownerUserId);
    return { success: true, requests };
  }

  @Get('requests/:id')
  async getRequestStatus(@Param('id') id: string, @Query('userId') userId: string) {
    const result = await this.emergencyService.getRequestStatus(userId, id);
    return { success: true, ...result };
  }
}
