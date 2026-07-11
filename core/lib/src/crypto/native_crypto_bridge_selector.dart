export 'native_crypto_bridge_stub.dart'
    if (dart.library.io) 'native_crypto_bridge_io.dart'
    if (dart.library.js_interop) 'native_crypto_bridge_web.dart';

/// Factory function that returns the platform-specific NativeCryptoBridge implementation.
///
/// On native platforms (iOS, Android, Desktop), this returns the FFI-based implementation.
/// On Web, this returns the JS interop-based implementation.
NativeCryptoBridge getNativeCryptoBridge() => NativeCryptoBridgeImpl();
