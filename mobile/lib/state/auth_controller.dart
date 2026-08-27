import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/personal_env.dart';
import 'providers.dart';

enum AuthStatus { signedIn, signedOut, notConfigured }

/// Watches the Personal session. All auth actions go through the repository;
/// widgets never touch Supabase auth directly.
class AuthController extends AsyncNotifier<AuthStatus> {
  StreamSubscription<bool>? _subscription;

  @override
  Future<AuthStatus> build() async {
    if (!PersonalEnv.isConfigured) {
      return AuthStatus.notConfigured;
    }
    final repo = ref.watch(personalAuthRepositoryProvider);
    await _subscription?.cancel();
    _subscription = repo.watchSignedIn().listen((signedIn) {
      state = AsyncData(signedIn ? AuthStatus.signedIn : AuthStatus.signedOut);
    });
    ref.onDispose(() => _subscription?.cancel());
    return repo.isSignedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  Future<void> signIn({required String email, required String password}) async {
    final repo = ref.read(personalAuthRepositoryProvider);
    await repo.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final repo = ref.read(personalAuthRepositoryProvider);
    await repo.signUpWithPassword(email: email, password: password, displayName: displayName);
  }

  Future<void> signOut() async {
    final repo = ref.read(personalAuthRepositoryProvider);
    await repo.signOut();
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthStatus>(AuthController.new);
