import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;

import 'native_crypto_bridge.dart';

// --- FFI Function Types ---

typedef _DeriveMasterKeyC = Int32 Function(
  Pointer<Uint8> passwordPtr,
  IntPtr passwordLen,
  Pointer<Uint8> saltPtr,
  IntPtr saltLen,
  Pointer<Uint8> outputPtr,
);
typedef _DeriveMasterKeyDart = int Function(
  Pointer<Uint8> passwordPtr,
  int passwordLen,
  Pointer<Uint8> saltPtr,
  int saltLen,
  Pointer<Uint8> outputPtr,
);

typedef _EncryptDecryptAesGcmC = Int32 Function(
  Pointer<Uint8> keyPtr,
  IntPtr keyLen,
  Pointer<Uint8> noncePtr,
  IntPtr nonceLen,
  Pointer<Uint8> dataPtr,
  IntPtr dataLen,
  Pointer<Uint8> outputPtr,
);
typedef _EncryptDecryptAesGcmDart = int Function(
  Pointer<Uint8> keyPtr,
  int keyLen,
  Pointer<Uint8> noncePtr,
  int nonceLen,
  Pointer<Uint8> dataPtr,
  int dataLen,
  Pointer<Uint8> outputPtr,
);

typedef _SrpCalculateXC = Int32 Function(
  Pointer<Uint8> usernamePtr,
  IntPtr usernameLen,
  Pointer<Uint8> masterKeyPtr,
  IntPtr masterKeyLen,
  Pointer<Uint8> saltPtr,
  IntPtr saltLen,
  Pointer<Uint8> outputPtr,
);
typedef _SrpCalculateXDart = int Function(
  Pointer<Uint8> usernamePtr,
  int usernameLen,
  Pointer<Uint8> masterKeyPtr,
  int masterKeyLen,
  Pointer<Uint8> saltPtr,
  int saltLen,
  Pointer<Uint8> outputPtr,
);

typedef _SrpGenerateClientEphemeralC = Int32 Function(
  Pointer<Uint8> aBytesPtr,
  IntPtr aBytesLen,
  Pointer<Uint8> secretOutputPtr,
  Pointer<Uint8> publicOutputPtr,
);
typedef _SrpGenerateClientEphemeralDart = int Function(
  Pointer<Uint8> aBytesPtr,
  int aBytesLen,
  Pointer<Uint8> secretOutputPtr,
  Pointer<Uint8> publicOutputPtr,
);

typedef _SrpCalculateClientSessionC = Int32 Function(
  Pointer<Uint8> usernamePtr,
  IntPtr usernameLen,
  Pointer<Uint8> saltPtr,
  IntPtr saltLen,
  Pointer<Uint8> aPtr,
  Pointer<Uint8> aPubPtr,
  Pointer<Uint8> bPubPtr,
  Pointer<Uint8> masterKeyPtr,
  IntPtr masterKeyLen,
  Pointer<Uint8> sessionKeyOut,
  Pointer<Uint8> clientEvidenceOut,
  Pointer<Uint8> serverEvidenceOut,
);
typedef _SrpCalculateClientSessionDart = int Function(
  Pointer<Uint8> usernamePtr,
  int usernameLen,
  Pointer<Uint8> saltPtr,
  int saltLen,
  Pointer<Uint8> aPtr,
  Pointer<Uint8> aPubPtr,
  Pointer<Uint8> bPubPtr,
  Pointer<Uint8> masterKeyPtr,
  int masterKeyLen,
  Pointer<Uint8> sessionKeyOut,
  Pointer<Uint8> clientEvidenceOut,
  Pointer<Uint8> serverEvidenceOut,
);

typedef _ShamirSplitC = Int32 Function(
  Pointer<Uint8> secretPtr,
  IntPtr secretLen,
  Uint8 m,
  Uint8 n,
  Pointer<Uint8> outputPtr,
  IntPtr outputCapacity,
  Pointer<IntPtr> writtenPtr,
);
typedef _ShamirSplitDart = int Function(
  Pointer<Uint8> secretPtr,
  int secretLen,
  int m,
  int n,
  Pointer<Uint8> outputPtr,
  int outputCapacity,
  Pointer<IntPtr> writtenPtr,
);

typedef _ShamirCombineC = Int32 Function(
  Pointer<Uint8> sharesPtr,
  IntPtr sharesTotalLen,
  Pointer<Uint8> outputPtr,
  IntPtr outputCapacity,
  Pointer<IntPtr> writtenPtr,
);
typedef _ShamirCombineDart = int Function(
  Pointer<Uint8> sharesPtr,
  int sharesTotalLen,
  Pointer<Uint8> outputPtr,
  int outputCapacity,
  Pointer<IntPtr> writtenPtr,
);

// --- Library Loader ---

