/// Shared core library for SentinelVault.
/// 
/// Contains zero-knowledge cryptography primitives, vault models, and sync engines.
library core;

export 'src/crypto/crypto.dart';
export 'src/crypto/srp.dart';
export 'src/database/vault_database.dart';
export 'src/models/models.dart';
export 'src/security/password_strength.dart';
export 'src/security/url_scanner.dart';
export 'src/security/email_scanner.dart';
export 'src/security/breach_monitor.dart';
export 'src/security/file_scanner.dart';
export 'src/sync/sync.dart';
export 'src/import/import_result.dart';
export 'src/import/parsers/bitwarden_parser.dart';
export 'src/import/parsers/one_password_parser.dart';
export 'src/import/parsers/lastpass_parser.dart';
export 'src/import/parsers/generic_csv_parser.dart';
export 'src/import/parsers/dashlane_parser.dart';
export 'src/import/parsers/keeper_parser.dart';
export 'src/import/parsers/nordpass_parser.dart';
export 'src/import/parsers/roboform_parser.dart';
export 'src/import/parsers/protonpass_parser.dart';
export 'src/import/parsers/keepass_kdbx_parser.dart';
export 'src/export/export_service.dart';
export 'src/export/security_activity_log.dart';
export 'src/security/ai_insights_client.dart';
export 'src/auth/auth_client.dart';
export 'src/auth/vault_lock_manager.dart';
export 'src/auth/biometric_auth_service.dart';
export 'src/platform/secure_storage.dart';
export 'src/sync/http_sync_api_client.dart';
export 'src/crypto/hardware_key_unlock.dart';
export 'src/crypto/shamir_recovery.dart';
export 'src/platform/duress_wipe_hook.dart';
export 'src/vault/dual_vault_manager.dart';
export 'src/crypto/pqc_sharing.dart';
export 'src/crypto/native_crypto_bridge.dart' show PqcKeyBundle, PqcWrappedKey, PqcSignatureBundle;





