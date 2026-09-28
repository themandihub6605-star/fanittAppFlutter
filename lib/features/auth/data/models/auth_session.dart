import '../../domain/entities/app_user.dart';
import 'user_model.dart';

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    this.refreshToken,
    this.isNewUser = false,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      isNewUser: json['isNewUser'] as bool? ?? false,
    );
  }

  final AppUser user;
  final String accessToken;
  final String? refreshToken;
  final bool isNewUser;
}
