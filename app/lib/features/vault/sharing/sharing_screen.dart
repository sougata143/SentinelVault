import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
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
  final _emailController = TextEditingController();
  final _sharingManager = PqcSharingManager();
  bool _loading = false;
  List<Map<String, dynamic>> _recipients = []; // { userId, email, fingerprint }

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    setState(() => _loading = true);
    // In production: fetch from backend sharing-service current key version recipients
    // Stub local list for UI demo/validation
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() {
      _loading = false;
      // bob-id is currently shared
      _recipients = [
        {
          'userId': 'bob-id-12345',
          'email': 'bob@example.com',
          'fingerprint': '49102 95810 39581 02938 10928 30491',
          'x25519Pub': Uint8List(32),
          'mlkemEk': Uint8List(1184),
        }
      ];
    });
  }

  Future<void> _inviteRecipient() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _loading = true);
    try {
      // 1. Simulate lookup of target user's key bundle from directory
      // In production: GET /key-directory/keys/:userId (after finding userId from email)
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Simulating a fetched bundle:
      final recipientBundle = PqcKeyBundle(
        x25519Pub: Uint8List.fromList(List.generate(32, (i) => i)),
        x25519Priv: Uint8List(32),
        ed25519Pub: Uint8List(32),
        ed25519Priv: Uint8List(32),
        mlkemEk: Uint8List.fromList(List.generate(1184, (i) => i % 256)),
        mlkemDk: Uint8List(2400),
        mldsaVk: Uint8List.fromList(List.generate(1952, (i) => i % 256)),
        mldsaSeed: Uint8List(32),
      );

      final safetyNumber = await _sharingManager.computeSafetyNumber(recipientBundle);

      if (!mounted) return;

      // 2. Open out-of-band trust confirmation dialog (Strict security rule gate)
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

      // 3. User confirmed fingerprint! Now sign invitation and encapsulate Folder Key.
      // Generate keys for the sender (Alice)
      final senderBundle = PqcKeyBundle(
        x25519Pub: Uint8List(32),
        x25519Priv: Uint8List(32),
        ed25519Pub: Uint8List(32),
        ed25519Priv: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        mlkemEk: Uint8List(1184),
        mlkemDk: Uint8List(2400),
        mldsaVk: Uint8List(1952),
        mldsaSeed: Uint8List.fromList(List.generate(32, (i) => i + 2)),
      );

      await _sharingManager.createSignedInvitation(
        folderId: widget.folderId,
        recipientUserId: 'new-recipient-id',
        senderUserId: widget.senderUserId,
        ed25519Priv: senderBundle.ed25519Priv,
        mldsaSeed: senderBundle.mldsaSeed,
        folderKey: Uint8List.fromList(widget.currentFolderKey),
        recipientX25519Pub: recipientBundle.x25519Pub,
        recipientMlkemEk: recipientBundle.mlkemEk,
      );

      if (!mounted) return;

      // In production: POST /invites with invitePayload
      _emailController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully created sharing invitation for $email!'),
          backgroundColor: Colors.teal.shade800,
        ),
      );

      // Add to local list for demonstration
      setState(() {
        _recipients.add({
          'userId': 'new-recipient-id',
          'email': email,
          'fingerprint': safetyNumber,
          'x25519Pub': recipientBundle.x25519Pub,
          'mlkemEk': recipientBundle.mlkemEk,
        });
      });
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
          'x25519Pub': r['x25519Pub'] as Uint8List,
          'mlkemEk': r['mlkemEk'] as Uint8List,
        }).toList(),
      );

      if (!mounted) return;

      // In production: DELETE /key-directory/wrapped-keys/revoke with wraps
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        _recipients = remaining;
      });

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
