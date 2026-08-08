import 'dart:convert';

/// Role permissions inside a Team or Family Shared Vault.
enum SharedVaultRole {
  admin,
  member,
  viewer;

  String toValue() => name;

  static SharedVaultRole fromValue(String value) {
    switch (value.toLowerCase()) {
      case 'admin':
        return SharedVaultRole.admin;
      case 'member':
        return SharedVaultRole.member;
      case 'viewer':
      default:
        return SharedVaultRole.viewer;
    }
  }

  bool get canManageMembers => this == SharedVaultRole.admin;
  bool get canWriteItems => this == SharedVaultRole.admin || this == SharedVaultRole.member;
  bool get canRotateKeys => this == SharedVaultRole.admin;
}

/// Participant membership entry in a Team/Family Shared Vault.
class SharedVaultMember {
  final String userId;
  final SharedVaultRole role;
  final String status; // 'pending' | 'accepted' | 'declined'
  final int keyVersion;
  final String? wrappedKeyPayload;

  const SharedVaultMember({
    required this.userId,
    required this.role,
    this.status = 'pending',
    this.keyVersion = 1,
    this.wrappedKeyPayload,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'role': role.toValue(),
        'status': status,
        'keyVersion': keyVersion,
        if (wrappedKeyPayload != null) 'wrappedKeyPayload': wrappedKeyPayload,
      };

  factory SharedVaultMember.fromJson(Map<String, dynamic> json) {
    return SharedVaultMember(
      userId: json['userId'] as String,
      role: SharedVaultRole.fromValue(json['role'] as String? ?? 'viewer'),
      status: json['status'] as String? ?? 'pending',
      keyVersion: json['keyVersion'] as int? ?? 1,
      wrappedKeyPayload: json['wrappedKeyPayload'] as String?,
    );
  }
}

/// Team / Family Shared Vault model.
class SharedVault {
  final String vaultId;
  final String name;
  final String ownerUserId;
  final int keyVersion;
  final List<SharedVaultMember> members;
  final DateTime createdAt;

  const SharedVault({
    required this.vaultId,
    required this.name,
    required this.ownerUserId,
    this.keyVersion = 1,
    required this.members,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'vaultId': vaultId,
        'name': name,
        'ownerUserId': ownerUserId,
        'keyVersion': keyVersion,
        'members': members.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory SharedVault.fromJson(Map<String, dynamic> json) {
    return SharedVault(
      vaultId: json['vaultId'] as String,
      name: json['name'] as String,
      ownerUserId: json['ownerUserId'] as String,
      keyVersion: json['keyVersion'] as int? ?? 1,
      members: (json['members'] as List<dynamic>? ?? [])
          .map((m) => SharedVaultMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
