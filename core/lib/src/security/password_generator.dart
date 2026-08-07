import 'dart:math';

/// Utility for generating cryptographically secure, high-entropy passwords.
class PasswordGenerator {
  static const String uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
  static const String numberChars = '0123456789';
  static const String symbolChars = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

  /// Generates a random password of specified [length] matching character rules.
  /// Uses [Random.secure] by default for cryptographic randomness.
  static String generate({
    int length = 20,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
    Random? random,
  }) {
    if (length < 4) length = 4;
    if (length > 128) length = 128;

    final rng = random ?? Random.secure();
    final pools = <String>[];

    if (includeUppercase) pools.add(uppercaseChars);
    if (includeLowercase) pools.add(lowercaseChars);
    if (includeNumbers) pools.add(numberChars);
    if (includeSymbols) pools.add(symbolChars);

    if (pools.isEmpty) {
      pools.add(lowercaseChars);
    }

    final chars = <String>[];

    // Ensure at least one character from each enabled pool is included
    for (final pool in pools) {
      chars.add(pool[rng.nextInt(pool.length)]);
    }

    // Fill the remaining length from the combined character pool
    final combinedPool = pools.join('');
    while (chars.length < length) {
      chars.add(combinedPool[rng.nextInt(combinedPool.length)]);
    }

    // Shuffle the characters securely using Fisher-Yates
    for (var i = chars.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final temp = chars[i];
      chars[i] = chars[j];
      chars[j] = temp;
    }

    return chars.join('');
  }
}
