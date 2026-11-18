// PLACEHOLDER. Replace by running, in this folder:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// That command creates your Firebase app config and overwrites this file.
// See README.md → "Connect Firebase".

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
    'Firebase is not set up yet. Run `flutterfire configure` (see README.md).',
  );
}
