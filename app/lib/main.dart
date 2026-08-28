import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/app.dart';
import 'package:lifedna/core/theme/ld_colors.dart';

/// LifeDNA OS — Your Personal Performance Operating System.
///
/// This entry point runs the app against the in-memory reference dataset so
/// it is fully operable without a Firebase project. Wiring the production data
/// layer is a matter of overriding two providers — `nutritionRepositoryProvider`
/// and `workoutRepositoryProvider` — with their Firestore/Drift
/// implementations. Nothing above the repository interfaces changes.
/// See app/README.md.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set before the first frame, so there is no flash of a light system bar
  // ahead of the theme being applied.
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: LdColors.dark.bg,
    ),
  );

  runApp(const ProviderScope(child: LifeDnaApp()));
}
