import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../theme/theme.dart';

class ManageDevicesScreen extends StatefulWidget {
  final String authBaseUrl;
  final String jwtToken;
  final http.Client? httpClient;

  const ManageDevicesScreen({
    super.key,
    this.authBaseUrl = ApiConfig.authBaseUrl,
    this.jwtToken = 'mock_jwt_token',
    this.httpClient,
  });

  @override
  State<ManageDevicesScreen> createState() => _ManageDevicesScreenState();
}

class _ManageDevicesScreenState extends State<ManageDevicesScreen> {
  late final AuthClient _authClient;
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _authClient = AuthClient(
      baseUrl: widget.authBaseUrl,
      httpClient: widget.httpClient,
    );
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sessions = await _authClient.getSessions(widget.jwtToken);
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRevoke(Map<String, dynamic> session) async {
    final sessionId = session['id'] as String;
    final deviceLabel = session['deviceLabel'] as String? ?? 'Device';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Revoke Session', style: TextStyle(color: AppTheme.textPrimaryColor)),
        content: Text(
          'Are you sure you want to revoke access for "$deviceLabel"? The device will be logged out immediately.',
          style: const TextStyle(color: AppTheme.textSecondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
          ),
          ElevatedButton(
            key: const Key('confirm-revoke-dialog-btn'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _authClient.revokeSession(widget.jwtToken, sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session for "$deviceLabel" revoked successfully.')),
        );
      }
      _fetchSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to revoke session: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  IconData _getDeviceIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('ios') || l.contains('android') || l.contains('iphone') || l.contains('phone')) {
      return Icons.smartphone;
    }
    if (l.contains('chrome') || l.contains('firefox') || l.contains('safari') || l.contains('edge') || l.contains('web')) {
      return Icons.language;
    }
    return Icons.desktop_windows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Devices & Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSessions,
            tooltip: 'Refresh Sessions',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 48),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textPrimaryColor)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchSessions,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sessions.isEmpty
                  ? const Center(
                      child: Text('No active sessions found.', style: TextStyle(color: AppTheme.textSecondaryColor)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final s = _sessions[index];
                        final isCurrent = s['isCurrent'] == true;
                        final deviceLabel = s['deviceLabel'] as String? ?? 'Unknown Device';
                        final loginMethod = s['loginMethod'] as String? ?? 'Standard';
                        final createdAtRaw = s['createdAt'] as String?;
                        final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw)?.toLocal().toString().substring(0, 16) ?? createdAtRaw : 'Unknown';

                        return Card(
                          key: Key('session-card-${s['id']}'),
                          color: AppTheme.surfaceColor,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isCurrent ? AppTheme.primaryColor.withValues(alpha: 0.5) : Colors.white10,
                              width: isCurrent ? 1.5 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: isCurrent ? AppTheme.primaryColor.withValues(alpha: 0.2) : Colors.white10,
                              child: Icon(
                                _getDeviceIcon(deviceLabel),
                                color: isCurrent ? AppTheme.primaryColor : Colors.white70,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    deviceLabel,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppTheme.primaryColor, width: 1),
                                    ),
                                    child: const Text(
                                      'This Device',
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Method: $loginMethod',
                                    style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12),
                                  ),
                                  Text(
                                    'Logged in: $createdAt',
                                    style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            trailing: isCurrent
                                ? const Tooltip(
                                    message: 'Current active session (Use Logout to end)',
                                    child: Icon(Icons.lock_outline, color: Colors.grey),
                                  )
                                : ElevatedButton(
                                    key: Key('revoke-btn-${s['id']}'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.errorColor.withValues(alpha: 0.15),
                                      foregroundColor: AppTheme.errorColor,
                                      elevation: 0,
                                      side: const BorderSide(color: AppTheme.errorColor),
                                    ),
                                    onPressed: () => _handleRevoke(s),
                                    child: const Text('Revoke'),
                                  ),
                          ),
                        );
                      },
                    ),
    );
  }
}
