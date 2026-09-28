import '../../../../core/enums/user_role.dart';
import '../../domain/entities/app_user.dart';

abstract final class UserModel {
  static AppUser fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as List<dynamic>? ?? const [])
        .map((role) => UserRole.fromValue(role as String?))
        .toList(growable: false);

    return AppUser(
      id: (json['_id'] ?? json['id'] ?? '') as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: _nonEmpty(json['phone']),
      avatarUrl: _nonEmpty(json['avatarUrl']),
      role: UserRole.fromValue(json['role'] as String?),
      roles: roles,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      referralCode: _nonEmpty(json['referralCode']),
      walletBalance: (json['walletBalance'] as num?)?.toInt() ?? 0,
      profileStatus: VerificationStatus.fromValue(json['profileStatus'] as String?),
      authProvider: json['authProvider'] as String? ?? 'local',
    );
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
