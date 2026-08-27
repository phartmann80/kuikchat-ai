import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Business environment screens.
///
/// The Business backend (its own isolated Supabase project) is not
/// provisioned yet, and these screens say so honestly instead of showing
/// fake inboxes or "coming soon" marketing. The navigation structure is
/// real and separate from Personal; the data layer will be added in the
/// Business messaging vertical slice with its own repositories.
class BusinessInboxScreen extends StatelessWidget {
  const BusinessInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _BusinessNotConnected(
      icon: LucideIcons.inbox,
      title: 'Inbox',
      description:
          'The Business environment is not connected in this build. '
          'Business messaging runs on a separate, isolated backend that has '
          'not been provisioned yet.',
    );
  }
}

class BusinessCustomersScreen extends StatelessWidget {
  const BusinessCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _BusinessNotConnected(
      icon: LucideIcons.users,
      title: 'Customers',
      description:
          'The customer directory requires the Business backend, which is '
          'not connected in this build.',
    );
  }
}

class BusinessSettingsScreen extends StatelessWidget {
  const BusinessSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: Icon(LucideIcons.building2, color: theme.colorScheme.secondary),
          title: const Text('Business account'),
          subtitle: Text(
            'Business accounts live in a separate backend environment with '
            'their own authentication, data, and permissions. This build has '
            'no Business backend configured.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _BusinessNotConnected extends StatelessWidget {
  const _BusinessNotConnected({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
