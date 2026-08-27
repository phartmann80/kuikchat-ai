import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/result.dart';
import '../../../domain/personal/entities/user_profile.dart';
import '../../../state/auth_controller.dart';
import '../../../state/providers.dart';

/// Personal settings root. Every entry navigates to a real screen — there
/// are no dead links and no "coming soon" placeholders.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        _SettingsTile(
          icon: LucideIcons.userCircle,
          title: 'Account',
          subtitle: 'Profile, email, sign out',
          builder: (_) => const AccountSettingsScreen(),
        ),
        _SettingsTile(
          icon: LucideIcons.palette,
          title: 'Appearance',
          subtitle: 'Theme',
          builder: (_) => const AppearanceSettingsScreen(),
        ),
        _SettingsTile(
          icon: LucideIcons.info,
          title: 'About',
          subtitle: 'Version, open-source licenses',
          builder: (_) => const AboutSettingsScreen(),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      trailing: const Icon(LucideIcons.chevronRight, size: 18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)),
    );
  }
}

/// Account: shows the real profile from the Personal backend and sign-out.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: FutureBuilder<UserProfile>(
        future: ref.read(personalProfileRepositoryProvider).loadOwnProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final failure = snapshot.error is AppFailure
                ? snapshot.error! as AppFailure
                : const AppFailure(AppFailureKind.unknown);
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.alertTriangle, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      failure.kind == AppFailureKind.network
                          ? 'You are offline. Profile could not be loaded.'
                          : 'Could not load your profile.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          final profile = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    profile.displayName.isEmpty ? '?' : profile.displayName[0].toUpperCase(),
                    style: TextStyle(
                        fontSize: 28,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(profile.displayName,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (profile.about != null && profile.about!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    profile.about!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Sign out?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign out')),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(authControllerProvider.notifier).signOut();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  }
                },
                icon: const Icon(LucideIcons.logOut, size: 16),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Appearance: states the actual behaviour — the app ships dark-only in
/// this milestone. No fake toggles.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(LucideIcons.moon, color: theme.colorScheme.primary),
            title: const Text('Theme'),
            subtitle: Text(
              'KuikChat currently uses a single dark theme. '
              'Additional themes are not part of this release.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// About: real version info and the standard Flutter license page.
class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(LucideIcons.smartphone, color: theme.colorScheme.primary),
            title: const Text('KuikChat for Android'),
            subtitle: Text('Version 0.1.0 (development build)',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          ListTile(
            leading: Icon(LucideIcons.scrollText, color: theme.colorScheme.primary),
            title: const Text('Open-source licenses'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'KuikChat',
              applicationVersion: '0.1.0',
            ),
          ),
        ],
      ),
    );
  }
}
