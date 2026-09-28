import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';

/// Opens the native Google account picker through Firebase and returns a
/// Firebase ID token, which the backend verifies with firebase-admin.
class GoogleAuthService {
  GoogleAuthService(this._auth);

  final FirebaseAuth _auth;

  Future<String> getIdToken() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});

    try {
      final credential = await _auth.signInWithProvider(provider);
      final token = await credential.user?.getIdToken();
      if (token == null) throw const GoogleSignInCancelled();
      return token;
    } on FirebaseAuthException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('cancel') || code == 'web-context-canceled') {
        throw const GoogleSignInCancelled();
      }
      if (code == 'network-request-failed') {
        throw const ApiException.network('No internet connection. Check your network and try again.');
      }
      throw ApiException(error.message ?? 'Google sign-in failed. Please try again.');
    }
  }

  /// We only need Firebase to mint the ID token; the Fanitt backend owns the
  /// session, so the Firebase session is cleared right after.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Nothing to clean up.
    }
  }
}
