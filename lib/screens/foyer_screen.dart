import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class FoyerScreen extends StatelessWidget {
  const FoyerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(32), child: Image.asset('assets/icon2.png', height: 150)),
              const SizedBox(height: 24),
              const Text(
                'Braid',
                style: TextStyle(
                  fontSize: 48,
                  fontFamily: 'Comfortaa',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Where faith meets fellowship',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textMuted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 64),
              ElevatedButton.icon(
                onPressed: () async {
                  final authService = AuthService();
                  await authService.signInWithGoogle();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gradientEnd,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.login),
                label: const Text('Continue with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


