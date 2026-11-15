const homagramAuthRedirect = 'homagram://auth-callback';
final homagramUsernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

String? validateHomagramUsername(String? value) {
  final username = (value ?? '').trim().toLowerCase();
  if (username.isEmpty) return 'usernameRequired';
  if (!homagramUsernamePattern.hasMatch(username)) {
    return 'usernameInvalid';
  }
  return null;
}
