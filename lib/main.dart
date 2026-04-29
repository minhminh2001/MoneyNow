import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'firebase_options.dart';

const _firebaseAppIdPrefsKey = 'firebase_config_app_id';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? initializationError;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final currentAppId = Firebase.app().options.appId;
    final prefs = await SharedPreferences.getInstance();
    final previousAppId = prefs.getString(_firebaseAppIdPrefsKey);

    // If the app was previously connected to a different Firebase app, clear
    // the cached auth session so stale tokens do not break callable requests.
    if (previousAppId != null &&
        previousAppId.isNotEmpty &&
        previousAppId != currentAppId) {
      await FirebaseAuth.instance.signOut();
    }

    await prefs.setString(_firebaseAppIdPrefsKey, currentAppId);
  } catch (error) {
    initializationError = error;
  }

  runApp(
    ProviderScope(
      child: LoanApp(initializationError: initializationError),
    ),
  );
}
