import '../../../../core/enums/user_role.dart';
import '../entities/app_user.dart';

class RegisterInput {
  const RegisterInput({
    required this.role,
    required this.name,
    required this.email,
    required this.password,
    this.phone,
    this.referralCode,
  });

  final UserRole role;
  final String name;
  final String email;
  final String password;
  final String? phone;
  final String? referralCode;
}

abstract interface class AuthRepository {
  /// Returns the signed-in user, or null if there is no valid session.
  /// Throws ApiException when the server can't be reached.
  Future<AppUser?> restoreSession();

  Future<AppUser> login({required String email, required String password});

  Future<AppUser> register(RegisterInput input);

  /// Throws [GoogleSignInCancelled] when the user closes the Google sheet.
  Future<AppUser> signInWithGoogle({UserRole? role, String? referralCode});

  Future<AppUser> fetchCurrentUser();

  Future<AppUser> upgradeRole(UserRole role, {String? name});

  /// Returns the server's confirmation message.
  Future<String> forgotPassword(String email);

  /// Sets a new password with the token from the reset email.
  Future<String> resetPassword({required String token, required String newPassword});

  Future<void> logout();
}

class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}
