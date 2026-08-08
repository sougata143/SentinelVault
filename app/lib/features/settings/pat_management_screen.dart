import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../theme/theme.dart';
import '../../../config/api_config.dart';

class PatRecordDto {
  final String id;
  final String name;
  final String tokenPrefix;
  final List<String> scopes;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final bool isRevoked;
  final DateTime createdAt;

  const PatRecordDto({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.scopes,
    this.expiresAt,
    this.lastUsedAt,
    required this.isRevoked,
    required this.createdAt,
  });

  factory PatRecordDto.fromJson(Map<String, dynamic> json) {
    return PatRecordDto(
      id: json['id'] as String,
      name: json['name'] as String,
      tokenPrefix: json['tokenPrefix'] as String,
      scopes: (json['scopes'] as List).cast<String>(),
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt'] as String) : null,
      lastUsedAt: json['lastUsedAt'] != null ? DateTime.parse(json['lastUsedAt'] as String) : null,
      isRevoked: json['isRevoked'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class PatManagementScreen extends StatefulWidget {
  final String? sessionToken;
  final String? authBaseUrl;
  final http.Client? httpClient;

  const PatManagementScreen({
    super.key,
    this.sessionToken,
    this.authBaseUrl,
    this.httpClient,
  });

  @override
  State<PatManagementScreen> createState() => _PatManagementScreenState();
}

class _PatManagementScreenState extends State<PatManagementScreen> {
  List<PatRecordDto> _tokens = [];
  bool _isLoading = true;
  String? _errorMessage;

  String get _effectiveAuthBaseUrl =>
      (widget.authBaseUrl != null && widget.authBaseUrl!.isNotEmpty)
          ? widget.authBaseUrl!
          : ApiConfig.authBaseUrl;

  @override
  void initState() {
    super.initState();
    _fetchTokens();
  }

  Future<void> _fetchTokens() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveAuthBaseUrl/auth/pats');

      final response = await client.get(
        uri,
        headers: {
          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
        },
      );

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        setState(() {
          _tokens = list.map((e) => PatRecordDto.fromJson(e)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load access tokens (HTTP ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading access tokens: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _revokeToken(String tokenId) async {
    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveAuthBaseUrl/auth/pats/$tokenId/revoke');

      final response = await client.post(
        uri,
        headers: {
          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
        },
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access Token revoked successfully.')),
        );
        _fetchTokens();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error revoking token: $e')),
      );
    }
  }

  void _showCreateTokenDialog() {
    final nameController = TextEditingController();
    int expiryDays = 90;
    bool scopeRead = true;
    bool scopeWrite = false;
    bool scopeSharing = false;

    String? generatedRawToken;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: SentinelTheme.surfaceDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Generate Personal Access Token', style: TextStyle(color: SentinelTheme.textPrimary, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (generatedRawToken == null) ...[
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Token Description Name (e.g. CI/CD Bot)',
                          filled: true,
                          fillColor: SentinelTheme.cardDark,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Permissions (Scopes)', style: TextStyle(color: SentinelTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
                      CheckboxListTile(
                        value: scopeRead,
                        onChanged: (val) => setDialogState(() => scopeRead = val ?? true),
                        title: const Text('vault:read (Read encrypted items)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        activeColor: SentinelTheme.accentCyan,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: scopeWrite,
                        onChanged: (val) => setDialogState(() => scopeWrite = val ?? false),
                        title: const Text('vault:write (Create & update items)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        activeColor: SentinelTheme.accentCyan,
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: scopeSharing,
                        onChanged: (val) => setDialogState(() => scopeSharing = val ?? false),
                        title: const Text('sharing:read (Read shared invites)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        activeColor: SentinelTheme.accentCyan,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: expiryDays,
                        dropdownColor: SentinelTheme.cardDark,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Expiration',
                          filled: true,
                          fillColor: SentinelTheme.cardDark,
                        ),
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 Days')),
                          DropdownMenuItem(value: 90, child: Text('90 Days (Default)')),
                          DropdownMenuItem(value: 365, child: Text('1 Year')),
                          DropdownMenuItem(value: 0, child: Text('Never (No Expiration)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => expiryDays = val);
                        },
                      ),
                    ] else ...[
                      const Text('🔒 Copy Your Personal Access Token:', style: TextStyle(color: SentinelTheme.accentCyan, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SentinelTheme.cardDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: SentinelTheme.accentCyan),
                        ),
                        child: SelectableText(
                          generatedRawToken!,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Save this secret token now. For your security, it will never be displayed again.',
                        style: TextStyle(color: SentinelTheme.warningYellow, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(generatedRawToken == null ? 'Cancel' : 'Close', style: const TextStyle(color: SentinelTheme.textMuted)),
                ),
                if (generatedRawToken == null)
                  ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;

                      final scopes = <String>[];
                      if (scopeRead) scopes.add('vault:read');
                      if (scopeWrite) scopes.add('vault:write');
                      if (scopeSharing) scopes.add('sharing:read');

                      final client = widget.httpClient ?? http.Client();
                      final uri = Uri.parse('$_effectiveAuthBaseUrl/auth/pats');

                      final res = await client.post(
                        uri,
                        headers: {
                          'Content-Type': 'application/json',
                          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
                        },
                        body: jsonEncode({
                          'name': name,
                          'scopes': scopes,
                          'expiryDays': expiryDays,
                        }),
                      );

                      if (res.statusCode == 201) {
                        final resJson = jsonDecode(res.body);
                        setDialogState(() {
                          generatedRawToken = resJson['rawToken'] as String;
                        });
                        _fetchTokens();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SentinelTheme.accentCyan,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Generate Token'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: generatedRawToken!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Access Token copied to clipboard!')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Token'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SentinelTheme.accentCyan,
                      foregroundColor: Colors.black,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SentinelTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Developer Personal Access Tokens'),
        backgroundColor: SentinelTheme.surfaceDark,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: SentinelTheme.accentCyan),
            onPressed: _showCreateTokenDialog,
            tooltip: 'Generate Token',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: SentinelTheme.accentCyan))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
              : _tokens.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.vpn_key_outlined, color: SentinelTheme.textMuted, size: 48),
                          const SizedBox(height: 12),
                          const Text('No Personal Access Tokens generated yet.', style: TextStyle(color: SentinelTheme.textMuted)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showCreateTokenDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Generate Token'),
                            style: ElevatedButton.styleFrom(backgroundColor: SentinelTheme.accentCyan, foregroundColor: Colors.black),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tokens.length,
                      itemBuilder: (context, index) {
                        final token = _tokens[index];
                        final isExpired = token.expiresAt != null && DateTime.now().isAfter(token.expiresAt!);

                        String statusText = 'Active';
                        Color statusColor = SentinelTheme.accentCyan;

                        if (token.isRevoked) {
                          statusText = 'Revoked';
                          statusColor = Colors.redAccent;
                        } else if (isExpired) {
                          statusText = 'Expired';
                          statusColor = SentinelTheme.warningYellow;
                        }

                        return Card(
                          color: SentinelTheme.cardDark,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: SentinelTheme.borderDark),
                          ),
                          child: ListTile(
                            title: Text(
                              token.name,
                              style: const TextStyle(color: SentinelTheme.textPrimary, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  token.tokenPrefix,
                                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Scopes: ${token.scopes.join(", ")}',
                                  style: const TextStyle(color: SentinelTheme.textMuted, fontSize: 12),
                                ),
                                if (token.lastUsedAt != null)
                                  Text(
                                    'Last Used: ${token.lastUsedAt!.toLocal()}',
                                    style: const TextStyle(color: SentinelTheme.textMuted, fontSize: 11),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                  backgroundColor: statusColor.withValues(alpha: 0.12),
                                  side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
                                ),
                                if (!token.isRevoked)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: 'Revoke Token',
                                    onPressed: () => _revokeToken(token.id),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
