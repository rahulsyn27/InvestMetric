import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Optional: the "Web client" OAuth ID from Firebase console → Authentication
/// → Sign-in method → Google → Web SDK configuration. Usually not needed when
/// google-services.json is present, but some devices require it.
const String? kGoogleServerClientId = null;

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;
  bool _initialised = false;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> _init() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: kGoogleServerClientId,
    );
    _initialised = true;
  }

  /// Shows the Google account picker and signs in to Firebase.
  Future<UserCredential> signInWithGoogle() async {
    await _init();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return a sign-in token.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
