import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../widgets/initial_avatar.dart';
import '../widgets/surface_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = context.select<AuthService, String?>((a) => a.fullName) ?? '';
    final user = context.select<AuthService, String?>((a) => a.user) ?? '';
    final shownName = name.isEmpty ? user : name;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              InitialAvatar(text: shownName, size: 80),
              const SizedBox(height: 16),
              Text(
                shownName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (user.isNotEmpty && user != shownName) ...[
                const SizedBox(height: 4),
                Text(
                  user,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () => context.read<AuthService>().logout(),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
