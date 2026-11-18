// Firebase settings for the "investmetric" project.
// Generated from android/app/google-services.json. These values are meant to
// ship inside the app; access to data is protected by firestore.rules.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'Firebase is only set up for Android so far. Add an iOS app in the '
      'Firebase console and run `flutterfire configure` to support iPhone.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDCTmeoFl5BNkzm0rs08RGfnXAatqusGdI',
    appId: '1:168978417222:android:6fc8fc231896ea4ba5ac47',
    messagingSenderId: '168978417222',
    projectId: 'investmetric',
    storageBucket: 'investmetric.firebasestorage.app',
  );
}
