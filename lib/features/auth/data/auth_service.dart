import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/auth_constants.dart';

class AuthService {
  AuthService._();
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> signUp({
    required String email, required String password,
    required String username, required String displayName,
  }) async {
    await client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      emailRedirectTo: homagramAuthRedirect,
      data: {'username': username.trim().toLowerCase(), 'display_name': displayName.trim()},
    );
  }

  static Future<void> signIn({required String email, required String password}) async {
    await client.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
  }

  static Future<void> resendSignupEmail(String email) async {
    await client.auth.resend(
      type: OtpType.signup, email: email.trim().toLowerCase(),
      emailRedirectTo: homagramAuthRedirect,
    );
  }

  static Future<void> sendPasswordRecovery(String email) async {
    await client.auth.resetPasswordForEmail(email.trim().toLowerCase(), redirectTo: homagramAuthRedirect);
  }

  static Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  static Future<void> signOutThisDevice() async {
    await client.auth.signOut(scope: SignOutScope.local);
  }

  static Future<void> signOutOtherDevices() async {
    await client.auth.signOut(scope: SignOutScope.others);
  }
}
