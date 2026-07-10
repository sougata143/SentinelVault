import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'theme/theme.dart';
import 'features/vault/vault_tab.dart';
import 'features/security_center/security_center_tab.dart';
import 'features/settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  final VaultDatabase db;
  final List<int> vaultKey;

  const AppShell({
    super.key,
    required this.db,
    required this.vaultKey,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width >= 900;

    final tabs = [
      VaultTab(db: widget.db, vaultKey: widget.vaultKey),
      SecurityCenterTab(db: widget.db, vaultKey: widget.vaultKey),
    ];


    if (isLargeScreen) {
      // Desktop wide layout: Left nav panel + Page content
      return Scaffold(
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
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
    }

    // Mobile View: App bar with settings + Bottom Navigation Bar
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedTabIndex == 0 ? 'SentinelVault' : 'Security Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
              color: isSelected ? AppTheme.primaryColor.withOpacity(0.1) : Colors.transparent,
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
