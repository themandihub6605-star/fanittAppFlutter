enum UserRole {
  fan('fan'),
  creator('creator'),
  brand('brand'),
  agency('agency'),
  admin('admin');

  const UserRole(this.value);

  final String value;

  static UserRole fromValue(String? value) =>
      UserRole.values.firstWhere((role) => role.value == value, orElse: () => UserRole.fan);

  /// Roles this mobile app is built for.
  static const List<UserRole> appRoles = [UserRole.creator, UserRole.brand, UserRole.agency];

  bool get isAppRole => appRoles.contains(this);

  String get label => switch (this) {
        UserRole.fan => 'Fan',
        UserRole.creator => 'Creator',
        UserRole.brand => 'Brand',
        UserRole.agency => 'Agency',
        UserRole.admin => 'Admin',
      };
}

enum VerificationStatus {
  unverified,
  pending,
  verified,
  rejected;

  static VerificationStatus? fromValue(String? value) {
    if (value == null) return null;
    return VerificationStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => VerificationStatus.unverified,
    );
  }

  bool get blocksAccess => this == VerificationStatus.pending || this == VerificationStatus.rejected;

  String get label => switch (this) {
        VerificationStatus.unverified => 'Not verified',
        VerificationStatus.pending => 'Under review',
        VerificationStatus.verified => 'Verified',
        VerificationStatus.rejected => 'Not approved',
      };
}
