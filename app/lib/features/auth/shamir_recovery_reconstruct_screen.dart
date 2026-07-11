import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import '../../app_shell.dart';
import '../../theme/theme.dart';

class ShamirRecoveryReconstructScreen extends StatefulWidget {
  final String email;
  final String syncBaseUrl;
  final http.Client httpClient;

  const ShamirRecoveryReconstructScreen({
    super.key,
    required this.email,
    required this.syncBaseUrl,
    required this.httpClient,
  });

  @override
  State<ShamirRecoveryReconstructScreen> createState() => _ShamirRecoveryReconstructScreenState();
}

class _ShamirRecoveryReconstructScreenState extends State<ShamirRecoveryReconstructScreen> {
  final List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  bool _isReconstructing = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addShareField() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeShareField(int index) {
    if (_controllers.length > 2) {
      setState(() {
        final controller = _controllers.removeAt(index);
        controller.dispose();
      });
    }
  }

  Future<void> _handleReconstruct() async {
    setState(() {
      _isReconstructing = true;
      _errorMessage = null;
    });

    final shares = _controllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (shares.isEmpty) {
      setState(() {
        _isReconstructing = false;
        _errorMessage = 'Please enter at least one share.';
      });
      return;
    }

    try {
      final syncClient = HttpSyncApiClient(
        baseUrl: widget.syncBaseUrl,
        userId: widget.email,
        httpClient: widget.httpClient,
      );

      // 1. Fetch current wrapped vault key and recovery salt (epoch ID) from the sync server
      final keysMap = await syncClient.fetchVaultKey();
      if (!keysMap.containsKey('recoverySalt') || !keysMap.containsKey('recoveryWrappedKey')) {
        throw Exception('No Shamir/Emergency Recovery setup found for this account.');
      }

      final serverSaltHex = keysMap['recoverySalt']!;
      final serverWrappedKeyHex = keysMap['wrappedKey']!;
      final serverRecoveryWrappedKeyHex = keysMap['recoveryWrappedKey']!;

      // Convert server recovery salt hex back to uuid epoch format for checking
      final serverEpochId = _hexToUuid(serverSaltHex);

      // Parse first share to check metadata
      final shamir = ShamirRecovery();

      // Check first share for threshold
      final firstPacket = _parseBase32(shares[0]);
      if (firstPacket.length != 41) {
        throw Exception('First share is invalid or has wrong length.');
      }
      final expectedThreshold = firstPacket[16];

      if (shares.length < expectedThreshold) {
        throw Exception('You need at least $expectedThreshold valid shares to reconstruct the key. '
            'Currently provided: ${shares.length}.');
      }

      // Check epochs of all shares against server epoch
      for (var i = 0; i < shares.length; i++) {
        final packet = _parseBase32(shares[i]);
        if (packet.length != 41) {
          throw Exception('Share ${i + 1} is invalid or has wrong length.');
        }
        final shareEpochBytes = packet.sublist(0, 16);
        final shareEpochStr = _uuidBytesToString(shareEpochBytes);
        if (shareEpochStr != serverEpochId) {
          throw Exception(
            'Share ${i + 1} belongs to a different or outdated recovery key set. '
            'If you regenerated shares, previous sets are permanently invalidated.'
          );
        }
      }

      // 2. Combine shares to reconstruct recovery key
      final reconstructedRK = shamir.combineShares(shares);

      // 3. Derive recovery KDF key using recovery salt
      final crypto = VaultCrypto();
      final rkSaltBytes = _uuidToBytes(serverEpochId);
      final rkk = await crypto.deriveRecoveryKdfKey(
        recoveryKey: reconstructedRK,
        salt: rkSaltBytes,
      );

      // 4. Unwrap vault key
      final recoveryWrappedKey = _hexToBytes(serverRecoveryWrappedKeyHex);
      final vaultKey = await crypto.unwrapVaultKey(
        wrappedVaultKey: recoveryWrappedKey,
        masterKey: rkk,
      );

      final db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);

      // Success! Unlock Vault, clean sensitive recovery parameters, navigate to AppShell
      VaultLockManager.instance.unlockWithRecoveryKey(vaultKey);

      // Zero out intermediate recovery keys
      _zeroOutList(rkSaltBytes);
      _zeroOutList(rkk);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AppShell(
              db: db,
              vaultKey: vaultKey,
              currentEmail: widget.email,
              syncBaseUrl: widget.syncBaseUrl,
              httpClient: widget.httpClient,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _isReconstructing = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Uint8List _parseBase32(String base32Str) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned = base32Str.replaceAll('-', '').toUpperCase();
    var bitBuffer = 0;
    var bitCount = 0;
    final result = <int>[];
    for (var i = 0; i < cleaned.length; i++) {
      final index = alphabet.indexOf(cleaned[i]);
      if (index == -1) {
        throw ArgumentError('Invalid character');
      }
      bitBuffer = (bitBuffer << 5) | index;
      bitCount += 5;
      if (bitCount >= 8) {
        result.add((bitBuffer >> (bitCount - 8)) & 255);
        bitCount -= 8;
      }
    }
    return Uint8List.fromList(result);
  }

  String _uuidBytesToString(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toUpperCase();
  }

  String _hexToUuid(String hex) {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(hex.substring(i * 2, i * 2 + 2));
    }
    return buffer.toString().toUpperCase();
  }

  Uint8List _uuidToBytes(String uuid) {
    final cleaned = uuid.replaceAll('-', '').toLowerCase();
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  void _zeroOutList(List<int> list) {
    for (var i = 0; i < list.length; i++) {
      list[i] = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reconstruct Recovery Key'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.people_outline, size: 72, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              const Text(
                'Enter Recovery Shares',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimaryColor,
                  fontFamily: 'Outfit',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Paste the recovery shares provided by your trusted contacts. '
                'Once the threshold (M) is reached, the key will be reconstructed client-side.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _controllers.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: Key('share-input-field-$index'),
                            controller: _controllers[index],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Recovery Share ${index + 1}',
                              hintText: 'XXXX-XXXX-XXXX-XXXX-...',
                              suffixIcon: _controllers[index].text.isNotEmpty
                                  ? const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20)
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (_controllers.length > 2) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            key: Key('remove-share-field-$index'),
                            icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorColor),
                            onPressed: () => _removeShareField(index),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('add-share-field-button'),
                onPressed: _addShareField,
                icon: const Icon(Icons.add),
                label: const Text('Add Another Share Field'),
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppTheme.errorColor, fontSize: 14, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton(
                key: const Key('reconstruct-key-button'),
                onPressed: _isReconstructing ? null : _handleReconstruct,
                child: _isReconstructing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Reconstruct & Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
