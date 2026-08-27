import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuikchat_mobile/core/theme/kuik_theme.dart';
import 'package:kuikchat_mobile/features/shell/app_shell.dart';
import 'package:kuikchat_mobile/state/providers.dart';

import 'fakes/fake_personal_repositories.dart';

void main() {
  Widget buildShell(FakePersonalConversationRepository conversations) {
    return ProviderScope(
      overrides: [
        personalAuthRepositoryProvider.overrideWithValue(FakePersonalAuthRepository()),
        personalProfileRepositoryProvider.overrideWithValue(FakePersonalProfileRepository()),
        personalConversationRepositoryProvider.overrideWithValue(conversations),
        personalMessageRepositoryProvider.overrideWithValue(FakePersonalMessageRepository()),
      ],
      child: MaterialApp(theme: KuikTheme.dark(), home: const AppShell()),
    );
  }

  testWidgets('shell defaults to Personal navigation with no fake conversations',
      (tester) async {
    await tester.pumpWidget(buildShell(FakePersonalConversationRepository()));
    await tester.pumpAndSettle();

    // Personal navigation model.
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);

    // Empty state, not placeholder data.
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('switching to Business swaps to a separate navigation model',
      (tester) async {
    await tester.pumpWidget(buildShell(FakePersonalConversationRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Chats'), findsNothing);
    expect(find.textContaining('not connected', findRichText: true), findsWidgets);

    // Switching back restores Personal navigation.
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('theme is dark with brand colors', (tester) async {
    final theme = KuikTheme.dark();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFF3B82F6));
    expect(theme.colorScheme.secondary, const Color(0xFF22C55E));
  });
}
