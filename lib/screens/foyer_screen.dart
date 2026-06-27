import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class FoyerScreen extends StatelessWidget {
  const FoyerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA), // Off-white minimalist
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'BSGC',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 4.0,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bible Study Group Chat',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 64),
              ElevatedButton.icon(
                onPressed: () async {
                  final authService = AuthService();
                  await authService.signInWithGoogle();
                },
                icon: const Icon(Icons.login),
                label: const Text('Continue with Google'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
