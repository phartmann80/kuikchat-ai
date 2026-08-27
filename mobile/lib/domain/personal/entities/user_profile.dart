/// Personal-environment user profile.
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.about,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? about;

  UserProfile copyWith({String? displayName, String? avatarUrl, String? about}) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      about: about ?? this.about,
    );
  }
}
