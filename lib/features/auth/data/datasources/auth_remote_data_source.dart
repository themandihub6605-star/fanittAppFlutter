import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/auth_session.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._api);

  final ApiClient _api;

  static AuthSession _session(dynamic data) => AuthSession.fromJson(data as Map<String, dynamic>);
  static AppUser _user(dynamic data) => UserModel.fromJson(data as Map<String, dynamic>);

  Future<AuthSession> login({required String email, required String password}) async {
    final response = await _api.post(
      ApiEndpoints.login,
      data: {'email': email, 'password': password},
      skipAuth: true,
      parser: _session,
    );
    return response.data;
  }

  Future<AuthSession> register(RegisterInput input) async {
    final response = await _api.post(
      ApiEndpoints.register,
      data: {
        'name': input.name,
        'email': input.email,
        'password': input.password,
        'role': input.role.value,
        if (input.phone != null) 'phone': input.phone,
        if (input.referralCode != null) 'referralCode': input.referralCode,
        if (input.otp != null) 'otp': input.otp,
      },
      skipAuth: true,
      parser: _session,
    );
    return response.data;
  }

  Future<AuthSession> google({required String idToken, UserRole? role, String? referralCode}) async {
    final response = await _api.post(
      ApiEndpoints.google,
      data: {
        'idToken': idToken,
        if (role != null) 'role': role.value,
        if (referralCode != null) 'referralCode': referralCode,
      },
      skipAuth: true,
      parser: _session,
    );
    return response.data;
  }

  Future<AppUser> getMe() async => (await _api.get(ApiEndpoints.me, parser: _user)).data;

  Future<AppUser> upgradeRole(UserRole role, {String? name}) async {
    final response = await _api.post(
      ApiEndpoints.upgradeRole,
      data: {'role': role.value, if (name != null) 'name': name},
      parser: _user,
    );
    return response.data;
  }

  /// Marks sign-up as finished (used for fan accounts, which have no
  /// creator/brand/agency profile to create).
  Future<AppUser> completeOnboarding() async =>
      (await _api.post(ApiEndpoints.completeOnboarding, parser: _user)).data;

  Future<String> forgotPassword(String email) async {
    final response = await _api.post(
      ApiEndpoints.forgotPassword,
      data: {'email': email},
      skipAuth: true,
      parser: (_) => null,
    );
    return response.message;
  }

  Future<String> resetPassword({required String token, required String newPassword}) async {
    final response = await _api.post(
      ApiEndpoints.resetPassword,
      data: {'token': token, 'newPassword': newPassword},
      skipAuth: true,
      parser: (_) => null,
    );
    return response.message;
  }

  Future<void> logout() async {
    await _api.post(ApiEndpoints.logout, skipAuth: true, parser: (_) => null);
  }
}