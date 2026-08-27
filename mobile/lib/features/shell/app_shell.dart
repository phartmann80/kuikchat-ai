import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../state/platform_scope.dart';
import '../business/business_screens.dart';
import '../personal/chats/chats_screen.dart';
import '../personal/settings/settings_screen.dart';

/// Root shell after sign-in.
///
/// Personal and Business have SEPARATE navigation models: switching scope
/// replaces the destination set and the active screen entirely. The two
/// environments never render each other's screens or share controllers.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _personalIndex = 0;
  int _businessIndex = 0;

  static const _personalDestinations = [
    _Destination('Chats', LucideIcons.messageSquare),
    _Destination('Settings', LucideIcons.settings),
  ];

  static const _businessDestinations = [
    _Destination('Inbox', LucideIcons.inbox),
    _Destination('Customers', LucideIcons.users),
    _Destination('Settings', LucideIcons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(platformScopeProvider);
    final isBusiness = scope == PlatformScope.business;
    final destinations = isBusiness ? _businessDestinations : _personalDestinations;
    final index = isBusiness ? _businessIndex : _personalIndex;

    // Tablet breakpoint: rail on wide screens, bottom bar on phones.
    final isWide = MediaQuery.sizeOf(context).width >= 840;

    final body = isBusiness
        ? switch (_businessIndex) {
            0 => const BusinessInboxScreen(),
            1 => const BusinessCustomersScreen(),
            _ => const BusinessSettingsScreen(),
          }
        : switch (_personalIndex) {
            0 => const ChatsScreen(),
            _ => const SettingsScreen(),
          };

    void onSelect(int value) {
      setState(() {
        if (isBusiness) {
          _businessIndex = value;
        } else {
          _personalIndex = value;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              isBusiness ? LucideIcons.briefcase : LucideIcons.messageCircle,
              size: 20,
              color: isBusiness
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isBusiness ? 'KuikChat Business' : 'KuikChat',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _PlatformSwitcher(
              scope: scope,
              // Icon-only segments on narrow phones so the AppBar never
              // overflows; labels appear from 400 dp upwards.
              compact: MediaQuery.sizeOf(context).width < 400,
              onChanged: (next) => ref.read(platformScopeProvider.notifier).state = next,
            ),
          ),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: onSelect,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _PlatformSwitcher extends StatelessWidget {
  const _PlatformSwitcher({
    required this.scope,
    required this.onChanged,
    this.compact = false,
  });

  final PlatformScope scope;
  final ValueChanged<PlatformScope> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PlatformScope>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(
          value: PlatformScope.personal,
          icon: const Icon(LucideIcons.user, size: 16),
          label: compact ? null : const Text('Personal'),
          tooltip: 'Personal',
        ),
        ButtonSegment(
          value: PlatformScope.business,
          icon: const Icon(LucideIcons.briefcase, size: 16),
          label: compact ? null : const Text('Business'),
          tooltip: 'Business',
        ),
      ],
      selected: {scope},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
