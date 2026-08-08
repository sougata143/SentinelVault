import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';

/// Data class representing a user's vault envelope in UI state.
class UserVaultInfo {
  final String id;
  final String name;
  final String salt;
  final String wrappedKey;
  final bool isDefault;
  final bool isUnlocked;

  const UserVaultInfo({
    required this.id,
    required this.name,
    required this.salt,
    required this.wrappedKey,
    required this.isDefault,
    required this.isUnlocked,
  });
}

/// Interactive Vault Switcher dropdown/dialog component.
class VaultSwitcher extends StatefulWidget {
  final String activeVaultId;
  final List<UserVaultInfo> vaults;
  final ValueChanged<UserVaultInfo> onSelectVault;
  final VoidCallback onCreateVault;

  const VaultSwitcher({
    super.key,
    required this.activeVaultId,
    required this.vaults,
    required this.onSelectVault,
    required this.onCreateVault,
  });

  @override
  State<VaultSwitcher> createState() => _VaultSwitcherState();
}

class _VaultSwitcherState extends State<VaultSwitcher> {
  UserVaultInfo get _activeVault {
    return widget.vaults.firstWhere(
      (v) => v.id == widget.activeVaultId,
      orElse: () => widget.vaults.isNotEmpty
          ? widget.vaults.first
          : const UserVaultInfo(
              id: 'default',
              name: 'Personal Vault',
              salt: '',
              wrappedKey: '',
              isDefault: true,
              isUnlocked: true,
            ),
    );
  }

  void _showSwitcherSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SentinelTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: SentinelTheme.accentCyan),
                    const SizedBox(width: 8),
                    const Text(
                      'Your Vaults',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: SentinelTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: SentinelTheme.textMuted),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: SentinelTheme.borderDark),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.vaults.length,
                    itemBuilder: (context, index) {
                      final vault = widget.vaults[index];
                      final isSelected = vault.id == widget.activeVaultId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? SentinelTheme.accentCyan.withOpacity(0.12)
                              : SentinelTheme.cardDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? SentinelTheme.accentCyan
                                : SentinelTheme.borderDark,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            vault.isUnlocked ? Icons.lock_open : Icons.lock_outline,
                            color: vault.isUnlocked
                                ? SentinelTheme.accentCyan
                                : SentinelTheme.warningYellow,
                          ),
                          title: Text(
                            vault.name,
                            style: const TextStyle(
                              color: SentinelTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            vault.isUnlocked ? 'Unlocked' : 'Locked — Tap to enter password',
                            style: TextStyle(
                              color: vault.isUnlocked
                                  ? SentinelTheme.accentCyan
                                  : SentinelTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: SentinelTheme.accentCyan)
                              : null,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            widget.onSelectVault(vault);
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      widget.onCreateVault();
                    },
                    icon: const Icon(Icons.add, color: SentinelTheme.accentCyan),
                    label: const Text(
                      'Create New Vault',
                      style: TextStyle(color: SentinelTheme.accentCyan, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: SentinelTheme.accentCyan),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showSwitcherSheet(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SentinelTheme.surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SentinelTheme.borderDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _activeVault.isUnlocked ? Icons.lock_open : Icons.lock,
              size: 16,
              color: _activeVault.isUnlocked
                  ? SentinelTheme.accentCyan
                  : SentinelTheme.warningYellow,
            ),
            const SizedBox(width: 6),
            Text(
              _activeVault.name,
              style: const TextStyle(
                color: SentinelTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: SentinelTheme.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