DynamicLibrary _loadLibrary() {
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      final testPath = p.join(Directory.current.path, '..', 'native', 'crypto_core', 'target', 'release', 'libcrypto_core.dylib');
      if (FileSystemEntity.typeSync(testPath) != FileSystemEntityType.notFound) {
        return DynamicLibrary.open(testPath);
      }
      final testPathDebug = p.join(Directory.current.path, '..', 'native', 'crypto_core', 'target', 'debug', 'libcrypto_core.dylib');
      if (FileSystemEntity.typeSync(testPathDebug) != FileSystemEntityType.notFound) {
        return DynamicLibrary.open(testPathDebug);
      }
    } catch (_) {}
    
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    return DynamicLibrary.open('libcrypto_core.dylib');
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('libcrypto_core.so');
  } else if (Platform.isLinux) {
    try {
      final testPath = p.join(Directory.current.path, '..', 'native', 'crypto_core', 'target', 'release', 'libcrypto_core.so');
      if (FileSystemEntity.typeSync(testPath) != FileSystemEntityType.notFound) {
        return DynamicLibrary.open(testPath);
      }
    } catch (_) {}
    return DynamicLibrary.open('libcrypto_core.so');
  } else if (Platform.isWindows) {
    try {
      final testPath = p.join(Directory.current.path, '..', 'native', 'crypto_core', 'target', 'release', 'crypto_core.dll');
      if (FileSystemEntity.typeSync(testPath) != FileSystemEntityType.notFound) {
        return DynamicLibrary.open(testPath);
      }
    } catch (_) {}
    return DynamicLibrary.open('crypto_core.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

// --- Implementation ---

class NativeCryptoBridgeImpl implements NativeCryptoBridge {
  late final DynamicLibrary _lib;
  late final _DeriveMasterKeyDart _deriveMasterKeyFn;
  late final _EncryptDecryptAesGcmDart _encryptAesGcmFn;
  late final _EncryptDecryptAesGcmDart _decryptAesGcmFn;
  late final _SrpCalculateXDart _srpCalculateXFn;
  late final _SrpCalculateXDart _srpCalculateVerifierFn;
  late final _SrpGenerateClientEphemeralDart _srpGenerateClientEphemeralFn;
  late final _SrpCalculateClientSessionDart _srpCalculateClientSessionFn;
  late final _ShamirSplitDart _shamirSplitFn;
  late final _ShamirCombineDart _shamirCombineFn;

  NativeCryptoBridgeImpl() {
    _lib = _loadLibrary();
    _deriveMasterKeyFn = _lib.lookupFunction<_DeriveMasterKeyC, _DeriveMasterKeyDart>('derive_master_key');
    _encryptAesGcmFn = _lib.lookupFunction<_EncryptDecryptAesGcmC, _EncryptDecryptAesGcmDart>('encrypt_aes_gcm');
    _decryptAesGcmFn = _lib.lookupFunction<_EncryptDecryptAesGcmC, _EncryptDecryptAesGcmDart>('decrypt_aes_gcm');
    _srpCalculateXFn = _lib.lookupFunction<_SrpCalculateXC, _SrpCalculateXDart>('srp_calculate_x');
    _srpCalculateVerifierFn = _lib.lookupFunction<_SrpCalculateXC, _SrpCalculateXDart>('srp_calculate_verifier');
    _srpGenerateClientEphemeralFn = _lib.lookupFunction<_SrpGenerateClientEphemeralC, _SrpGenerateClientEphemeralDart>('srp_generate_client_ephemeral');
    _srpCalculateClientSessionFn = _lib.lookupFunction<_SrpCalculateClientSessionC, _SrpCalculateClientSessionDart>('srp_calculate_client_session');
    _shamirSplitFn = _lib.lookupFunction<_ShamirSplitC, _ShamirSplitDart>('shamir_split');
    _shamirCombineFn = _lib.lookupFunction<_ShamirCombineC, _ShamirCombineDart>('shamir_combine');
  }

  @override
  Future<Uint8List> deriveMasterKey({
    required List<int> password,
    required List<int> salt,
  }) async {
    return using((Arena arena) {
      final passwordPtr = password.toPointer(arena);
      final saltPtr = salt.toPointer(arena);
      final outputPtr = arena<Uint8>(32);

      final res = _deriveMasterKeyFn(
        passwordPtr,
        password.length,
        saltPtr,
        salt.length,
        outputPtr,
      );

      if (res != 0) {
        throw Exception('Native master key derivation failed: $res');
      }

      final outBytes = outputPtr.asTypedList(32);
      return Uint8List.fromList(outBytes);
    });
    // The using scope handles the allocation cleanup.
    // However, since dart Futures are asynchronous, we return directly synchronously.
    // Wait! Let's make sure the returned Uint8List is fully copied before the Arena is released!
    // Yes, Uint8List.fromList creates a deep copy of the bytes, so it is safe to release the pointer immediately.
  }

  @override
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) async {
    return using((Arena arena) {
      final keyPtr = key.toPointer(arena);
      final noncePtr = nonce.toPointer(arena);
      final plaintextPtr = plaintext.toPointer(arena);
      
      final outLen = plaintext.length + 16;
      final outputPtr = arena<Uint8>(outLen);

      final res = _encryptAesGcmFn(
        keyPtr,
        key.length,
        noncePtr,
        nonce.length,
        plaintextPtr,
        plaintext.length,
        outputPtr,
      );

      if (res != 0) {
        throw Exception('Native AES-256-GCM encryption failed: $res');
      }

      final outBytes = outputPtr.asTypedList(outLen);
      return Uint8List.fromList(outBytes);
    });
  }

  @override
  Future<Uint8List> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  }) async {
    return using((Arena arena) {
      final keyPtr = key.toPointer(arena);
      final noncePtr = nonce.toPointer(arena);
      final ciphertextPtr = ciphertextAndMac.toPointer(arena);
      
      final outLen = ciphertextAndMac.length - 16;
      final outputPtr = arena<Uint8>(outLen);

      final res = _decryptAesGcmFn(
        keyPtr,
        key.length,
        noncePtr,
        nonce.length,
        ciphertextPtr,
        ciphertextAndMac.length,
        outputPtr,
      );

      if (res != 0) {
        throw SecretBoxAuthenticationError();
      }

      final outBytes = outputPtr.asTypedList(outLen);
      return Uint8List.fromList(outBytes);
    });
  }

  @override
  Future<Uint8List> srpCalculateX({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) async {
    return using((Arena arena) {
      final usernamePtr = username.toPointer(arena);
      final masterKeyPtr = masterKey.toPointer(arena);
      final saltPtr = salt.toPointer(arena);
      final outputPtr = arena<Uint8>(32);

      final res = _srpCalculateXFn(
        usernamePtr,
        utf8.encode(username).length,
        masterKeyPtr,
        masterKey.length,
        saltPtr,
        salt.length,
        outputPtr,
      );

      if (res != 0) {
        throw Exception('Native SRP calculate_x failed: $res');
      }

      final outBytes = outputPtr.asTypedList(32);
      return Uint8List.fromList(outBytes);
    });
  }

  @override
  Future<Uint8List> srpCalculateVerifier({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) async {
    return using((Arena arena) {
      final usernamePtr = username.toPointer(arena);
      final masterKeyPtr = masterKey.toPointer(arena);
      final saltPtr = salt.toPointer(arena);
      final outputPtr = arena<Uint8>(256);

      final res = _srpCalculateVerifierFn(
        usernamePtr,
        utf8.encode(username).length,
        masterKeyPtr,
        masterKey.length,
        saltPtr,
        salt.length,
        outputPtr,
      );

      if (res != 0) {
        throw Exception('Native SRP calculate_verifier failed: $res');
      }

      final outBytes = outputPtr.asTypedList(256);
      return Uint8List.fromList(outBytes);
    });
  }

  @override
  List<Uint8List> srpGenerateClientEphemeral({
    required List<int> secureRandomBytes,
  }) {
    return using((Arena arena) {
      final aBytesPtr = secureRandomBytes.toPointer(arena);
      final secretOutputPtr = arena<Uint8>(256);
      final publicOutputPtr = arena<Uint8>(256);

      final res = _srpGenerateClientEphemeralFn(
        aBytesPtr,
        secureRandomBytes.length,
        secretOutputPtr,
        publicOutputPtr,
      );

      if (res != 0) {
        throw Exception('Native SRP generate_client_ephemeral failed: $res');
      }

      final secretBytes = secretOutputPtr.asTypedList(256);
      final publicBytes = publicOutputPtr.asTypedList(256);
      
      return [
        Uint8List.fromList(secretBytes),
        Uint8List.fromList(publicBytes),
      ];
    });
  }

  @override
  Future<List<Uint8List>> srpCalculateClientSession({
    required String username,
    required List<int> salt,
    required List<int> a,
    required List<int> A,
    required List<int> B,
    required List<int> masterKey,
  }) async {
    return using((Arena arena) {
      final usernamePtr = username.toPointer(arena);
      final saltPtr = salt.toPointer(arena);
      
      final aPtr = a.toPointer(arena);
      final aPubPtr = A.toPointer(arena);
      final bPubPtr = B.toPointer(arena);
      final masterKeyPtr = masterKey.toPointer(arena);
      
      final sessionKeyOut = arena<Uint8>(32);
      final clientEvidenceOut = arena<Uint8>(32);
      final serverEvidenceOut = arena<Uint8>(32);

      final res = _srpCalculateClientSessionFn(
        usernamePtr,
        utf8.encode(username).length,
        saltPtr,
        salt.length,
        aPtr,
        aPubPtr,
        bPubPtr,
        masterKeyPtr,
        masterKey.length,
        sessionKeyOut,
        clientEvidenceOut,
        serverEvidenceOut,
      );

      if (res != 0) {
        throw Exception('Native SRP calculate_client_session failed: $res');
      }

      final sessionKey = sessionKeyOut.asTypedList(32);
      final clientEvidence = clientEvidenceOut.asTypedList(32);
      final serverEvidence = serverEvidenceOut.asTypedList(32);

      return [
        Uint8List.fromList(sessionKey),
        Uint8List.fromList(clientEvidence),
        Uint8List.fromList(serverEvidence),
      ];
    });
  }

  @override
  List<Uint8List> shamirSplit({
    required Uint8List secret,
    required int m,
    required int n,
  }) {
    // Capacity: n shares × (4 byte length prefix + secret.length + 1 byte x-coord)
    final outputCapacity = n * (4 + secret.length + 2);
    return using((Arena arena) {
      final secretPtr = arena<Uint8>(secret.length);
      secretPtr.asTypedList(secret.length).setAll(0, secret);

      final outputPtr = arena<Uint8>(outputCapacity);
      final writtenPtr = arena<IntPtr>(1);
      writtenPtr.value = 0;

      final res = _shamirSplitFn(
        secretPtr,
        secret.length,
        m,
        n,
        outputPtr,
        outputCapacity,
        writtenPtr,
      );

      if (res != 0) {
        throw ArgumentError('Native shamir_split failed: $res');
      }

      final totalWritten = writtenPtr.value;
      final flatBuf = outputPtr.asTypedList(totalWritten);

      // Parse length-prefixed share blobs back into Dart list
      final shares = <Uint8List>[];
      var cursor = 0;
      while (cursor + 4 <= totalWritten) {
        final shareLen = flatBuf[cursor] |
            (flatBuf[cursor + 1] << 8) |
            (flatBuf[cursor + 2] << 16) |
            (flatBuf[cursor + 3] << 24);
        cursor += 4;
        if (cursor + shareLen > totalWritten) break;
        shares.add(Uint8List.fromList(flatBuf.sublist(cursor, cursor + shareLen)));
        cursor += shareLen;
      }

      if (shares.length != n) {
        throw StateError('shamir_split returned ${shares.length} shares, expected $n');
      }
      return shares;
    });
  }

  @override
  Uint8List shamirCombine({required List<Uint8List> shares}) {
    // Re-assemble length-prefixed wire format for native call
    var flatLen = 0;
    for (final s in shares) {
      flatLen += 4 + s.length;
    }

    return using((Arena arena) {
      final sharesPtr = arena<Uint8>(flatLen);
      final flatView = sharesPtr.asTypedList(flatLen);
      var cursor = 0;
      for (final s in shares) {
        final len = s.length;
        flatView[cursor] = len & 0xFF;
        flatView[cursor + 1] = (len >> 8) & 0xFF;
        flatView[cursor + 2] = (len >> 16) & 0xFF;
        flatView[cursor + 3] = (len >> 24) & 0xFF;
        cursor += 4;
        flatView.setRange(cursor, cursor + len, s);
        cursor += len;
      }

      // Output buffer: up to 256 bytes (generous for any reasonable secret)
      const maxSecretLen = 256;
      final outputPtr = arena<Uint8>(maxSecretLen);
      final writtenPtr = arena<IntPtr>(1);
      writtenPtr.value = 0;

      final res = _shamirCombineFn(
        sharesPtr,
        flatLen,
        outputPtr,
        maxSecretLen,
        writtenPtr,
      );

      if (res != 0) {
        throw ArgumentError('Native shamir_combine failed: $res — shares may be invalid or insufficient');
      }

      final written = writtenPtr.value;
      return Uint8List.fromList(outputPtr.asTypedList(written));
    });
  }
}

// --- Pointer Helpers ---

extension _ListToPtr on List<int> {
  Pointer<Uint8> toPointer(Allocator allocator) {
    final ptr = allocator<Uint8>(length);
    final view = ptr.asTypedList(length);
    view.setAll(0, this);
    return ptr;
  }
}

extension _StringToPtr on String {
  Pointer<Uint8> toPointer(Allocator allocator) {
    final bytes = utf8.encode(this);
    final ptr = allocator<Uint8>(bytes.length);
    final view = ptr.asTypedList(bytes.length);
    view.setAll(0, bytes);
    return ptr;
  }
}

extension _NativeCryptoBridgeIoShamir on NativeCryptoBridgeImpl {
  // Intentionally empty — Shamir methods are inline on the class.
}
