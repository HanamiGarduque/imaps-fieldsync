class UserProfile {
  final String id;
  final String fullName;
  final String role; // 'admin' or 'inspector'

  UserProfile({required this.id, required this.fullName, required this.role});

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'],
      fullName: map['full_name'],
      role: map['role'],
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isInspector => role == 'inspector';
}