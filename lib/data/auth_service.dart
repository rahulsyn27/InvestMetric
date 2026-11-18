import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The "Web client" OAuth ID (client_type 3 in google-services.json). Android
/// sign-in asks Google for a token addressed to this id, which Firebase then
/// accepts.
const String kGoogleServerClientId =
    '168978417222-sgnpg9i92q2qe25ppbm309fjgunm4mc5.apps.googleusercontent.com';

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
