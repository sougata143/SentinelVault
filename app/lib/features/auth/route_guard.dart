import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';
import 'unlock_screen.dart';
import '../../theme/theme.dart';

/// Root route guard that enforces the correct auth/unlock flow.
///
/// Routing logic:
/// - No session → Login screen (with Sign up link)
/// - Valid session, vault locked → Unlock screen
/// - Valid session, vault already unlocked → Dashboard (AppShell)
class RouteGuard extends StatefulWidget {
  final http.Client? httpClient;
  final String syncBaseUrl;
  final String authBaseUrl;

  const RouteGuard({
    super.key,
    this.httpClient,
    this.syncBaseUrl = 'http://localhost:3002',
    this.authBaseUrl = 'http://localhost:3001',
  });

  @override
  State<RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends State<RouteGuard> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isLocked = true;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    // Session is already loaded in main.dart via VaultLockManager.instance.loadSession()
    // We just need to check the current state
    final isLoggedIn = VaultLockManager.instance.isLoggedIn;
    final isLocked = VaultLockManager.instance.isLocked;

    setState(() {
      _isLoggedIn = isLoggedIn;
      _isLocked = isLocked;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (!_isLoggedIn) {
      // No session → Login screen
      return LoginScreen(
        authClient: AuthClient(baseUrl: widget.authBaseUrl),
      );
    }

    if (_isLocked) {
      // Valid session, vault locked → Unlock screen
      // We need the email for UnlockScreen - for now use a placeholder
      // In production, this should be stored in session or fetched from user profile
      return UnlockScreen(
        email: 'user@example.com', // TODO: Get from session/user profile
        authClient: AuthClient(baseUrl: widget.authBaseUrl),
        syncBaseUrl: widget.syncBaseUrl,
        httpClient: widget.httpClient ?? http.Client(),
      );
    }

    // Valid session, vault unlocked → Dashboard
    // This case shouldn't normally happen on cold start since vault keys are memory-only
    // But it handles the case where the user hasn't locked the vault yet
    return const _VaultLockedPlaceholder();
  }
}

/// Placeholder shown when vault is already unlocked (rare on cold start).
/// In production, this would navigate to AppShell with the actual vault key.
class _VaultLockedPlaceholder extends StatelessWidget {
  const _VaultLockedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_open, color: AppTheme.primaryColor, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Vault is already unlocked',
              style: TextStyle(
                color: AppTheme.textPrimaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This should not happen on cold start.',
              style: TextStyle(color: AppTheme.textSecondaryColor),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                VaultLockManager.instance.lock();
                // Reload the app to trigger the guard again
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RouteGuard()),
                );
              },
              child: const Text('Lock Vault'),
            ),
          ],
        ),
      ),
    );
  }
}
