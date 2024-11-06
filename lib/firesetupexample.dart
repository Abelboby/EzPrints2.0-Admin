//the file that is generated by the FlutterFire CLI
//the file name is firebase_options.dart
//maker sure to add the original file by using the FlutterFire CLI
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for android',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos',
        );
      case TargetPlatform.windows:
        return getWindowsOptions();
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions getWindowsOptions() {
    // Check for required environment variables
    final apiKey = dotenv.env['FIREBASE_API_KEY'] ?? 
        const String.fromEnvironment('FIREBASE_API_KEY');
    final appId = dotenv.env['FIREBASE_APP_ID'] ?? 
        const String.fromEnvironment('FIREBASE_APP_ID');
    final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? 
        const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    final projectId = dotenv.env['FIREBASE_PROJECT_ID'] ?? 
        const String.fromEnvironment('FIREBASE_PROJECT_ID');
    final authDomain = dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? 
        const String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? 
        const String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    final measurementId = dotenv.env['FIREBASE_MEASUREMENT_ID'] ?? 
        const String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

    // Validate required values
    if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) {
      throw Exception(
        'Firebase configuration missing. Please ensure all required environment variables are set.',
      );
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain,
      storageBucket: storageBucket,
      measurementId: measurementId,
    );
  }
}