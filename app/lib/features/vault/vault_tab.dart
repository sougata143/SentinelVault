import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';
import 'item_editor.dart';
import 'item_detail.dart';
import 'import_export/import_screen.dart';
import 'import_export/export_screen.dart';

class VaultTab extends StatefulWidget {
  final VaultDatabase db;
  final List<int> vaultKey;

  const VaultTab({
    super.key,
    required this.db,
    required this.vaultKey,
  });

  @override
  State<VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<VaultTab> {
  // Navigation Sidebar filter state
  String _selectedCategory = 'all'; // all, login, credit_card, identity, secure_note, bank_account, password, favorites, trash
  String? _selectedTag;
  
  // Search, filter, and sort state
  String _searchQuery = '';
  String _sortBy = 'title'; // title, updated
  bool _ascending = true;

  List<EncryptedVaultItem> _dbItems = [];
  List<VaultItem> _decryptedItems = [];
  VaultItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final encItems = widget.db.getAllItems();
    final List<VaultItem> decrypted = [];

    for (final item in encItems) {
      if (item.isDeleted && _selectedCategory != 'trash') continue;
      try {
        final dec = await VaultItem.decrypt(item, widget.vaultKey, VaultCrypto());
        decrypted.add(dec);
      } catch (_) {
        // Skip un-decryptable items
      }
    }

    setState(() {
      _dbItems = encItems;
      _decryptedItems = decrypted;
      
      // Select the first item by default on desktop if list is not empty
      if (_selectedItem != null) {
        final index = _decryptedItems.indexWhere((it) => it.id == _selectedItem!.id);
        if (index != -1) {
          _selectedItem = _decryptedItems[index];
        } else {
          _selectedItem = null;
        }
      }
    });
  }

