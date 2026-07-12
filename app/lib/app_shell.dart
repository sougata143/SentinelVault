import 'dart:async';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import 'theme/theme.dart';
import 'features/vault/vault_tab.dart';
import 'features/security_center/security_center_tab.dart';
import 'features/settings/settings_screen.dart';
import 'features/auth/unlock_screen.dart';
import 'features/auth/login_screen.dart';

class AppShell extends StatefulWidget {
  final VaultDatabase db;
  final List<int> vaultKey;
  final String? currentEmail;
  final AuthClient? authClient;
  final Duration? autoLockTimeoutOverride;
  final String syncBaseUrl;
  final http.Client? httpClient;

  const AppShell({
    super.key,
    required this.db,
    required this.vaultKey,
    this.currentEmail,
    this.authClient,
    this.autoLockTimeoutOverride,
    this.syncBaseUrl = 'http://localhost:3002',
    this.httpClient,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _selectedTabIndex = 0;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _triggerLock();
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (AppSettings.autoLockEnabled) {
      final timeout = widget.autoLockTimeoutOverride ??
          Duration(minutes: AppSettings.autoLockTimeoutMinutes);
      _inactivityTimer = Timer(timeout, _triggerLock);
    }
  }

  void _triggerLock() {
    _inactivityTimer?.cancel();
    VaultLockManager.instance.lock();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => UnlockScreen(
            email: widget.currentEmail ?? 'user@example.com',
            authClient: widget.authClient,
            syncBaseUrl: widget.syncBaseUrl,
            httpClient: widget.httpClient,
          ),
        ),
        (route) => false,
      );
    }
  }

  void _triggerLogout() {
    _inactivityTimer?.cancel();
    VaultLockManager.instance.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            authClient: widget.authClient ?? AuthClient(baseUrl: 'http://localhost:3003'),
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width >= 900;

    final tabs = [
      VaultTab(db: widget.db, vaultKey: widget.vaultKey),
      SecurityCenterTab(db: widget.db, vaultKey: widget.vaultKey),
    ];

    Widget content;

    if (isLargeScreen) {
      // Desktop wide layout: Left nav panel + Page content
      content = Scaffold(
        body: Row(
          children: [
            // Tab switcher sidebar
            Container(
              width: 72,
              color: AppTheme.backgroundColor,
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const CircleAvatar(
                    backgroundColor: AppTheme.surfaceColor,
                    child: Icon(Icons.shield, color: AppTheme.primaryColor, size: 20),
                  ),
                  const SizedBox(height: 40),
                  
                  // Vault tab button
                  _buildTabIconButton(
                    index: 0,
                    icon: Icons.lock_outline,
                    activeIcon: Icons.lock,
                    tooltip: 'Vault',
                  ),
                  const SizedBox(height: 16),
                  
                  // Security Center tab button
                  _buildTabIconButton(
                    index: 1,
                    icon: Icons.shield_outlined,
                    activeIcon: Icons.shield,
                    tooltip: 'Security Center',
                  ),
                  
                  const Spacer(),
                  
                  // Settings button
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondaryColor),
                    tooltip: 'Settings',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                            onLock: _triggerLock,
                            onLogout: _triggerLogout,
                            currentEmail: widget.currentEmail ?? 'auditor@sentinelvault.io',
                            syncBaseUrl: widget.syncBaseUrl,
                            httpClient: widget.httpClient,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            const VerticalDivider(width: 1, color: Colors.white10),
            
            // Core Page Content
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: tabs,
              ),
            ),
          ],
        ),
      );
    } else {
      // Mobile View: App bar with settings + Bottom Navigation Bar
      content = Scaffold(
        appBar: AppBar(
          title: Text(_selectedTabIndex == 0 ? 'SentinelVault' : 'Security Center'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      onLock: _triggerLock,
                      onLogout: _triggerLogout,
                      currentEmail: widget.currentEmail ?? 'auditor@sentinelvault.io',
                      syncBaseUrl: widget.syncBaseUrl,
                      httpClient: widget.httpClient,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _selectedTabIndex,
          children: tabs,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedTabIndex,
          selectedItemColor: AppTheme.primaryColor,
          unselectedItemColor: AppTheme.textSecondaryColor,
          backgroundColor: AppTheme.surfaceColor,
          onTap: (index) {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.lock_outline),
              activeIcon: Icon(Icons.lock),
              label: 'Vault',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield),
              label: 'Security Center',
            ),
          ],
        ),
      );
    }

    return Listener(
      key: const Key('app-shell-root-listener'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      onPointerHover: (_) => _resetInactivityTimer(),
      child: content,
    );
  }

  Widget _buildTabIconButton({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String tooltip,
  }) {
    final isSelected = _selectedTabIndex == index;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondaryColor,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
