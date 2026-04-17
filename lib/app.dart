import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

class LoanApp extends ConsumerWidget {
  const LoanApp({
    super.key,
    this.initializationError,
  });

  final Object? initializationError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final baseTextTheme = Typography.material2021().black;
    const seedColor = Color(0xFFE46A11);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      primary: const Color(0xFFE46A11),
      secondary: const Color(0xFFFFA145),
      surface: Colors.white,
    );

    return MaterialApp(
      title: 'Money Now',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        textTheme: baseTextTheme.copyWith(
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.1,
            fontFamilyFallback: const ['SF Pro Display', 'Segoe UI', 'Roboto'],
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            fontFamilyFallback: const ['SF Pro Display', 'Segoe UI', 'Roboto'],
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFamilyFallback: const ['SF Pro Display', 'Segoe UI', 'Roboto'],
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFamilyFallback: const ['SF Pro Text', 'Segoe UI', 'Roboto'],
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            height: 1.45,
            fontFamilyFallback: const ['SF Pro Text', 'Segoe UI', 'Roboto'],
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            height: 1.45,
            fontFamilyFallback: const ['SF Pro Text', 'Segoe UI', 'Roboto'],
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            fontFamilyFallback: const ['SF Pro Text', 'Segoe UI', 'Roboto'],
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF12343B),
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Color(0xFF12343B),
            fontFamilyFallback: ['SF Pro Display', 'Segoe UI', 'Roboto'],
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: const Color(0xFFE46A11).withValues(alpha: 0.08)),
          ),
        ),
        dividerColor: const Color(0xFFE3EAF2),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFamilyFallback: ['SF Pro Text', 'Segoe UI', 'Roboto'],
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF12343B),
            side:
                BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide(color: Color(0xFFD7E3EE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide(color: Color(0xFFE46A11), width: 1.4),
          ),
          alignLabelWithHint: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          helperStyle: TextStyle(color: Color(0xFF6B7A90)),
        ),
      ),
      home: initializationError != null
          ? FirebaseSetupScreen(errorText: initializationError.toString())
          : authState.when(
              data: (user) {
                if (user == null) {
                  return const LoginScreen();
                }
                return const HomeScreen();
              },
              loading: () => const SplashScreen(),
              error: (error, _) => FirebaseSetupScreen(
                errorText: error.toString(),
              ),
            ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF1E6),
              Color(0xFFFFF8F2),
              Color(0xFFFFE6D5),
            ],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE46A11), Color(0xFFFFA145)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE46A11).withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Money Now',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF12343B),
                      ),
                ),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({
    super.key,
    required this.errorText,
  });

  final String errorText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chưa cấu hình Firebase'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                const Text(
                  'Dự án này đang dùng file `firebase_options.dart` tạm thời.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Các bước cần làm:',
                ),
                const SizedBox(height: 8),
                const Text(
                    '1. flutter create . --platforms=android,ios,web --overwrite'),
                const Text('2. flutter pub get'),
                const Text('3. flutterfire configure'),
                const Text('4. firebase use --add'),
                const Text('5. cd functions && npm install && npm run build'),
                const Text(
                    '6. firebase deploy --only firestore,storage,functions'),
                const SizedBox(height: 16),
                Text(
                  'Chi tiết lỗi khởi tạo: $errorText',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
