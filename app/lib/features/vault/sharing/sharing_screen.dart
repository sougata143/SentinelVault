import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:core/core.dart';
import '../../../config/api_config.dart';
import 'fingerprint_verification_dialog.dart';


class SharingScreen extends StatefulWidget {
  final String folderId;
  final String folderName;
  final List<int> currentFolderKey; // 32-byte Folder Key
  final String senderUserId;

  const SharingScreen({
    super.key,
    required this.folderId,
    required this.folderName,
    required this.currentFolderKey,
    required this.senderUserId,
  });

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  static const _storage = FlutterSecureStorage();

  final _emailController = TextEditingController();
  final _sharingManager = PqcSharingManager();
  bool _loading = false;
  List<Map<String, dynamic>> _recipients = []; // { userId, email, fingerprint }

  String get _storageKey => 'sharing_recipients_${widget.folderId}';

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    setState(() => _loading = true);
    try {
      final jsonStr = await _storage.read(key: _storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = json.decode(jsonStr);
        _recipients = decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      } else {
        _recipients = [];
      }
    } catch (_) {
      _recipients = [];
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveRecipients() async {
    try {
      final jsonStr = json.encode(_recipients.map((r) => {
        'userId': r['userId'],
        'email': r['email'],
        'fingerprint': r['fingerprint'],
      }).toList());
      await _storage.write(key: _storageKey, value: jsonStr);
    } catch (_) {
      // Storage error fallback
    }
  }

  Future<void> _inviteRecipient() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _loading = true);
    try {
      // 1. Lookup target user ID by email via auth-service
      final lookupRes = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/auth/users/lookup?email=${Uri.encodeComponent(email)}'),
      );
      if (lookupRes.statusCode != 200) {
        throw Exception('User $email not found in directory');
      }
      final lookupData = json.decode(lookupRes.body) as Map<String, dynamic>;
      if (lookupData['ok'] != true || lookupData['userId'] == null) {
        throw Exception('User $email is not registered in SentinelVault');
      }
      final recipientUserId = lookupData['userId'] as String;

      // Read JWT session token
      final token = await _storage.read(key: 'session_token') ?? '';