  List<VaultItem> _getFilteredAndSortedItems() {
    // 1. Filter by category
    var items = _decryptedItems.where((item) {
      if (_selectedCategory == 'favorites') {
        return item.favorite;
      }
      if (_selectedCategory == 'trash') {
        // Handled at loading level (isDeleted check matches database status)
        return true;
      }
      if (_selectedCategory != 'all') {
        return item.type.toValue() == _selectedCategory;
      }
      return true;
    }).toList();

    // 2. Filter by search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((it) {
        final titleMatch = it.title.toLowerCase().contains(q);
        final tagMatch = it.tags.any((t) => t.toLowerCase().contains(q));
        return titleMatch || tagMatch;
      }).toList();
    }

    // 3. Sort
    items.sort((a, b) {
      int result = 0;
      if (_sortBy == 'title') {
        result = a.title.compareTo(b.title);
      } else {
        result = a.updatedAt.compareTo(b.updatedAt);
      }
      return _ascending ? result : -result;
    });

    return items;
  }

  void _openItemEditor([VaultItem? item]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemEditorScreen(
          item: item,
          vaultKey: widget.vaultKey,
          db: widget.db,
          onSave: (encryptedItem) {
            if (item == null) {
              widget.db.insertItem(encryptedItem);
            } else {
              widget.db.updateItem(encryptedItem);
            }
            _loadItems();
          },
        ),
      ),
    );
  }

  void _deleteItem(String id) {
    widget.db.softDeleteItem(id);
    _loadItems();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item deleted locally')),
    );
  }

  void _triggerImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportScreen(
          vaultKey: widget.vaultKey,
          db: widget.db,
        ),
      ),
    ).then((_) => _loadItems()); // Reload vault after import completes
  }

  void _triggerExport() {
    // Placeholder salt — in production this is loaded from local secure storage
    // alongside the wrapped vault key. The salt is never the key itself.
    final placeholderSalt = List<int>.filled(16, 0);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          vaultKey: widget.vaultKey,
          db: widget.db,
          masterKeySalt: placeholderSalt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _getFilteredAndSortedItems();
    final isLargeScreen = MediaQuery.of(context).size.width >= 900;

    if (isLargeScreen) {
      return Scaffold(
        body: Row(
          children: [
            // Column 1: Sidebar
            SizedBox(
              width: 240,
              child: _buildSidebar(),
            ),
            const VerticalDivider(width: 1, color: Colors.white10),

            // Column 2: List view
            SizedBox(
              width: 340,
              child: _buildItemListSection(filteredItems, false),
            ),
            const VerticalDivider(width: 1, color: Colors.white10),

            // Column 3: Detail view
            Expanded(
              child: ItemDetailPane(
                item: _selectedItem,
                onEdit: _selectedItem == null ? null : () => _openItemEditor(_selectedItem),
                onDelete: _selectedItem == null ? null : () => _deleteItem(_selectedItem!.id),
              ),
            ),
          ],
        ),
      );
    }

    // Mobile View (List view with category drawer)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadItems),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: AppTheme.backgroundColor),
              child: Center(
                child: Text(
                  'Vault Categories',
                  style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(child: _buildSidebarList()),
          ],
        ),
      ),
      body: _buildItemListSection(filteredItems, true),
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: AppTheme.backgroundColor,
      child: Column(
        children: [
          // Logo or Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'SentinelVault',
                    style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          // Wrap the sidebar list in a Material so that ListTile's
          // selectedTileColor ink-splash renderer has a Material ancestor.
          // Container(color:…) compiles to a ColoredBox which is NOT a
          // Material, causing a Flutter debug assertion.
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: _buildSidebarList(),
            ),
          ),
          const Divider(color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimaryColor,
                      side: const BorderSide(color: Colors.white10),
                    ),
                    onPressed: _triggerImport,
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('Import', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimaryColor,
                      side: const BorderSide(color: Colors.white10),
                    ),
                    onPressed: _triggerExport,
                    icon: const Icon(Icons.upload, size: 14),
                    label: const Text('Export', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _buildSidebarTile('all', 'All Items', Icons.all_inclusive),
        const Divider(color: Colors.white10),
        _buildSidebarTile('login', 'Logins', Icons.language),
        _buildSidebarTile('credit_card', 'Credit Cards', Icons.credit_card),
        _buildSidebarTile('identity', 'Identities', Icons.person_outline),
        _buildSidebarTile('secure_note', 'Secure Notes', Icons.note_outlined),
        _buildSidebarTile('bank_account', 'Bank Accounts', Icons.account_balance_outlined),
        _buildSidebarTile('password', 'Passwords', Icons.vpn_key_outlined),
        const Divider(color: Colors.white10),
        _buildSidebarTile('favorites', 'Favorites', Icons.star_border),
        _buildSidebarTile('trash', 'Trash', Icons.delete_outline),
      ],
    );
  }

  Widget _buildSidebarTile(String cat, String label, IconData icon) {
    final isSelected = _selectedCategory == cat;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondaryColor, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.textPrimaryColor : AppTheme.textSecondaryColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: isSelected,
      selectedTileColor: AppTheme.primaryColor.withOpacity(0.08),
      onTap: () {
        setState(() {
          _selectedCategory = cat;
          _selectedItem = null;
        });
        _loadItems();
        // Close drawer on mobile
        if (Scaffold.of(context).isDrawerOpen) {
          Navigator.pop(context);
        }
      },
    );
  }

  Widget _buildItemListSection(List<VaultItem> items, bool isMobile) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Search & Sort bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: const InputDecoration(
                    hintText: 'Search title or tags...',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    DropdownButton<String>(
                      value: _sortBy,
                      dropdownColor: AppTheme.surfaceColor,
                      items: const [
                        DropdownMenuItem(value: 'title', child: Text('Sort by Title', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'updated', child: Text('Sort by Date', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _sortBy = val);
                      },
                    ),
                    IconButton(
                      icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                      onPressed: () => setState(() => _ascending = !_ascending),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No matching items', style: TextStyle(color: AppTheme.textSecondaryColor)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = _selectedItem?.id == item.id;
                      
                      return Card(
                        color: isSelected ? AppTheme.primaryColor.withOpacity(0.12) : AppTheme.surfaceColor,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? AppTheme.primaryColor : Colors.white.withOpacity(0.05),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(item.type.toValue().toUpperCase(), style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                          trailing: const Icon(Icons.chevron_right, size: 16, color: AppTheme.textSecondaryColor),
                          onTap: () {
                            if (isMobile) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(),
                                    body: ItemDetailPane(
                                      item: item,
                                      onEdit: () => _openItemEditor(item),
                                      onDelete: () => _deleteItem(item.id),
                                    ),
                                  ),
                                ),
                              ).then((_) => _loadItems());
                            } else {
                              setState(() {
                                _selectedItem = item;
                              });
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _openItemEditor(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
