import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/storage/token_storage.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/auth_session.dart';
import '../services/google_auth_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required TokenStorage tokens,
    required GoogleAuthService google,
  })  : _remote = remote,
        _tokens = tokens,
        _google = google;

  final AuthRemoteDataSource _remote;
  final TokenStorage _tokens;
  final GoogleAuthService _google;

  @override
  Future<AppUser?> restoreSession() async {
    if (await _tokens.accessToken == null) return null;
    try {
      return await _remote.getMe();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<AppUser> login({required String email, required String password}) async {
    final session = await _remote.login(email: email, password: password);
    return _persist(session);
  }

  @override
  Future<AppUser> register(RegisterInput input) async {
    final session = await _remote.register(input);
    final user = await _persist(session);
    // Fans have nothing else to set up — mark sign-up as finished so the
    // app doesn't ask them to pick an account type again.
    if (user.role == UserRole.fan && !user.onboardingCompleted) return _remote.completeOnboarding();
    return user;
  }

  @override
  Future<AppUser> signInWithGoogle({UserRole? role, String? referralCode}) async {
    final idToken = await _google.getIdToken();
    try {
      final session = await _remote.google(idToken: idToken, role: role, referralCode: referralCode);
      final user = await _persist(session);
      // Chose "Fan" on the sign-up screen → finish sign-up now.
      if (role == UserRole.fan && user.role == UserRole.fan && !user.onboardingCompleted) {
        return _remote.completeOnboarding();
      }
      return user;
    } finally {
      await _google.signOut();
    }
  }

  @override
  Future<AppUser> fetchCurrentUser() => _remote.getMe();

  @override
  Future<AppUser> upgradeRole(UserRole role, {String? name}) => _remote.upgradeRole(role, name: name);

  @override
  Future<AppUser> completeOnboarding() => _remote.completeOnboarding();

  @override
  Future<String> forgotPassword(String email) => _remote.forgotPassword(email);

  @override
  Future<String> resetPassword({required String token, required String newPassword}) =>
      _remote.resetPassword(token: token, newPassword: newPassword);

  @override
  Future<void> logout() async {
    try {
      await _remote.logout();
    } catch (_) {
      // Logging out must always succeed locally.
    }
    await _tokens.clear();
    await _google.signOut();
  }

  Future<AppUser> _persist(AuthSession session) async {
    await _tokens.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
    return session.user;
  }
}