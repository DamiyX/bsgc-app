import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../theme.dart';

const String googleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
  <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
  <path fill="none" d="M0 0h48v48H0z"/>
</svg>
''';

class FoyerScreen extends StatefulWidget {
  const FoyerScreen({super.key});

  @override
  State<FoyerScreen> createState() => _FoyerScreenState();
}

class _FoyerScreenState extends State<FoyerScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(32), child: Image.asset('assets/icon2.png', height: 150)),
              SizedBox(height: 24),
              Text(
                'Braid',
                style: TextStyle(
                  fontSize: 48,
                  fontFamily: 'Comfortaa',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Fellowship beyond Sundays. Weaving believers together.',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 64),
              _isLoading 
                ? CircularProgressIndicator(color: AppColors.gradientEnd)
                : OutlinedButton.icon(
                onPressed: () async {
                  setState(() { _isLoading = true; });
                  final authService = AuthService();
                  final user = await authService.signInWithGoogle();
                  if (user == null && mounted) {
                    // Sign in failed or was canceled
                    setState(() { _isLoading = false; });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign in canceled or failed')),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: SvgPicture.string(googleSvg, width: 24, height: 24),
                label: Text('Continue with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


