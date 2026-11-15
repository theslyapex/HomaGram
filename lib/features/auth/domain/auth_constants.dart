const homagramAuthRedirect = 'homagram://auth-callback';
const homagramAdminEmail = 'theslyapex@gmail.com';
final homagramUsernamePattern = RegExp(r'^[a-z0-9_]{5,24}$');

String? validateHomagramUsername(String? value, {String? accountEmail}) {
  final username = (value ?? '').trim().toLowerCase();
  if (username.isEmpty) return 'usernameRequired';
  final isAdminAlias = (accountEmail ?? '').trim().toLowerCase() == homagramAdminEmail && username == 'ali';
  if (!homagramUsernamePattern.hasMatch(username) && !isAdminAlias) {
    return 'usernameInvalid';
  }
  return null;
}