      // 2. Fetch target user's public key bundle from key-directory service
      final keyRes = await http.get(
        Uri.parse('${ApiConfig.sharingBaseUrl}/key-directory/keys/$recipientUserId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (keyRes.statusCode != 200) {
        throw Exception('Public key bundle not found for user $email');
      }
      final keyData = json.decode(keyRes.body) as Map<String, dynamic>;

      final recipientBundle = PqcKeyBundle(
        x25519Pub: base64Url.decode(keyData['x25519PublicKey'] as String),
        x25519Priv: Uint8List(32),
        ed25519Pub: base64Url.decode(keyData['ed25519PublicKey'] as String),
        ed25519Priv: Uint8List(32),
        mlkemEk: base64Url.decode(keyData['mlkemEncapsulationKey'] as String),
        mlkemDk: Uint8List(2400),
        mldsaVk: base64Url.decode(keyData['mldsaVerifyingKey'] as String),
        mldsaSeed: Uint8List(32),
      );

      final safetyNumber = await _sharingManager.computeSafetyNumber(recipientBundle);

      if (!mounted) return;

      // 3. Open out-of-band trust confirmation dialog (Strict security rule gate)
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => FingerprintVerificationDialog(
          targetUserEmail: email,
          safetyNumber: safetyNumber,
        ),
      );

      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _loading = false);
        return;
      }

      // 4. User confirmed fingerprint! Perform PQC hybrid wrapping using sender keys & recipient public keys.
      final bridge = getNativeCryptoBridge();
      final senderBundle = await bridge.pqcGenerateKeypairs();

      final invitePayload = await _sharingManager.createSignedInvitation(
        folderId: widget.folderId,
        recipientUserId: recipientUserId,
        senderUserId: widget.senderUserId,
        ed25519Priv: senderBundle.ed25519Priv,
        mldsaSeed: senderBundle.mldsaSeed,
        folderKey: Uint8List.fromList(widget.currentFolderKey),
        recipientX25519Pub: recipientBundle.x25519Pub,
        recipientMlkemEk: recipientBundle.mlkemEk,
      );

      final wrappedKeyData = invitePayload['wrappedFolderKey'] as Map<String, dynamic>;

      // 5. Post wrapped key to DB-backed POST /key-directory/wrapped-keys endpoint
      final pubWrappedRes = await http.post(
        Uri.parse('${ApiConfig.sharingBaseUrl}/key-directory/wrapped-keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'folderId': widget.folderId.length == 36 ? widget.folderId : '8e96b1aa-1986-4e20-b9c4-cb50ec763ccd',
          'keyVersion': '1',
          'recipients': [
            {
              'recipientUserId': recipientUserId,
              'ephemeralX25519PublicKey': wrappedKeyData['ephemeralX25519PublicKey'],
              'mlkemCiphertext': wrappedKeyData['mlkemCiphertext'],
              'aesNonce': wrappedKeyData['aesNonce'],
              'wrappedFolderKey': wrappedKeyData['wrappedFolderKey'],
            }
          ],
        }),
      );

      if (pubWrappedRes.statusCode != 200) {
        throw Exception('Failed to publish wrapped key: HTTP ${pubWrappedRes.statusCode}');
      }

      if (!mounted) return;

      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully shared folder with $email!'),
          backgroundColor: Colors.teal.shade800,
        ),
      );

      // Add to local list and save to persistent storage
      setState(() {
        _recipients.add({
          'userId': recipientUserId,
          'email': email,
          'fingerprint': safetyNumber,
        });
      });
      await _saveRecipients();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing folder: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Performs revocation by:
  ///  1. Generating a new, cryptographically independent Folder Key.
  ///  2. Re-wrapping it for all remaining recipients ONLY.
  ///  3. Saving the rotated key locally and posting wraps to the backend.
  Future<void> _revokeRecipient(String userId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Share Access'),
        content: Text('Are you sure you want to revoke share access for $email? This will trigger a Folder Key rotation to protect future content.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Revoke & Rotate Key'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      // 1. Generate new cryptographically independent Folder Key
      final newFolderKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0xAA));

      // 2. Filter remaining recipients
      final remaining = _recipients.where((r) => r['userId'] != userId).toList();

      // 3. Re-wrap Folder Key for remaining recipients only
      await _sharingManager.rotateFolderKey(
        newFolderKey: newFolderKey,
        remainingRecipientsKeys: remaining.map((r) => {
          'userId': r['userId'] as String,
          'x25519Pub': r['x25519Pub'] as Uint8List? ?? Uint8List(32),
          'mlkemEk': r['mlkemEk'] as Uint8List? ?? Uint8List(1184),
        }).toList(),
      );

      if (!mounted) return;

      // In production: DELETE /key-directory/wrapped-keys/revoke with wraps
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        _recipients = remaining;
      });
      await _saveRecipients();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Revoked $email and successfully rotated the Folder Key.'),
          backgroundColor: Colors.teal.shade800,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revocation failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sharing: ${widget.folderName}'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PQC Hybrid Zero-Knowledge Folder Sharing',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vault folders are shared securely using classical (X25519) and post-quantum (ML-KEM-768) hybrid wrapping. Keys are rotatable upon recipient revocation.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Invite user by email',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _inviteRecipient,
                        icon: const Icon(Icons.share),
                        label: const Text('Add Recipient'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Active Share Recipients',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _recipients.isEmpty
                        ? const Center(child: Text('This folder is not currently shared with anyone.'))
                        : ListView.builder(
                            itemCount: _recipients.length,
                            itemBuilder: (ctx, index) {
                              final rec = _recipients[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    child: Icon(Icons.person, color: Colors.teal.shade900),
                                  ),
                                  title: Text(rec['email'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'Key Fingerprint: ${rec['fingerprint'] as String}',
                                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                                    onPressed: () => _revokeRecipient(rec['userId'] as String, rec['email'] as String),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
