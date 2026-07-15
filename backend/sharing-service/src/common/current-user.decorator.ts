import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthenticatedRequest } from './jwt-auth.guard';

/**
 * @CurrentUser() — extracts the verified user id from `req.user.id`.
 *
 * MUST only be used on endpoints protected by JwtAuthGuard, which is
 * responsible for populating `req.user` from the verified JWT payload.
 * The id is server-verified — it cannot be spoofed by the client.
 */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): string => {
    const req = ctx.switchToHttp().getRequest<AuthenticatedRequest>();
    return req.user!.id;
  },
);
