// File: lib/features/auth/data/services/google_auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';

/// Google sign-in with the phone's own account picker — a popup on the same
/// screen listing the Google accounts on the device. No browser window and no
/// Firebase link is shown. The picked account is exchanged for a Firebase ID
/// token, which the backend verifies with firebase-admin (unchanged).
class GoogleAuthService {
  GoogleAuthService(this._auth);

  final FirebaseAuth _auth;
  final GoogleSignIn _google = GoogleSignIn(scopes: const ['email']);

  Future<String> getIdToken() async {
    try {
      // Forget the last pick so the account list always shows.
      try {
        await _google.signOut();
      } catch (_) {}

      final account = await _google.signIn();
      if (account == null) throw const GoogleSignInCancelled();

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException('Google sign-in failed. Please try again.');
      }

      final result = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken, accessToken: auth.accessToken),
      );
      final token = await result.user?.getIdToken();
      if (token == null) throw const GoogleSignInCancelled();
      return token;
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase();
      final details = '${error.message ?? ''} ${error.details ?? ''}';
      if (code.contains('cancel')) throw const GoogleSignInCancelled();
      if (code.contains('network')) {
        throw const ApiException.network('No internet connection. Check your network and try again.');
      }
      // ApiException: 10 = this build's SHA-1 isn't added in Firebase.
      if (details.contains('ApiException: 10') || details.contains(': 10:')) {
        throw const ApiException('Google sign-in isn’t set up for this app build yet. Please use email for now.');
      }
      throw ApiException(error.message ?? 'Google sign-in failed. Please try again.');
    } on FirebaseAuthException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('cancel')) throw const GoogleSignInCancelled();
      if (code == 'network-request-failed') {
        throw const ApiException.network('No internet connection. Check your network and try again.');
      }
      throw ApiException(error.message ?? 'Google sign-in failed. Please try again.');
    }
  }

  /// We only need Firebase to mint the ID token; the Fanitt backend owns the
  /// session, so both Google and Firebase sessions are cleared.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    try {
      await _google.signOut();
    } catch (_) {}
  }
}
