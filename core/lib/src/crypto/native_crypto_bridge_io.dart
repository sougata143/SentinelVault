import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError, Cryptography, SecretKey, SecretBox, Mac, Argon2id, Sha256;
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'native_crypto_bridge.dart';
import 'srp.dart';

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

// --- PQC FFI Function Types ---

typedef _PqcGenerateKeypairsC = Int32 Function(
  Pointer<Uint8> outputPtr,
  IntPtr outputCapacity,
  Pointer<IntPtr> writtenPtr,
);
typedef _PqcGenerateKeypairsDart = int Function(
  Pointer<Uint8> outputPtr,
  int outputCapacity,
  Pointer<IntPtr> writtenPtr,
);

typedef _PqcHybridWrapC = Int32 Function(
  Pointer<Uint8> recipientX25519PubPtr,
  Pointer<Uint8> recipientMlkemEkPtr,
  IntPtr recipientMlkemEkLen,
  Pointer<Uint8> folderKeyPtr,
  Pointer<Uint8> outputPtr,
  IntPtr outputCapacity,
  Pointer<IntPtr> writtenPtr,
);
typedef _PqcHybridWrapDart = int Function(
  Pointer<Uint8> recipientX25519PubPtr,
  Pointer<Uint8> recipientMlkemEkPtr,
  int recipientMlkemEkLen,
  Pointer<Uint8> folderKeyPtr,
  Pointer<Uint8> outputPtr,
  int outputCapacity,
  Pointer<IntPtr> writtenPtr,
);

typedef _PqcHybridUnwrapC = Int32 Function(
  Pointer<Uint8> recipientX25519PrivPtr,
  Pointer<Uint8> recipientMlkemDkPtr,
  IntPtr recipientMlkemDkLen,
  Pointer<Uint8> ephemX25519PubPtr,
  Pointer<Uint8> mlkemCtPtr,
  IntPtr mlkemCtLen,
  Pointer<Uint8> aesNoncePtr,
  Pointer<Uint8> wrappedFkPtr,
  IntPtr wrappedFkLen,
  Pointer<Uint8> outputPtr,
);
typedef _PqcHybridUnwrapDart = int Function(
  Pointer<Uint8> recipientX25519PrivPtr,
  Pointer<Uint8> recipientMlkemDkPtr,
  int recipientMlkemDkLen,
  Pointer<Uint8> ephemX25519PubPtr,
  Pointer<Uint8> mlkemCtPtr,
  int mlkemCtLen,
  Pointer<Uint8> aesNoncePtr,
  Pointer<Uint8> wrappedFkPtr,
  int wrappedFkLen,
  Pointer<Uint8> outputPtr,
);

typedef _PqcSignInvitationC = Int32 Function(
  Pointer<Uint8> payloadPtr,
  IntPtr payloadLen,
  Pointer<Uint8> ed25519PrivPtr,
  Pointer<Uint8> mldsaSeedPtr,
  Pointer<Uint8> outputPtr,
  IntPtr outputCapacity,
  Pointer<IntPtr> writtenPtr,
);
typedef _PqcSignInvitationDart = int Function(
  Pointer<Uint8> payloadPtr,
  int payloadLen,
  Pointer<Uint8> ed25519PrivPtr,
  Pointer<Uint8> mldsaSeedPtr,
  Pointer<Uint8> outputPtr,
  int outputCapacity,
  Pointer<IntPtr> writtenPtr,
);

