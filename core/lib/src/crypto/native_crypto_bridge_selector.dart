import 'native_crypto_bridge.dart';

// Conditional import brings NativeCryptoBridgeImpl into scope for the factory
// function below. The conditional export re-exports the same class so that
// external code importing this selector library also sees the correct type.
import 'native_crypto_bridge_stub.dart'
    if (dart.library.io) 'native_crypto_bridge_io.dart'
    if (dart.library.js_interop) 'native_crypto_bridge_web.dart';

export 'native_crypto_bridge_stub.dart'
    if (dart.library.io) 'native_crypto_bridge_io.dart'
    if (dart.library.js_interop) 'native_crypto_bridge_web.dart';

/// Factory function that returns the platform-specific [NativeCryptoBridge] implementation.
///
/// On native platforms (iOS, Android, Desktop), returns the FFI-backed implementation.
/// On Web, returns the JS-interop-backed implementation.
/// In test environments where neither native library is present, returns the
/// [NativeCryptoBridgeImpl] stub, which throws [UnsupportedError] if called —
/// tests that exercise crypto paths should mock [NativeCryptoBridge] directly.
NativeCryptoBridge getNativeCryptoBridge() => NativeCryptoBridgeImpl();
