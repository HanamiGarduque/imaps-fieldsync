class UserProfile {
  final String id;
  final String fullName;
  final String role; // 'admin' or 'inspector'
  final String? phoneNumber;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.phoneNumber,
    this.avatarUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'],
      fullName: map['full_name'],
      role: map['role'],
      phoneNumber: map['phone_number'] as String?,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isInspector => role == 'inspector';
}