import 'package:flutter/material.dart';

import 'auth_sheet.dart';
import 'session.dart';

const _ink = Color(0xFF1B2340);
const _accent = Color(0xFF4C6FFF);

/// Profile. Logged-out visitors see Log in and Sign up.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                color: _ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 28),
            if (session.isSignedIn) ...[
              Text(
                session.displayName ?? '',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 28),
              _AuthPill(
                label: 'Logout',
                filled: false,
                onTap: () => AppSession.instance.signOut(),
              ),
            ] else ...[
              _AuthPill(
                label: 'Log in',
                filled: false,
                onTap: () => showAuthSheet(context, signUp: false),
              ),
              const SizedBox(height: 12),
              _AuthPill(
                label: 'Sign up',
                filled: true,
                onTap: () => showAuthSheet(context, signUp: true),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AuthPill extends StatelessWidget {
  const _AuthPill({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _accent : Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
