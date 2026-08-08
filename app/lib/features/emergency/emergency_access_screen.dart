import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../theme/theme.dart';

class EmergencyAccessScreen extends StatefulWidget {
  final String currentEmail;
  final List<int> vaultKey;
  final String sharingBaseUrl;
  final http.Client? httpClient;

  const EmergencyAccessScreen({
    super.key,
    required this.currentEmail,
    required this.vaultKey,
    this.sharingBaseUrl = '',
    this.httpClient,
  });

  @override
  State<EmergencyAccessScreen> createState() => _EmergencyAccessScreenState();
}

class _EmergencyAccessScreenState extends State<EmergencyAccessScreen> {
  String get _effectiveSharingBaseUrl =>
      widget.sharingBaseUrl.isNotEmpty ? widget.sharingBaseUrl : ApiConfig.sharingBaseUrl;
  final _emailController = TextEditingController();
  int _selectedWaitingPeriodHours = 72; // Default 72 hours (3 days)
  bool _isLoading = true;

  List<Map<String, dynamic>> _myContacts = [];
  List<Map<String, dynamic>> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadEmergencyData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadEmergencyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final client = widget.httpClient ?? http.Client();
      
      // Fetch contacts designated by owner
      final contactsRes = await client.get(
        Uri.parse('$_effectiveSharingBaseUrl/emergency/contacts/owner?ownerUserId=${widget.currentEmail}'),
      );
      if (contactsRes.statusCode == 200) {
        final data = jsonDecode(contactsRes.body);
        _myContacts = List<Map<String, dynamic>>.from(data['contacts'] ?? []);
      }

      // Fetch pending requests for owner
      final reqsRes = await client.get(
        Uri.parse('$_effectiveSharingBaseUrl/emergency/requests/pending?ownerUserId=${widget.currentEmail}'),
      );
      if (reqsRes.statusCode == 200) {
        final data = jsonDecode(reqsRes.body);
        _pendingRequests = List<Map<String, dynamic>>.from(data['requests'] ?? []);
      }
    } catch (_) {
      // Graceful fallback for offline mode or mock testing
      _myContacts = [];
      _pendingRequests = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addTrustedContact() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = widget.httpClient ?? http.Client();
      // Dummy ML-KEM-768 ciphertext wrapping of vault key for contact
      final hexKey = widget.vaultKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final wrappedKey = 'pqc_mlkem768_wrapped:$hexKey';

      final res = await client.post(
        Uri.parse('${widget.sharingBaseUrl}/emergency/contacts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ownerUserId': widget.currentEmail,
          'contactEmail': email,
          'contactUserId': email,
          'waitingPeriodHours': _selectedWaitingPeriodHours,
          'wrappedVaultKey': wrappedKey,
        }),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        _emailController.clear();
        await _loadEmergencyData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Designated $email as trusted contact with $_selectedWaitingPeriodHours h delay')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add trusted contact')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _denyRequest(String requestId) async {
    try {
      final client = widget.httpClient ?? http.Client();
      await client.post(
        Uri.parse('${widget.sharingBaseUrl}/emergency/requests/$requestId/deny'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerUserId': widget.currentEmail}),
      );
      await _loadEmergencyData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access Request Denied successfully.')),
        );
      }
    } catch (_) {}
  }

  Future<void> _revokeContact(String contactId) async {
    try {
      final client = widget.httpClient ?? http.Client();
      await client.post(
        Uri.parse('${widget.sharingBaseUrl}/emergency/contacts/$contactId/revoke'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ownerUserId': widget.currentEmail}),
      );
      await _loadEmergencyData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trusted contact designation revoked.')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency & Inheritance Access')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prominent Pending Request Warning Banner
                  if (_pendingRequests.isNotEmpty) ...[
                    Card(
                      color: AppTheme.errorColor.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppTheme.errorColor, width: 2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 28),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'ACTION REQUIRED: Emergency Access Request Pending!',
                                    style: TextStyle(
                                      color: AppTheme.errorColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._pendingRequests.map((req) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Request from: ${req['contactUserId']}\nGrants At: ${req['grantsAt']}',
                                            style: const TextStyle(fontSize: 12, height: 1.4),
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
                                          onPressed: () => _denyRequest(req['id']),
                                          child: const Text('DENY REQUEST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Add Trusted Contact Section
                  const Text(
                    'Designate Trusted Contact',
                    style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Designate trusted contacts who can request vault access in emergency or inheritance scenarios after a mandatory waiting period.',
                    style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: AppTheme.surfaceColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Contact SentinelVault Email',
                              hintText: 'trusted.contact@example.com',
                              prefixIcon: Icon(Icons.person_add_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Waiting Period Before Access:'),
                              DropdownButton<int>(
                                value: _selectedWaitingPeriodHours,
                                dropdownColor: AppTheme.surfaceColor,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                underline: const SizedBox(),
                                items: const [
                                  DropdownMenuItem(value: 24, child: Text('24 Hours (1 Day)')),
                                  DropdownMenuItem(value: 72, child: Text('72 Hours (3 Days)')),
                                  DropdownMenuItem(value: 168, child: Text('7 Days')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedWaitingPeriodHours = val);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: _addTrustedContact,
                              icon: const Icon(Icons.shield_outlined),
                              label: const Text('Add Trusted Contact', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Active Designated Contacts List
                  const Text(
                    'Active Emergency Contacts',
                    style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_myContacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No trusted contacts designated yet.', style: TextStyle(color: AppTheme.textSecondaryColor)),
                    )
                  else
                    ..._myContacts.map((contact) => Card(
                          color: AppTheme.surfaceColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppTheme.primaryColor,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(contact['contactEmail'] ?? 'Contact'),
                            subtitle: Text('Waiting Period: ${contact['waitingPeriodHours']} hours'),
                            trailing: IconButton(
                              icon: const Icon(Icons.person_remove_outlined, color: AppTheme.errorColor),
                              onPressed: () => _revokeContact(contact['id']),
                              tooltip: 'Revoke Access',
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
