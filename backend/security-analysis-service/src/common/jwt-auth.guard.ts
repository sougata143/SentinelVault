import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

/** Custom Request interface to avoid direct dependency on Express type declarations. */
export interface AuthenticatedRequest {
  headers: Record<string, string | string[] | undefined>;
  user?: { id: string; username: string };
  [key: string]: any;
}

/**
 * JwtAuthGuard — verifies the `Authorization: Bearer <token>` header using
 * the shared JWT_SECRET that auth-service used to sign the token.
 *
 * Rejects with 401 UNAUTHORIZED if:
 *   - The `Authorization` header is absent or malformed
 *   - The token signature is invalid
 *   - The token has expired
 *   - The token payload lacks a `sub` claim
 *
 * On success, attaches `req.user = { id: payload.sub, username: payload.username }`
 * so downstream handlers never touch the raw token or header again.
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwtService: JwtService) {}

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authHeader = req.headers['authorization'];

    // In HTTP headers, keys are always lowercase
    const headerStr = Array.isArray(authHeader) ? authHeader[0] : authHeader;

    if (!headerStr || !headerStr.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or malformed Authorization header');
    }

    const token = headerStr.slice(7); // strip "Bearer "

    let payload: { sub: string; username: string };
    try {
      payload = this.jwtService.verify<{ sub: string; username: string }>(token, {
        secret: process.env.JWT_SECRET,
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }

    if (!payload.sub) {
      throw new UnauthorizedException('Token payload missing sub claim');
    }

    req.user = { id: payload.sub, username: payload.username };
    return true;
  }
}
