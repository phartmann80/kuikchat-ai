import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/config/personal_env.dart';
import '../../core/result.dart';
import '../../state/auth_controller.dart';

/// Email + password sign in / sign up against the Personal backend.
/// Handles: unconfigured build, submitting, auth failure, network failure.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _isSignUp = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (_isSignUp) {
        await controller.signUp(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _displayName.text.trim(),
        );
      } else {
        await controller.signIn(email: _email.text.trim(), password: _password.text);
      }
    } on AppFailure catch (failure) {
      setState(() {
        _error = switch (failure.kind) {
          AppFailureKind.network => 'No connection. Check your network and try again.',
          AppFailureKind.unauthorized => failure.message ?? 'Invalid email or password.',
          _ => failure.message ?? 'Something went wrong. Please try again.',
        };
      });
    } catch (error) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PersonalEnv.isConfigured) {
      return const _NotConfiguredScreen();
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(LucideIcons.messageCircle, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'KuikChat',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignUp ? 'Create your Personal account' : 'Sign in to your Personal account',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _displayName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        prefixIcon: Icon(LucideIcons.user, size: 18),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().length < 2) ? 'Enter a display name' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(LucideIcons.mail, size: 18),
                    ),
                    validator: (value) =>
                        (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(LucideIcons.lock, size: 18),
                    ),
                    validator: (value) =>
                        (value == null || value.length < 8) ? 'Minimum 8 characters' : null,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _submitting
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isSignUp ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                            }),
                    child: Text(_isSignUp
                        ? 'Already have an account? Sign in'
                        : 'New to KuikChat? Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: scheme.error))),
        ],
      ),
    );
  }
}

/// Shown when the build has no Personal backend injected. This is an honest
/// configuration state — the app does not pretend a backend exists.
class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.serverOff, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('Personal backend not configured',
                  style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'This build was compiled without PERSONAL_SUPABASE_URL / '
                'PERSONAL_SUPABASE_ANON_KEY. Rebuild with:\n\n'
                'flutter run --dart-define=PERSONAL_SUPABASE_URL=... '
                '--dart-define=PERSONAL_SUPABASE_ANON_KEY=...',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