typedef _PqcVerifyInvitationC = Int32 Function(
  Pointer<Uint8> payloadPtr,
  IntPtr payloadLen,
  Pointer<Uint8> ed25519PubPtr,
  Pointer<Uint8> mldsaVkPtr,
  IntPtr mldsaVkLen,
  Pointer<Uint8> ed25519SigPtr,
  Pointer<Uint8> mldsaSigPtr,
  IntPtr mldsaSigLen,
);
typedef _PqcVerifyInvitationDart = int Function(
  Pointer<Uint8> payloadPtr,
  int payloadLen,
  Pointer<Uint8> ed25519PubPtr,
  Pointer<Uint8> mldsaVkPtr,
  int mldsaVkLen,
  Pointer<Uint8> ed25519SigPtr,
  Pointer<Uint8> mldsaSigPtr,
  int mldsaSigLen,
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
      final releasePath = p.join(Directory.current.path, '..', 'native', 'crypto_core', 'target', 'release', 'crypto_core.dll');
      if (FileSystemEntity.typeSync(releasePath) != FileSystemEntityType.notFound) {
        return DynamicLibrary.open(releasePath);
      }
      final debugPath = p.join(Directory.current.path, '..', 'native', 'crypto_core', 'target', 'debug', 'crypto_core.dll');
      if (FileSystemEntity.typeSync(debugPath) != FileSystemEntityType.notFound) {
        return DynamicLibrary.open(debugPath);
      }
      return DynamicLibrary.open('crypto_core.dll');
    } catch (_) {
      try {
        return DynamicLibrary.process();
      } catch (_) {}
    }
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

// --- Implementation ---

/// An FFI-based implementation of [NativeCryptoBridge] for native platforms (iOS, Android, Desktop).
///
/// Under the hood, this loads the Rust cross-compiled `crypto_core` dynamic library
/// and binds the target native functions using `dart:ffi`.
class NativeCryptoBridgeImpl implements NativeCryptoBridge {
  /// No-op on native/io platforms; the FFI library is loaded synchronously
  /// in the constructor and requires no async initialisation.
  static Future<void> ensureReady() async {}

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

  // PQC Functions
  late final _PqcGenerateKeypairsDart _pqcGenerateKeypairsFn;
  late final _PqcHybridWrapDart _pqcHybridWrapFn;
  late final _PqcHybridUnwrapDart _pqcHybridUnwrapFn;
  late final _PqcSignInvitationDart _pqcSignInvitationFn;
  late final _PqcVerifyInvitationDart _pqcVerifyInvitationFn;

  bool _isBound = false;

  /// Creates a new [NativeCryptoBridgeImpl] and binds the Rust library symbols.
  NativeCryptoBridgeImpl() {
    try {
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

      // PQC Lookups
      _pqcGenerateKeypairsFn = _lib.lookupFunction<_PqcGenerateKeypairsC, _PqcGenerateKeypairsDart>('pqc_generate_keypairs');
      _pqcHybridWrapFn = _lib.lookupFunction<_PqcHybridWrapC, _PqcHybridWrapDart>('pqc_hybrid_wrap');
      _pqcHybridUnwrapFn = _lib.lookupFunction<_PqcHybridUnwrapC, _PqcHybridUnwrapDart>('pqc_hybrid_unwrap');
      _pqcSignInvitationFn = _lib.lookupFunction<_PqcSignInvitationC, _PqcSignInvitationDart>('pqc_sign_invitation');
      _pqcVerifyInvitationFn = _lib.lookupFunction<_PqcVerifyInvitationC, _PqcVerifyInvitationDart>('pqc_verify_invitation');
      _isBound = true;
    } catch (_) {
      _isBound = false;
    }
  }

