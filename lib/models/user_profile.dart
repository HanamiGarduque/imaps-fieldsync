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


  bool get isAdmin => role == 'admin';
  bool get isInspector => role == 'inspector';
}