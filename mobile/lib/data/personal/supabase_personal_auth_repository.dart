import '../../domain/personal/entities/user_profile.dart';
import '../../domain/personal/repositories/personal_auth_repository.dart';
import 'supabase_personal_client.dart';

class SupabasePersonalAuthRepository implements PersonalAuthRepository {
  SupabasePersonalAuthRepository(this._client);

  final SupabasePersonalClient _client;

  @override
  Stream<bool> watchSignedIn() =>
      _client.raw.auth.onAuthStateChange.map((event) => event.session != null);

  @override
  bool get isSignedIn => _client.raw.auth.currentSession != null;

  @override
  String? get currentUserId => _client.raw.auth.currentUser?.id;

  @override
  Future<void> signInWithPassword({required String email, required String password}) async {
    try {
      await _client.raw.auth.signInWithPassword(email: email, password: password);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      await _client.raw.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.raw.auth.signOut();
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }
}

class SupabasePersonalProfileRepository implements PersonalProfileRepository {
  SupabasePersonalProfileRepository(this._client);

  final SupabasePersonalClient _client;

  @override
  Future<UserProfile> loadOwnProfile() async {
    try {
      final userId = _client.raw.auth.currentUser!.id;
      final row = await _client.raw
          .from('profiles')
          .select('user_id, display_name, avatar_url, about')
          .eq('user_id', userId)
          .single();
      return _fromRow(row);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Future<UserProfile?> findByEmail(String email) async {
    try {
      // Server-side function: only returns a minimal profile for an exact
      // email match, never a browsable directory.
      final rows = await _client.raw
          .rpc<List<dynamic>>('find_profile_by_email', params: {'lookup_email': email.trim().toLowerCase()});
      if (rows.isEmpty) return null;
      return _fromRow(rows.first as Map<String, dynamic>);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  UserProfile _fromRow(Map<String, dynamic> row) {
    return UserProfile(
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?) ?? 'Unknown',
      avatarUrl: row['avatar_url'] as String?,
      about: row['about'] as String?,
    );
  }
}
