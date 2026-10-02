class UserProfile {
  final String id;
  final String fullName;
  final String role; // 'admin' or 'inspector'
  final String? phoneNumber;
  final String? avatarUrl;
  final String? email;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.phoneNumber,
    this.avatarUrl,
    this.email,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, {String? email}) {
    return UserProfile(
      id: map['id'],
      fullName: map['full_name'],
      role: map['role'],
      phoneNumber: map['phone_number'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      email: email ?? map['email'] as String?,
    );
  }

  /// Returns the complete configured name without abbreviation.
  ///
  /// Outer whitespace is ignored for display, while internal whitespace and
  /// every name token are preserved exactly.
  static String displayFullName(String value) {
    final name = value.trim();
    return name.isEmpty ? 'there' : name;
  }

  /// Avatar initials are intentionally derived independently from the visible
  /// name so retaining a compact avatar never abbreviates the header text.
  static String avatarInitials(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'JR';

    final parts = name.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.first
        .substring(0, parts.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }

  /// Round-trips with fromMap() — used to cache the profile locally
  /// (SecurePrefsService) so a previously-authenticated inspector can keep
  /// working if a later profile refresh fails only because there's no
  /// connectivity, not because the account was actually deactivated.
  Map<String, dynamic> toMap() => {
    'id': id,
    'full_name': fullName,
    'role': role,
    'phone_number': phoneNumber,
    'avatar_url': avatarUrl,
    'email': email,
  };

  bool get isAdmin => role == 'admin';
  bool get isInspector => role == 'inspector';
}
