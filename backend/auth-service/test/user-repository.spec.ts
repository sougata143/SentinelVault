import { Test, TestingModule } from '@nestjs/testing';
import { AppModule } from '../src/app.module';
import { UserRepository } from '../src/auth/user.repository';

describe('UserRepository Database Persistence', () => {
  let appModule: TestingModule;
  let repository: UserRepository;

  beforeEach(async () => {
    // 1. Create a module and get the repository
    appModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    repository = appModule.get<UserRepository>(UserRepository);
    await repository.clear();
  });

  afterEach(async () => {
    if (appModule) {
      await appModule.close();
    }
  });

  it('should persist a user across UserRepository instance restarts', async () => {
    const testUsername = 'persist_test_user';
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

    // 2. Simulate process restart by closing the module and creating a new one
    await appModule.close();

    const newAppModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    const newRepository = newAppModule.get<UserRepository>(UserRepository);

    // 3. Find the user again on the new repository instance
    const found = await newRepository.findByUsername(testUsername);
    expect(found).not.toBeNull();
    expect(found!.id).toBe(saved.id);
    expect(found!.username).toBe(testUsername);
    expect(found!.salt).toBe('salt_hex_123');
    expect(found!.verifier).toBe('verifier_hex_456');

    // Clean up
    await newRepository.clear();
    await newAppModule.close();
  });
});
