import 'dart:convert';
import 'dart:io';
import 'package:core/core.dart';

/// Local HTTP loopback server that acts as the backend for the native messaging host.
///
/// Security Invariant: Only binds to local loopback (127.0.0.1) and handles queries
/// entirely in memory. The Vault Key never leaves this server context.
class LocalMessagingServer {
  static VaultDatabase? db;
  static HttpServer? _server;
  static final _crypto = VaultCrypto();

  /// Starts the loopback HTTP server.
  static Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 16235);
      _server!.listen((HttpRequest request) async {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Headers', '*');
        request.response.headers.add('Content-Type', 'application/json');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        final path = request.uri.path;
        if (path == '/status') {
          final locked = VaultLockManager.instance.isLocked;
          request.response.write(json.encode({
            'locked': locked,
            'unlocked': !locked,
          }));
        } else if (path == '/items') {
          final origin = request.uri.queryParameters['origin'];
          final locked = VaultLockManager.instance.isLocked;
          if (locked || origin == null) {
            request.response.write(json.encode({
              'locked': locked,
              'items': [],
            }));
          } else {
            final vaultKey = VaultLockManager.instance.vaultKey;
            if (vaultKey == null || db == null) {
              request.response.write(json.encode({
                'locked': true,
                'items': [],
              }));
            } else {
              final matchedItems = <Map<String, dynamic>>[];
              final allEncrypted = db!.getAllItems();
              final targetDomain = UrlScanner.extractDomain(origin);

              for (final enc in allEncrypted) {
                try {
                  final decrypted = await VaultItem.decrypt(enc, vaultKey, _crypto);
                  
                  // Check exact domain match (no subdomains wildcard by default)
                  bool domainMatches = false;
                  String username = '';
                  String password = '';

                  if (decrypted.fields is LoginFields) {
                    final loginFields = decrypted.fields as LoginFields;
                    for (final url in loginFields.urls) {
                      if (UrlScanner.extractDomain(url) == targetDomain) {
                        domainMatches = true;
                        break;
                      }
                    }
                    if (domainMatches) {
                      username = loginFields.username;
                      password = loginFields.password.plaintext ?? '';

                      matchedItems.add({
                        'title': decrypted.title,
                        'username': username,
                        'password': password,
                      });
                    }
                  }
                } catch (_) {
                  // Skip if decryption fails
                }
              }

              request.response.write(json.encode({
                'locked': false,
                'items': matchedItems,
              }));
            }
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    } catch (_) {
      // Ignore bind exceptions in background
    }
  }

  /// Stops the server.
  static Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
}
