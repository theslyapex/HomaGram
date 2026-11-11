const homagramAuthRedirect = 'homagram://auth-callback';
final homagramUsernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

String? validateHomagramUsername(String? value) {
  final username = (value ?? '').trim().toLowerCase();
  if (username.isEmpty) return 'نام کاربری را وارد کنید.';
  if (!homagramUsernamePattern.hasMatch(username)) {
    return 'نام کاربری باید ۳ تا ۲۴ حرف انگلیسی، عدد یا زیرخط باشد.';
  }
  return null;
}
