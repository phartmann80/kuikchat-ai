import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/kuik_theme.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/auth_controller.dart';

/// Root widget. Decides between the sign-in flow and the app shell based on
/// the authenticated session. No Supabase calls happen here; everything goes
/// through the repository layer via Riverpod providers.
class KuikChatApp extends ConsumerWidget {
  const KuikChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return MaterialApp(
      title: 'KuikChat',
      debugShowCheckedModeBanner: false,
      theme: KuikTheme.dark(),
      darkTheme: KuikTheme.dark(),
      themeMode: ThemeMode.dark,
      home: auth.when(
        data: (state) => switch (state) {
          AuthStatus.signedIn => const AppShell(),
          AuthStatus.signedOut ||
          AuthStatus.notConfigured =>
            const SignInScreen(),
        },
        loading: () => const _AppLoading(),
        error: (_, __) => const SignInScreen(),
      ),
    );
  }
}

class _AppLoading extends StatelessWidget {
  const _AppLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
