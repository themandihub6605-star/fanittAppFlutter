// File: lib/features/auth/data/services/apple_auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';

/// Sign in with Apple through Firebase (iPhone). Returns the Firebase ID token
/// for the backend, plus the person's name when Apple shares it (only the
/// first time someone signs in).
class AppleAuthService {
  AppleAuthService(this._auth);

  final FirebaseAuth _auth;

  Future<({String idToken, String? name})> signIn() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    try {
      final credential = await _auth.signInWithProvider(provider);
      final token = await credential.user?.getIdToken();
      if (token == null) throw const AppleSignInCancelled();
      final profileName = credential.additionalUserInfo?.profile?['name'];
      final name = credential.user?.displayName ?? (profileName is String ? profileName : null);
      return (idToken: token, name: (name == null || name.trim().isEmpty) ? null : name.trim());
    } on FirebaseAuthException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('cancel') || code == '1001' || code == 'web-context-canceled') {
        throw const AppleSignInCancelled();
      }
      if (code == 'network-request-failed') {
        throw const ApiException.network('No internet connection. Check your network and try again.');
      }
      throw ApiException(error.message ?? 'Apple sign-in failed. Please try again.');
    }
  }

  /// Firebase is only used to get the token; Fanitt keeps its own session.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Nothing to clean up.
    }
  }
}