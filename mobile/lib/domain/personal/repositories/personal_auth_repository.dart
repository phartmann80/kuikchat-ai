import '../entities/user_profile.dart';

/// Authentication boundary for the PERSONAL environment.
/// Implementations must only ever talk to the Personal backend.
abstract interface class PersonalAuthRepository {
  /// Emits true while a user session exists.
  Stream<bool> watchSignedIn();

  bool get isSignedIn;

  /// The authenticated user id, or null when signed out.
  String? get currentUserId;

  Future<void> signInWithPassword({required String email, required String password});

  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signOut();
}

abstract interface class PersonalProfileRepository {
  Future<UserProfile> loadOwnProfile();

  /// Looks up another user by exact email/handle for starting a conversation.
  /// Returns null when no user matches (never throws for "not found").
  Future<UserProfile?> findByEmail(String email);
}
