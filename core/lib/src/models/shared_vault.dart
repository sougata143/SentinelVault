/// Role permissions inside a Team or Family Shared Vault.
enum SharedVaultRole {
  /// Admin role: can manage members, rotate keys, and modify items.
  admin,

  /// Member role: can read and write items inside shared vault.
  member,

  /// Viewer role: read-only access to items inside shared vault.
  viewer;

  /// Serializes role enum to string value.
  String toValue() => name;

  /// Deserializes string value to [SharedVaultRole].
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

  /// Returns true if this role is permitted to invite/remove members.
  bool get canManageMembers => this == SharedVaultRole.admin;

  /// Returns true if this role is permitted to write/edit items.
  bool get canWriteItems => this == SharedVaultRole.admin || this == SharedVaultRole.member;

  /// Returns true if this role is permitted to rotate Shared Vault Keys.
  bool get canRotateKeys => this == SharedVaultRole.admin;
}

/// Participant membership entry in a Team/Family Shared Vault.
class SharedVaultMember {
  /// Unique identifier or email of the member.
  final String userId;

  /// Role assigned to this member in the vault.
  final SharedVaultRole role;

  /// Status of membership ('pending', 'accepted', 'declined', 'revoked').
  final String status;

  /// Active key version number associated with member's wrapped key.
  final int keyVersion;

  /// Encrypted/wrapped Shared Vault Key payload for this member.
  final String? wrappedKeyPayload;

  /// Creates a new [SharedVaultMember] instance.
  const SharedVaultMember({
    required this.userId,
    required this.role,
    this.status = 'pending',
    this.keyVersion = 1,
    this.wrappedKeyPayload,
  });

  /// Serializes member object to JSON map.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'role': role.toValue(),
        'status': status,
        'keyVersion': keyVersion,
        if (wrappedKeyPayload != null) 'wrappedKeyPayload': wrappedKeyPayload,
      };

  /// Constructs a [SharedVaultMember] instance from JSON map.
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
  /// Unique identifier of the shared vault.
  final String vaultId;

  /// Human-readable title of the shared vault.
  final String name;

  /// User ID or email of the shared vault owner.
  final String ownerUserId;

  /// Current key version counter for the Shared Vault Key.
  final int keyVersion;

  /// List of members participating in this shared vault.
  final List<SharedVaultMember> members;

  /// Creation timestamp of the shared vault.
  final DateTime createdAt;

  /// Creates a new [SharedVault] instance.
  const SharedVault({
    required this.vaultId,
    required this.name,
    required this.ownerUserId,
    this.keyVersion = 1,
    required this.members,
    required this.createdAt,
  });

  /// Serializes shared vault object to JSON map.
  Map<String, dynamic> toJson() => {
        'vaultId': vaultId,
        'name': name,
        'ownerUserId': ownerUserId,
        'keyVersion': keyVersion,
        'members': members.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  /// Constructs a [SharedVault] instance from JSON map.
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
