import { Test, TestingModule } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import { AppModule } from '../src/app.module';
import { UserRepository } from '../src/auth/user.repository';
import { User } from '../src/auth/entities/user.entity';
import { WebauthnCredential } from '../src/auth/entities/webauthn-credential.entity';

import * as crypto from 'crypto';

describe('UserRepository Database Persistence', () => {
  let appModule: TestingModule;
  let repository: UserRepository;
  let dataSource: DataSource;

  beforeEach(async () => {
    // 1. Create a module and get the repository and dataSource
    appModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    repository = appModule.get<UserRepository>(UserRepository);
    dataSource = appModule.get<DataSource>(DataSource);
  }, 30000);

  afterEach(async () => {
    if (appModule) {
      await appModule.close();
    }
  }, 30000);

  it('should persist a user across UserRepository instance restarts', async () => {
    const testUsername = 'persist_user_' + crypto.randomBytes(6).toString('hex');
    const testRecord = {
      username: testUsername,
      salt: 'salt_hex_123',
      verifier: 'verifier_hex_456',
      failedAttempts: 0,
      lockoutUntil: null,
      totpEnabled: false,
      webauthnEnabled: false,
    };

    // 1. Save user to repository
    const saved = await repository.save(testRecord);
    expect(saved.id).toBeDefined();

    // 2. Instantiate a fresh UserRepository object connected to the same test database
    const userRepo = dataSource.getRepository(User);
    const webauthnRepo = dataSource.getRepository(WebauthnCredential);
    const newRepository = new UserRepository(userRepo, webauthnRepo);

    // 3. Find the user again on the new repository instance
    const found = await newRepository.findByUsername(testUsername);
    expect(found).not.toBeNull();
    expect(found!.id).toBe(saved.id);
    expect(found!.username).toBe(testUsername);
    expect(found!.salt).toBe('salt_hex_123');
    expect(found!.verifier).toBe('verifier_hex_456');

    // Clean up
    await newRepository.clear();
  });
});
