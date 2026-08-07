import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { RedisService } from '../auth/redis.service';

export interface AuthenticatedRequest {
  headers: Record<string, string | string[] | undefined>;
  user?: { id: string; username: string; jti?: string };
  [key: string]: any;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly redisService: RedisService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authHeader = req.headers['authorization'];

    const headerStr = Array.isArray(authHeader) ? authHeader[0] : authHeader;

    if (!headerStr || !headerStr.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or malformed Authorization header');
    }

    const token = headerStr.slice(7);

    let payload: { sub: string; username: string; jti?: string };
    try {
      payload = this.jwtService.verify<{ sub: string; username: string; jti?: string }>(token, {
        secret: process.env.JWT_SECRET || 'sentinelvault_jwt_secret_key_change_in_production',
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }

    if (!payload.sub) {
      throw new UnauthorizedException('Token payload missing sub claim');
    }

    if (payload.jti) {
      const isRevoked = await this.redisService.get(`revoked:jti:${payload.jti}`);
      if (isRevoked) {
        throw new UnauthorizedException('Session has been revoked');
      }
    }

    req.user = { id: payload.sub, username: payload.username, jti: payload.jti };
    return true;
  }
}
