import '../../../app/app_language.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/app_theme.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../support/presentation/support_chat_screen.dart';
import 'two_step_verification_screen.dart';
import '../../verification/presentation/verification_request_screen.dart';
import 'bug_report_settings_screen.dart';
import 'account_preferences_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  AppLocalizations _t(BuildContext context) => AppLocalizations.of(context)!;
  Future<void> _sendPasswordReset(BuildContext context) async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(context).emailUnavailable)),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(context).passwordResetSent)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(context).passwordResetFailed)),
      );
    }
  }

  Future<void> _requestAccountDeletion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context).deleteAccountRequest),
        content: Text(_t(context).deleteAccountExplanation),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t(context).cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t(context).continueAndSend)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const SupportChatScreen(
        initialMessage: _t(context).formalAccountDeletionMessage,
      ),
    ));
  }

  void _open(BuildContext context, String title, List<_PolicySection> sections) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PolicyScreen(title: title, sections: sections)));
  }
  @override
  Widget build(BuildContext context) {
    final entries = <_SettingEntry>[
      _SettingEntry(Icons.password_rounded, _t(context).passwordRecovery, _t(context).sendSecureResetLink,
        () => _sendPasswordReset(context)),
      _SettingEntry(Icons.person_remove_alt_1_rounded, _t(context).deleteAccountRequest, _t(context).submitFormalSupportRequest,
        () => _requestAccountDeletion(context)),
      _SettingEntry(Icons.folder_shared_outlined, _t(context).dataAndAccountRequests, _t(context).dataCopyOrDeletion,
        () => _open(context, _t(context).dataAndAccountRequests, [
          _PolicySection(_t(context).dataAccessTitle, _t(context).dataAccessBody),
          _PolicySection(_t(context).dataCorrectionTitle, _t(context).dataCorrectionBody),
          _PolicySection(_t(context).deleteAccountRequest, _t(context).dataDeletionBody),
          _PolicySection(_t(context).dataRequestReviewTitle, _t(context).dataRequestReviewBody),
        ])),
      _SettingEntry(Icons.verified_user_outlined, _t(context).verificationRequest, _t(context).submitVerificationDocuments,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VerificationRequestScreen()))),
      _SettingEntry(Icons.shield_moon_outlined, _t(context).twoStepVerification, _t(context).addLoginSecurityCode,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TwoStepVerificationScreen()))),
      _SettingEntry(Icons.vibration_rounded, _t(context).quickBugReport, _t(context).captureAndSubmitAfterReview,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShakeBugReportSettingsScreen()))),
      _SettingEntry(Icons.notifications_active_outlined, _t(context).notifications, _t(context).manageNotifications,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()))),
      _SettingEntry(Icons.tune_rounded, _t(context).privacyAndAccountVisibility, _t(context).themePrivacyAndBlockedUsers,
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPreferencesScreen()))),
      _SettingEntry(Icons.lock_outline_rounded, _t(context).privacyPolicy, _t(context).accountAndDataProtection,
        () => _open(context, _t(context).privacyPolicy, _privacy(_t(context)))),
      _SettingEntry(Icons.gavel_rounded, _t(context).termsAndConditions, _t(context).homagramTerms,
        () => _open(context, _t(context).termsAndConditions, _terms(_t(context)))),
      _SettingEntry(Icons.groups_2_outlined, _t(context).communityGuidelines, _t(context).allowedBehaviorAndProhibitedContent,
        () => _open(context, _t(context).communityGuidelines, _community(_t(context)))),
      _SettingEntry(Icons.copyright_rounded, _t(context).contentOwnershipAndCopyright, _t(context).userRightsAndCopyrightClaims,
        () => _open(context, _t(context).contentOwnershipAndCopyright, _copyright(_t(context)))),
      _SettingEntry(Icons.info_outline_rounded, _t(context).aboutHomagram, _t(context).productStoryVisionAndRoadmap,
        () => _open(context, _t(context).aboutHomagram, [
          _PolicySection(_t(context).aboutMissionTitle, _t(context).aboutMissionBody),
          _PolicySection(_t(context).aboutFeaturesTitle, _t(context).aboutFeaturesBody),
          _PolicySection(_t(context).aboutExperienceTitle, _t(context).aboutExperienceBody),
          _PolicySection(_t(context).aboutPrivacyTitle, _t(context).aboutPrivacyBody),
          _PolicySection(_t(context).aboutCommunityTitle, _t(context).aboutCommunityBody),
          _PolicySection(_t(context).aboutRoadmapTitle, _t(context).aboutRoadmapBody),
          _PolicySection(_t(context).aboutContactTitle, _t(context).aboutContactBody),
          _PolicySection(_t(context).aboutIdentityTitle, _t(context).aboutIdentityBody),
        ])),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_t(context).settings, style: const TextStyle(fontWeight: FontWeight.w900))),
      body: HomaGramEntrance(child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF273B72), Color(0xFF174D60), Color(0xFF17233E)])),
          child: Row(children: [
            CircleAvatar(radius: 25, backgroundColor: Color(0x33FFFFFF),
              child: Icon(Icons.tune_rounded, color: Colors.white, size: 27)),
            SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t(context).settingsCenter, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text(_t(context).accountSecurityAndUsage,
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6)),
            ])),
          ]),
        ),
        const SizedBox(height: 18),
        Card(child: LanguagePicker()),
        const SizedBox(height: 10),
        for (final entry in entries)
          Padding(padding: const EdgeInsets.only(bottom: 9), child: Material(
            color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(18),
            child: ListTile(
              onTap: entry.onTap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              leading: Container(width: 42, height: 42,
                decoration: BoxDecoration(color: HomaGramTheme.turquoise.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Icon(entry.icon, color: HomaGramTheme.turquoise)),
              title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              subtitle: Text(entry.subtitle, style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_left_rounded),
            ),
          )),
        const SizedBox(height: 12),
        HomaGramSpringPress(child: OutlinedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: Text(_t(context).signOut), content: Text(_t(context).confirmSignOut),
              actions: [
                HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t(context).cancel))),
                HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t(context).signOut))),
              ],
            ));
            if (ok == true) await Supabase.instance.client.auth.signOut();
          },
          icon: const Icon(Icons.logout_rounded),
          label: Text(_t(context).signOut, style: TextStyle(fontFamily: 'Estedad')),
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        )),
        const SizedBox(height: 14),
        Text(_t(context).versionLegalNotice,
          textAlign: TextAlign.center, style: TextStyle(fontSize: 10, height: 1.7, color: Color(0xFF8490A4))),
      ])),
    );
  }
}
class _SettingEntry {
  const _SettingEntry(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon; final String title, subtitle; final VoidCallback onTap;
}
class _PolicySection {
  const _PolicySection(this.title, this.body);
  final String title, body;
}
class _PolicyScreen extends StatelessWidget {
  const _PolicyScreen({required this.title, required this.sections});
  final String title; final List<_PolicySection> sections;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      for (var i = 0; i < sections.length; i++)
        Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sections[i].title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 8),
            Text(sections[i].body, style: const TextStyle(height: 1.9, fontSize: 12)),
          ]),
        )),
    ]),
  );
}
List<_PolicySection> _terms(AppLocalizations t) => [
  _PolicySection(t.policyTerms1Title, t.policyTerms1Body),
  _PolicySection(t.policyTerms2Title, t.policyTerms2Body),
  _PolicySection(t.policyTerms3Title, t.policyTerms3Body),
  _PolicySection(t.policyTerms4Title, t.policyTerms4Body),
  _PolicySection(t.policyTerms5Title, t.policyTerms5Body),
  _PolicySection(t.policyTerms6Title, t.policyTerms6Body),
  _PolicySection(t.policyTerms7Title, t.policyTerms7Body),
  _PolicySection(t.policyTerms8Title, t.policyTerms8Body),
  _PolicySection(t.policyTerms9Title, t.policyTerms9Body),
  _PolicySection(t.policyTerms10Title, t.policyTerms10Body),
  _PolicySection(t.policyTerms11Title, t.policyTerms11Body),
];
List<_PolicySection> _privacy(AppLocalizations t) => [
  _PolicySection(t.policyPrivacy1Title, t.policyPrivacy1Body),
  _PolicySection(t.policyPrivacy2Title, t.policyPrivacy2Body),
  _PolicySection(t.policyPrivacy3Title, t.policyPrivacy3Body),
  _PolicySection(t.policyPrivacy4Title, t.policyPrivacy4Body),
  _PolicySection(t.policyPrivacy5Title, t.policyPrivacy5Body),
  _PolicySection(t.policyPrivacy6Title, t.policyPrivacy6Body),
  _PolicySection(t.policyPrivacy7Title, t.policyPrivacy7Body),
  _PolicySection(t.policyPrivacy8Title, t.policyPrivacy8Body),
  _PolicySection(t.policyPrivacy9Title, t.policyPrivacy9Body),
  _PolicySection(t.policyPrivacy10Title, t.policyPrivacy10Body),
  _PolicySection(t.policyPrivacy11Title, t.policyPrivacy11Body),
  _PolicySection(t.policyPrivacy12Title, t.policyPrivacy12Body),
];
List<_PolicySection> _community(AppLocalizations t) => [
  _PolicySection(t.policyCommunity1Title, t.policyCommunity1Body),
  _PolicySection(t.policyCommunity2Title, t.policyCommunity2Body),
  _PolicySection(t.policyCommunity3Title, t.policyCommunity3Body),
  _PolicySection(t.policyCommunity4Title, t.policyCommunity4Body),
];
List<_PolicySection> _copyright(AppLocalizations t) => [
  _PolicySection(t.policyCopyright1Title, t.policyCopyright1Body),
  _PolicySection(t.policyCopyright2Title, t.policyCopyright2Body),
  _PolicySection(t.policyCopyright3Title, t.policyCopyright3Body),
];
