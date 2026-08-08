import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import Redis from 'ioredis';
const RedisMock = require('ioredis-mock');

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private client!: Redis;
  private readonly logger = new Logger(RedisService.name);

  constructor() {
    this.initClient();
  }

  private initClient() {
    if (this.client) return;
    const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';

    if (process.env.NODE_ENV === 'test' && !process.env.USE_REAL_REDIS) {
      this.logger.log('Initializing RedisService with ioredis-mock (Test environment)');
      this.client = new RedisMock() as unknown as Redis;
    } else {
      this.logger.log(`Connecting to Redis at ${redisUrl}`);
      this.client = new Redis(redisUrl, {
        maxRetriesPerRequest: 3,
        enableOfflineQueue: true,
        lazyConnect: false,
      });

      this.client.on('error', (err) => {
        this.logger.warn(`Redis connection error: ${err.message}`);
      });
    }
  }

  onModuleInit() {
    this.initClient();
  }

  async onModuleDestroy() {
    if (this.client) {
      await this.client.quit().catch(() => {});
    }
  }

  /**
   * Get a key's value.
   */
  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  /**
   * Set a key with optional TTL (in seconds).
   */
  async set(key: string, value: string, mode?: 'EX', ttlSeconds?: number): Promise<'OK' | null> {
    if (mode === 'EX' && ttlSeconds !== undefined) {
      return this.client.set(key, value, 'EX', ttlSeconds);
    }
    return this.client.set(key, value);
  }

  /**
   * Atomically get and delete a key (GETDEL).
   * Ensures single-pass consumption for one-time challenge validation.
   */
  async getdel(key: string): Promise<string | null> {
    try {
      if (typeof this.client.getdel === 'function') {
        return await this.client.getdel(key);
      }
    } catch (_) {
      // Fallback to Lua script if GETDEL is not supported on target environment / mock
    }

    // Atomic Lua script fallback: GET key then DEL key in single script execution
    const luaScript = `
      local val = redis.call('GET', KEYS[1])
      if val then
        redis.call('DEL', KEYS[1])
      end
      return val
    `;
    return (await this.client.eval(luaScript, 1, key)) as string | null;
  }

  /**
   * Deletes a key manually if needed.
   */
  async del(key: string): Promise<number> {
    return this.client.del(key);
  }

  /**
   * Flushes all keys (used for test cleanup).
   */
  async flushall(): Promise<'OK'> {
    return this.client.flushall();
  }
}