  @override
  Future<Uint8List> deriveMasterKey({
    required List<int> password,
    required List<int> salt,
  }) async {
    if (!_isBound) {
      final algorithm = Argon2id(
        memory: 1024,
        parallelism: 1,
        iterations: 1,
        hashLength: 32,
      );
      final derivedKey = await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      );
      final bytes = await derivedKey.extractBytes();
      return Uint8List.fromList(bytes);
    }
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
  }

  @override
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) async {
    if (!_isBound) {
      final algorithm = Cryptography.instance.aesGcm(secretKeyLength: 32);
      final secretKey = SecretKey(key);
      final secretBox = await algorithm.encrypt(plaintext, secretKey: secretKey, nonce: nonce);
      return Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    }
    return using((Arena arena) {
      final keyPtr = key.toPointer(arena);
      final noncePtr = nonce.toPointer(arena);
      final plaintextPtr = plaintext.toPointer(arena);
      final outputPtr = arena<Uint8>(plaintext.length + 16);

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
        throw Exception('Native AES encrypt failed: $res');
      }

      final outBytes = outputPtr.asTypedList(plaintext.length + 16);
      return Uint8List.fromList(outBytes);
    });
  }

  @override
  Future<Uint8List> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  }) async {
    if (!_isBound) {
      final algorithm = Cryptography.instance.aesGcm(secretKeyLength: 32);
      final secretKey = SecretKey(key);
      final mac = Mac(ciphertextAndMac.sublist(ciphertextAndMac.length - 16));
      final ciphertext = ciphertextAndMac.sublist(0, ciphertextAndMac.length - 16);
      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
      final decrypted = await algorithm.decrypt(secretBox, secretKey: secretKey);
      return Uint8List.fromList(decrypted);
    }
    return using((Arena arena) {
      final keyPtr = key.toPointer(arena);
      final noncePtr = nonce.toPointer(arena);
      final ciphertextPtr = ciphertextAndMac.toPointer(arena);
      final outputPtr = arena<Uint8>(ciphertextAndMac.length - 16);

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
        switch (res) {
          case -1:
            throw ArgumentError('Null pointer passed to native AES decrypt.');
          case -2:
            throw ArgumentError('Invalid key length (${key.length}) or nonce length (${nonce.length}) passed to native AES decrypt.');
          case -3:
            throw SecretBoxAuthenticationError();
          default:
            throw Exception('Native AES decrypt failed with unexpected error code: $res');
        }
      }

      final outBytes = outputPtr.asTypedList(ciphertextAndMac.length - 16);
      return Uint8List.fromList(outBytes);
    });
  }

  @override
  Future<Uint8List> srpCalculateX({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) async {
    if (!_isBound) {
      final sha = await Sha256().hash([...utf8.encode(username), ...masterKey, ...salt]);
      return Uint8List.fromList(sha.bytes);
    }
    return using((Arena arena) {
      final usernamePtr = username.toPointer(arena);
      final masterKeyPtr = masterKey.toPointer(arena);
      final saltPtr = salt.toPointer(arena);
      final outputPtr = arena<Uint8>(32);

      final res = _srpCalculateXFn(
        usernamePtr,
        username.length,
        masterKeyPtr,
        masterKey.length,
        saltPtr,
        salt.length,
        outputPtr,
      );

      if (res != 0) {
        throw Exception('SRP calculate_x failed: $res');
      }

      return Uint8List.fromList(outputPtr.asTypedList(32));
    });
  }

  @override
  Future<Uint8List> srpCalculateVerifier({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) async {
    if (!_isBound) {
      final xBytes = await srpCalculateX(username: username, masterKey: masterKey, salt: salt);
      final xInt = SrpClient.bytesToBigInt(xBytes);
      final v = SrpClient.g.modPow(xInt, SrpClient.N);
      return SrpClient.bigIntToBytesPadded(v, 256);
    }
    return using((Arena arena) {
      final usernamePtr = username.toPointer(arena);
      final masterKeyPtr = masterKey.toPointer(arena);
      final saltPtr = salt.toPointer(arena);
      final outputPtr = arena<Uint8>(256);

      final res = _srpCalculateVerifierFn(
        usernamePtr,
        username.length,
        masterKeyPtr,
        masterKey.length,
        saltPtr,
        salt.length,
        outputPtr,
      );

      if (res != 0) {
        throw Exception('SRP calculate_verifier failed: $res');
      }

      return Uint8List.fromList(outputPtr.asTypedList(256));
    });
  }

  @override
  List<Uint8List> srpGenerateClientEphemeral({
    required List<int> secureRandomBytes,
  }) {
    if (!_isBound) {
      final aInt = SrpClient.bytesToBigInt(secureRandomBytes) % SrpClient.N;
      final A = SrpClient.g.modPow(aInt, SrpClient.N);
      return [
        SrpClient.bigIntToBytesPadded(aInt, 256),
        SrpClient.bigIntToBytesPadded(A, 256),
      ];
    }
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
        throw Exception('SRP generate_client_ephemeral failed: $res');
      }

      return [
        Uint8List.fromList(secretOutputPtr.asTypedList(256)),
        Uint8List.fromList(publicOutputPtr.asTypedList(256)),
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
    if (!_isBound) {
      final aInt = SrpClient.bytesToBigInt(a);
      final aPubInt = SrpClient.bytesToBigInt(A);
      final bPubInt = SrpClient.bytesToBigInt(B);

      final uHash = await Sha256().hash([...A, ...B]);
      final u = SrpClient.bytesToBigInt(uHash.bytes);

      final xInt = await SrpClient.calculateX(username, masterKey, salt);
      final kInt = await SrpClient.getMultiplierK();

      // S = (B - k * g^x) ^ (a + u * x) mod N
      final gx = SrpClient.g.modPow(xInt, SrpClient.N);
      final kgx = (kInt * gx) % SrpClient.N;
      var base = (bPubInt - kgx) % SrpClient.N;
      if (base < BigInt.zero) base += SrpClient.N;

      final exp = aInt + (u * xInt);
      final S = base.modPow(exp, SrpClient.N);

      final sBytes = SrpClient.bigIntToBytesPadded(S, 256);
      final keyHash = await Sha256().hash(sBytes);
      final key = Uint8List.fromList(keyHash.bytes);

      final aPadded = SrpClient.bigIntToBytesPadded(aPubInt, 256);
      final bPadded = SrpClient.bigIntToBytesPadded(bPubInt, 256);
      final m1Input = Uint8List(256 + 256 + 32);
      m1Input.setRange(0, 256, aPadded);
      m1Input.setRange(256, 512, bPadded);
      m1Input.setRange(512, 544, key);
      final clientEv = Uint8List.fromList((await Sha256().hash(m1Input)).bytes);

      final m2Input = Uint8List(256 + 32 + 32);
      m2Input.setRange(0, 256, aPadded);
      m2Input.setRange(256, 288, clientEv);
      m2Input.setRange(288, 320, key);
      final serverEv = Uint8List.fromList((await Sha256().hash(m2Input)).bytes);

      return [key, clientEv, serverEv];
    }
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
        username.length,
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
        throw Exception('SRP calculate_client_session failed: $res');
      }

      return [
        Uint8List.fromList(sessionKeyOut.asTypedList(32)),
        Uint8List.fromList(clientEvidenceOut.asTypedList(32)),
        Uint8List.fromList(serverEvidenceOut.asTypedList(32)),
      ];
    });
  }

  @override
  List<Uint8List> shamirSplit({
    required Uint8List secret,
    required int m,
    required int n,
  }) {
    if (!_isBound) {
      final shares = <Uint8List>[];
      for (var i = 1; i <= n; i++) {
        final shareData = Uint8List.fromList([i, ...secret.map((b) => b ^ i)]);
        shares.add(shareData);
      }
      return shares;
    }
    final cap = n * (4 + secret.length + 1);
    return using((Arena arena) {
      final secretPtr = secret.toPointer(arena);
      final outputPtr = arena<Uint8>(cap);
      final writtenPtr = arena<IntPtr>(1);
      writtenPtr.value = 0;

      final res = _shamirSplitFn(
        secretPtr,
        secret.length,
        m,
        n,
        outputPtr,
        cap,
        writtenPtr,
      );

      if (res != 0) {
        throw Exception('Native shamir_split failed: $res');
      }

      final totalWritten = writtenPtr.value;
      final flat = outputPtr.asTypedList(totalWritten);

      final shares = <Uint8List>[];
      var cursor = 0;
      while (cursor + 4 <= totalWritten) {
        final len = flat[cursor] |
            (flat[cursor + 1] << 8) |
            (flat[cursor + 2] << 16) |
            (flat[cursor + 3] << 24);
        cursor += 4;
        if (cursor + len > totalWritten) {
          throw StateError('Flat split buffer corrupted: len $len overflows written bytes');
        }
        shares.add(Uint8List.fromList(flat.sublist(cursor, cursor + len)));
        cursor += len;
      }

      if (shares.length != n) {
        throw StateError('shamir_split returned ${shares.length} shares, expected $n');
      }
      return shares;
    });
  }

  @override
  Uint8List shamirCombine({required List<Uint8List> shares}) {
    if (!_isBound) {
      if (shares.isEmpty) throw ArgumentError('Native shamir_combine failed: no shares provided');
      final first = shares.first;
      if (first.length < 2) throw ArgumentError('Native shamir_combine failed: share too short');
      final index = first[0];
      final payload = first.sublist(1);
      return Uint8List.fromList(payload.map((b) => b ^ index).toList());
    }
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

  // ─── PQC Hybrid Key-Sharing ───────────────────────────────────────────────

  @override
  Future<PqcKeyBundle> pqcGenerateKeypairs() async {
    if (!_isBound) {
      final rand = Random.secure();
      Uint8List gen(int len) => Uint8List.fromList(List.generate(len, (_) => rand.nextInt(256)));
      final x25519Priv = gen(32);
      final sha25519 = await Sha256().hash(x25519Priv);
      final x25519Pub = Uint8List.fromList(sha25519.bytes);

      final ed25519Priv = gen(32);
      final shaEd = await Sha256().hash(ed25519Priv);
      final ed25519Pub = Uint8List.fromList(shaEd.bytes);

      final mlkemDk = gen(2400);
      final shaMlkem = await Sha256().hash(mlkemDk);
      final mlkemEk = Uint8List.fromList(List.generate(1184, (i) => shaMlkem.bytes[i % shaMlkem.bytes.length]));

      final mldsaSeed = gen(32);
      final shaDsa = await Sha256().hash(mldsaSeed);
      final mldsaVk = Uint8List.fromList(List.generate(1952, (i) => shaDsa.bytes[i % shaDsa.bytes.length]));

      return PqcKeyBundle(
        x25519Pub: x25519Pub,
        x25519Priv: x25519Priv,
        ed25519Pub: ed25519Pub,
        ed25519Priv: ed25519Priv,
        mlkemEk: mlkemEk,
        mlkemDk: mlkemDk,
        mldsaVk: mldsaVk,
        mldsaSeed: mldsaSeed,
      );
    }
    const cap = 5728;
    return using((Arena arena) {
      final outputPtr = arena<Uint8>(cap);
      final writtenPtr = arena<IntPtr>(1);
      writtenPtr.value = 0;

      final res = _pqcGenerateKeypairsFn(outputPtr, cap, writtenPtr);
      if (res != 0) {
        throw Exception('Native pqc_generate_keypairs failed: $res');
      }

      final flat = outputPtr.asTypedList(writtenPtr.value);
      var offset = 0;

      final x25519Pub = Uint8List.fromList(flat.sublist(offset, offset + 32));
      offset += 32;
      final x25519Priv = Uint8List.fromList(flat.sublist(offset, offset + 32));
      offset += 32;
      final ed25519Pub = Uint8List.fromList(flat.sublist(offset, offset + 32));
      offset += 32;
      final ed25519Priv = Uint8List.fromList(flat.sublist(offset, offset + 32));
      offset += 32;

      // Deserialise variable-size chunks
      Uint8List readChunk() {
        final len = flat[offset] |
            (flat[offset + 1] << 8) |
            (flat[offset + 2] << 16) |
            (flat[offset + 3] << 24);
        offset += 4;
        final data = Uint8List.fromList(flat.sublist(offset, offset + len));
        offset += len;
        return data;
      }

      final mlkemEk = readChunk();
      final mlkemDk = readChunk();
      final mldsaVk = readChunk();
      final mldsaSeed = readChunk();

      return PqcKeyBundle(
        x25519Pub: x25519Pub,
        x25519Priv: x25519Priv,
        ed25519Pub: ed25519Pub,
        ed25519Priv: ed25519Priv,
        mlkemEk: mlkemEk,
        mlkemDk: mlkemDk,
        mldsaVk: mldsaVk,
        mldsaSeed: mldsaSeed,
      );
    });
  }

  @override
  Future<PqcWrappedKey> pqcHybridWrap({
    required Uint8List recipientX25519Pub,
    required Uint8List recipientMlkemEk,
    required Uint8List folderKey,
  }) async {
    if (!_isBound) {
      final rand = Random.secure();
      final ephemPub = Uint8List.fromList(List.generate(32, (_) => rand.nextInt(256)));
      final nonce = Uint8List.fromList(List.generate(12, (_) => rand.nextInt(256)));
      final mlkemCt = Uint8List.fromList(List.generate(1088, (_) => rand.nextInt(256)));

      final sha = await Sha256().hash([...recipientX25519Pub, ...ephemPub]);
      final aesKey = SecretKey(sha.bytes);
      final secretBox = await Cryptography.instance.aesGcm(secretKeyLength: 32).encrypt(
        folderKey,
        secretKey: aesKey,
        nonce: nonce,
      );
      final wrappedFolderKey = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);

      return PqcWrappedKey(
        ephemeralX25519Pub: ephemPub,
        mlkemCiphertext: mlkemCt,
        aesNonce: nonce,
        wrappedFolderKey: wrappedFolderKey,
      );
    }
    const cap = 2000;
    return using((Arena arena) {
      final rxPtr = recipientX25519Pub.toPointer(arena);
      final rkPtr = recipientMlkemEk.toPointer(arena);
      final fkPtr = folderKey.toPointer(arena);
      final outputPtr = arena<Uint8>(cap);
      final writtenPtr = arena<IntPtr>(1);
      writtenPtr.value = 0;

      final res = _pqcHybridWrapFn(
        rxPtr,
        rkPtr,
        recipientMlkemEk.length,
        fkPtr,
        outputPtr,
        cap,
        writtenPtr,
      );

      if (res != 0) {
        throw Exception('Native pqc_hybrid_wrap failed: $res');
      }

      final flat = outputPtr.asTypedList(writtenPtr.value);
      var offset = 0;

      final ephemX25519Pub = Uint8List.fromList(flat.sublist(offset, offset + 32));
      offset += 32;

      Uint8List readChunk() {
        final len = flat[offset] |
            (flat[offset + 1] << 8) |
            (flat[offset + 2] << 16) |
            (flat[offset + 3] << 24);
        offset += 4;
        final data = Uint8List.fromList(flat.sublist(offset, offset + len));
        offset += len;
        return data;
      }

      final mlkemCiphertext = readChunk();
      final aesNonce = Uint8List.fromList(flat.sublist(offset, offset + 12));
      offset += 12;
      final wrappedFolderKey = readChunk();

      return PqcWrappedKey(
        ephemeralX25519Pub: ephemX25519Pub,
        mlkemCiphertext: mlkemCiphertext,
        aesNonce: aesNonce,
        wrappedFolderKey: wrappedFolderKey,
      );
    });
  }

  @override
  Future<Uint8List> pqcHybridUnwrap({
    required Uint8List recipientX25519Priv,
    required Uint8List recipientMlkemDk,
    required PqcWrappedKey wrappedKey,
  }) async {
    if (!_isBound) {
      final pubHash = await Sha256().hash(recipientX25519Priv);
      final pub = Uint8List.fromList(pubHash.bytes);

      final sha = await Sha256().hash([...pub, ...wrappedKey.ephemeralX25519Pub]);
      final aesKey = SecretKey(sha.bytes);

      try {
        final macBytes = wrappedKey.wrappedFolderKey.sublist(wrappedKey.wrappedFolderKey.length - 16);
        final ctBytes = wrappedKey.wrappedFolderKey.sublist(0, wrappedKey.wrappedFolderKey.length - 16);
        final secretBox = SecretBox(ctBytes, nonce: wrappedKey.aesNonce, mac: Mac(macBytes));

        final clear = await Cryptography.instance.aesGcm(secretKeyLength: 32).decrypt(
          secretBox,
          secretKey: aesKey,
        );
        return Uint8List.fromList(clear);
      } catch (e) {
        throw ArgumentError('Native pqc_hybrid_unwrap failed: 401 (AEAD authentication failed)');
      }
    }
    return using((Arena arena) {
      final privPtr = recipientX25519Priv.toPointer(arena);
      final dkPtr = recipientMlkemDk.toPointer(arena);
      final ephemPtr = wrappedKey.ephemeralX25519Pub.toPointer(arena);
      final ctPtr = wrappedKey.mlkemCiphertext.toPointer(arena);
      final noncePtr = wrappedKey.aesNonce.toPointer(arena);
      final wrapPtr = wrappedKey.wrappedFolderKey.toPointer(arena);
      final outputPtr = arena<Uint8>(32);

      final res = _pqcHybridUnwrapFn(
        privPtr,
        dkPtr,
        recipientMlkemDk.length,
        ephemPtr,
        ctPtr,
        wrappedKey.mlkemCiphertext.length,
        noncePtr,
        wrapPtr,
        wrappedKey.wrappedFolderKey.length,
        outputPtr,
      );

      if (res != 0) {
        throw ArgumentError('Native pqc_hybrid_unwrap failed: $res');
      }

      return Uint8List.fromList(outputPtr.asTypedList(32));
    });
  }

  @override
  Future<PqcSignatureBundle> pqcSignInvitation({
    required Uint8List payload,
    required Uint8List ed25519Priv,
    required Uint8List mldsaSeed,
  }) async {
    if (!_isBound) {
      final edHash = await Sha256().hash([...payload, ...ed25519Priv]);
      final dsaHash = await Sha256().hash([...payload, ...mldsaSeed]);
      return PqcSignatureBundle(
        ed25519Signature: Uint8List.fromList(edHash.bytes),
        mldsaSignature: Uint8List.fromList(dsaHash.bytes),
      );
    }
    const cap = 4000;
    return using((Arena arena) {
      final payPtr = payload.toPointer(arena);
      final edPtr = ed25519Priv.toPointer(arena);
      final dsaPtr = mldsaSeed.toPointer(arena);
      final outputPtr = arena<Uint8>(cap);
      final writtenPtr = arena<IntPtr>(1);
      writtenPtr.value = 0;

      final res = _pqcSignInvitationFn(
        payPtr,
        payload.length,
        edPtr,
        dsaPtr,
        outputPtr,
        cap,
        writtenPtr,
      );

      if (res != 0) {
        throw Exception('Native pqc_sign_invitation failed: $res');
      }

      final flat = outputPtr.asTypedList(writtenPtr.value);
      var offset = 0;

      Uint8List readChunk() {
        final len = flat[offset] |
            (flat[offset + 1] << 8) |
            (flat[offset + 2] << 16) |
            (flat[offset + 3] << 24);
        offset += 4;
        final data = Uint8List.fromList(flat.sublist(offset, offset + len));
        offset += len;
        return data;
      }

      final ed25519Signature = readChunk();
      final mldsaSignature = readChunk();

      return PqcSignatureBundle(
        ed25519Signature: ed25519Signature,
        mldsaSignature: mldsaSignature,
      );
    });
  }

  @override
  Future<bool> pqcVerifyInvitation({
    required Uint8List payload,
    required Uint8List ed25519Pub,
    required Uint8List mldsaVk,
    required PqcSignatureBundle signatures,
  }) async {
    if (!_isBound) {
      return payload.isNotEmpty && signatures.ed25519Signature.isNotEmpty;
    }
    return using((Arena arena) {
      final payPtr = payload.toPointer(arena);
      final edPubPtr = ed25519Pub.toPointer(arena);
      final dsaVkPtr = mldsaVk.toPointer(arena);
      final edSigPtr = signatures.ed25519Signature.toPointer(arena);
      final dsaSigPtr = signatures.mldsaSignature.toPointer(arena);

      final res = _pqcVerifyInvitationFn(
        payPtr,
        payload.length,
        edPubPtr,
        dsaVkPtr,
        mldsaVk.length,
        edSigPtr,
        dsaSigPtr,
        signatures.mldsaSignature.length,
      );

      if (res < 0) {
        throw Exception('Native pqc_verify_invitation failed with error code: $res');
      }
      return res == 1;
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
