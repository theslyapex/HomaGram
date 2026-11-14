import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/app_theme.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../support/presentation/support_chat_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  Future<void> _sendPasswordReset(BuildContext context) async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای این حساب ایمیل ثبت‌شده‌ای در دسترس نیست.')),
      );
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لینک بازیابی رمز عبور به ایمیل حساب ارسال شد.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارسال لینک بازیابی انجام نشد؛ کمی بعد دوباره تلاش کنید.')),
      );
    }
  }

  Future<void> _requestAccountDeletion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('درخواست حذف حساب'),
        content: const Text('درخواست شما در گفت‌وگوی پشتیبانی ثبت می‌شود. حساب فوراً حذف نخواهد شد و پیش از اقدام، مالکیت حساب و موارد نگهداری قانونی بررسی می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ادامه و ارسال')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const SupportChatScreen(
        initialMessage: 'درخواست رسمی حذف حساب کاربری هماگرام: لطفاً مالکیت حساب را بررسی کنید، مراحل حذف و پیامدهای آن را توضیح دهید و پس از احراز هویت، درخواست حذف اطلاعات قابل حذف را مطابق قوانین لازم‌الاجرا پیگیری کنید.',
      ),
    ));
  }

  void _open(BuildContext context, String title, List<_PolicySection> sections) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PolicyScreen(title: title, sections: sections)));
  }
  @override
  Widget build(BuildContext context) {
    final entries = <_SettingEntry>[
      _SettingEntry(Icons.password_rounded, 'بازیابی رمز عبور', 'ارسال لینک امن به ایمیل حساب',
        () => _sendPasswordReset(context)),
      _SettingEntry(Icons.person_remove_alt_1_rounded, 'درخواست حذف حساب', 'ثبت درخواست رسمی از طریق پشتیبانی',
        () => _requestAccountDeletion(context)),
      _SettingEntry(Icons.folder_shared_outlined, 'درخواست‌های اطلاعات و حساب', 'دریافت نسخه اطلاعات یا درخواست حذف حساب',
        () => _open(context, 'درخواست‌های اطلاعات و حساب', const [
          _PolicySection('دسترسی و دریافت نسخه', 'برای درخواست نسخه‌ای از اطلاعات مرتبط با حساب، از گفت‌وگوی پشتیبانی داخل برنامه پیام دهید. درخواست باید از همان حساب ثبت شود تا امکان بررسی مالکیت حساب فراهم باشد.'),
          _PolicySection('اصلاح اطلاعات', 'نام نمایشی، نام کاربری و اطلاعاتی را که در بخش ویرایش نمایه قابل تغییر است، از همان بخش اصلاح کنید. برای داده‌هایی که امکان ویرایش مستقیم ندارند، درخواست خود را به پشتیبانی ارسال کنید.'),
          _PolicySection('درخواست حذف حساب', 'برای ثبت درخواست حذف حساب، از گفت‌وگوی پشتیبانی داخل برنامه استفاده کنید. پیش از اجرای حذف، پیامدهای آن، مواردی که ممکن است طبق قانون یا برای رسیدگی به گزارش‌ها و اختلاف‌ها نگهداری شوند، و وضعیت محتوای منتشرشده باید به شما توضیح داده شود. این صفحه به‌تنهایی حساب را حذف نمی‌کند.'),
          _PolicySection('رسیدگی و پیگیری', 'درخواست‌ها پس از بررسی هویت و دامنه درخواست رسیدگی می‌شوند. اطلاعات ورود، رمز عبور یا کد یک‌بارمصرف را برای هیچ‌کس ارسال نکنید.'),
        ])),
      _SettingEntry(Icons.notifications_active_outlined, 'اعلان‌ها', 'مدیریت اعلان‌های دریافتی',
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()))),
      _SettingEntry(Icons.lock_outline_rounded, 'حریم خصوصی و امنیت', 'اصول حفاظت از حساب و اطلاعات',
        () => _open(context, 'حریم خصوصی و امنیت', _privacy)),
      _SettingEntry(Icons.gavel_rounded, 'قوانین و مقررات', 'شرایط استفاده از هماگرام',
        () => _open(context, 'قوانین و مقررات', _terms)),
      _SettingEntry(Icons.groups_2_outlined, 'راهنمای جامعه', 'رفتار مجاز و محتوای ممنوع',
        () => _open(context, 'راهنمای جامعه', _community)),
      _SettingEntry(Icons.copyright_rounded, 'مالکیت محتوا و حقوق نشر', 'حقوق کاربران و رسیدگی به تخلفات',
        () => _open(context, 'مالکیت محتوا و حقوق نشر', _copyright)),
      _SettingEntry(Icons.info_outline_rounded, 'درباره هماگرام', 'داستان، چشم‌انداز و مسیر رشد محصول',
        () => _open(context, 'درباره هماگرام', const [
          _PolicySection('هماگرام؛ ارتباطی فراتر از مرزها', 'هماگرام یک فضای اجتماعی و پیام‌رسان چندرسانه‌ای است که برای نزدیک‌تر کردن آدم‌ها، ایده‌ها و تجربه‌ها ساخته می‌شود؛ جایی برای گفت‌وگو، کشف محتوا و ساختن ارتباط‌های معنادار.'),
          _PolicySection('یک خانه برای ارتباط و خلاقیت', 'در هماگرام می‌توانید محتوای تصویری و ویدئویی منتشر کنید، ریلز و استوری ببینید، با دیگران گفت‌وگو کنید، گروه و کانال بسازید، دیدگاه بگذارید و محتوای مورد علاقه‌تان را دنبال کنید. هدف این است که تجربه‌های روزمره ارتباطی در محیطی منسجم و خوش‌ساخت کنار هم قرار بگیرند.'),
          _PolicySection('طراحی‌شده برای تجربه‌ای روان', 'از هویت بصری تا حرکت اجزای رابط کاربری، تلاش می‌کنیم تجربه‌ای سریع، خوانا و دلنشین ارائه کنیم. هماگرام به‌صورت پیوسته بهبود می‌یابد و قابلیت‌های تازه پس از آزمون و بررسی مرحله‌ای در اختیار کاربران قرار می‌گیرند.'),
          _PolicySection('حریم خصوصی و اختیار کاربر', 'کنترل حساب خصوصی، تنظیمات نمایش اطلاعات، مدیریت نشست‌ها، گزارش محتوا و ارتباط با پشتیبانی بخشی از مسیر اعتمادسازی هستند. هیچ‌گاه رمز عبور یا کد ورود خود را در اختیار دیگران قرار ندهید. جزئیات پردازش اطلاعات در بخش «حریم خصوصی و امنیت» توضیح داده شده است.'),
          _PolicySection('جامعه‌ای بر پایه احترام', 'هماگرام برای گفت‌وگوی محترمانه و مشارکت خلاقانه ساخته می‌شود. امنیت، کرامت و حقوق دیگران باید در انتشار محتوا و ارتباط‌ها رعایت شود؛ گزارش‌های معتبر بررسی می‌شوند و امکان پیگیری از مسیر پشتیبانی وجود دارد.'),
          _PolicySection('چشم‌انداز توسعه', 'مسیر توسعه هماگرام بر بهبود پیام‌رسانی، تجربه پروفایل، ابزارهای تولید محتوا، امنیت حساب، دسترس‌پذیری و کیفیت عملکرد متمرکز است. قابلیت‌های در حال توسعه تا زمان انتشار و آزمون نهایی، وعده قطعی محصول محسوب نمی‌شوند.'),
          _PolicySection('ارتباط با تیم هماگرام', 'برای پیشنهاد، گزارش خطا، درخواست بررسی یا پرسش درباره حساب، از گفت‌وگوی پشتیبانی داخل برنامه استفاده کنید. اگر گزارش شما شامل تصویر یا اطلاعات خصوصی است، فقط اطلاعات ضروری را ارسال کنید.'),
          _PolicySection('هویت محصول', 'HomaGram • Connection Beyond Boundaries\nهماگرام؛ ارتباطی فراتر از مرزها.'),
        ])),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات', style: TextStyle(fontWeight: FontWeight.w900))),
      body: HomaGramEntrance(child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF273B72), Color(0xFF174D60), Color(0xFF17233E)])),
          child: const Row(children: [
            CircleAvatar(radius: 25, backgroundColor: Color(0x33FFFFFF),
              child: Icon(Icons.tune_rounded, color: Colors.white, size: 27)),
            SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مرکز تنظیمات', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text('حساب، امنیت و چارچوب استفاده از هماگرام',
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6)),
            ])),
          ]),
        ),
        const SizedBox(height: 18),
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
              title: const Text('خروج از حساب'), content: const Text('از حساب هماگرام خارج شوید؟'),
              actions: [
                HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف'))),
                HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج'))),
              ],
            ));
            if (ok == true) await Supabase.instance.client.auth.signOut();
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('خروج از حساب', style: TextStyle(fontFamily: 'Estedad')),
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        )),
        const SizedBox(height: 14),
        const Text('نسخه ۱.۰ • بازبینی محتوایی: ۲۳ آبان ۱۴۰۵. این مقررات باید همراه با قوانین آمره و تصمیم مراجع صالح تفسیر شوند؛ هیچ بندی حقوقی را که قانون قابل اسقاط نمی‌داند محدود نمی‌کند.',
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
      Container(padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
          color: HomaGramTheme.turquoise.withValues(alpha: .09),
          border: Border.all(color: HomaGramTheme.turquoise.withValues(alpha: .2))),
        child: const Text('لطفاً این موارد را مطالعه کنید. متن نهایی، نسخه معتبر و تاریخ اجرای شرایط باید پیش از انتشار رسمی تعیین و تغییرات مهم به کاربران اعلام شود.',
          style: TextStyle(height: 1.9, fontSize: 12))),
      const SizedBox(height: 14),
      for (var i = 0; i < sections.length; i++)
        Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(
          padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${sections[i].title}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 8),
            Text(sections[i].body, style: const TextStyle(height: 1.9, fontSize: 12)),
          ]),
        )),
    ]),
  );
}
const List<_PolicySection> _terms = [
  _PolicySection('۱. پذیرش و چارچوب حقوقی', 'استفاده از هماگرام به معنی پذیرش این شرایط و سیاست حریم خصوصی است. این متن با توجه به قوانین لازم‌الاجرای جمهوری اسلامی ایران، از جمله اصول مرتبط قانون اساسی، قانون مدنی، قانون تجارت الکترونیکی و قانون جرایم رایانه‌ای تنظیم شده است. در صورت تعارض، حکم آمره قانون بر این متن مقدم است.'),
  _PolicySection('۲. اهلیت و استفاده مسئولانه', 'کاربر باید برای ایجاد حساب و انجام اقدامات حقوقی مرتبط، اهلیت قانونی لازم را داشته باشد. مواد ۹۵۶ تا ۹۶۰ قانون مدنی درباره آغاز و پایان اهلیت و امکان اعمال حقوق مدنی چارچوب عمومی این موضوع را بیان می‌کنند. هرجا طبق قانون رضایت یا اقدام ولی، قیم یا نماینده قانونی لازم باشد، رعایت آن بر عهده کاربر و سرپرست قانونی اوست.'),
  _PolicySection('۳. صحت اطلاعات و امنیت حساب', 'اطلاعات حساب باید درست و تا حد امکان به‌روز باشد. کاربر مسئول حفاظت از دستگاه و اطلاعات ورود خود است و نباید رمز عبور، کد یک‌بارمصرف یا کلیدهای امنیتی را در اختیار دیگران بگذارد. جعل هویت، دسترسی غیرمجاز، خریدوفروش حساب و تلاش برای دور زدن تدابیر امنیتی ممنوع است.'),
  _PolicySection('۴. محتوای مجاز و مسئولیت انتشار', 'کاربر مسئول محتوایی است که منتشر یا ارسال می‌کند و باید حقوق اشخاص، حریم خصوصی، مالکیت فکری و قوانین لازم‌الاجرا را رعایت کند. تهدید، آزار، افشای اطلاعات خصوصی، کلاهبرداری، هرزنامه، جعل هویت، بدافزار، محتوای ناقض قانون و محتوای بهره‌کشانه یا جنسی مرتبط با افراد زیر سن قانونی ممنوع است.'),
  _PolicySection('۵. مالکیت محتوا و مجوز محدود سرویس', 'حقوق محتوایی که کاربر ایجاد می‌کند، تا جایی که قانون مقرر کرده، برای او باقی می‌ماند. کاربر فقط به میزان لازم برای میزبانی، ذخیره، نمایش، انتقال، پشتیبان‌گیری و ارائه قابلیت‌هایی که خودش انتخاب کرده، مجوزی محدود و غیرانحصاری به هماگرام می‌دهد. این مجوز به معنی انتقال مالکیت اثر نیست و با حذف محتوا یا حساب، در حدود امکان فنی و تعهدات قانونی خاتمه می‌یابد.'),
  _PolicySection('۶. ارتباطات و احترام به حریم دیگران', 'پیام‌ها و ارتباطات خصوصی نباید بدون مجوز یا مجوز قانونی در اختیار دیگران قرار گیرند. اصل ۲۲ قانون اساسی از حیثیت، حقوق و حریم اشخاص حمایت می‌کند و اصل ۲۵ تعرض به مکاتبات و ارتباطات را جز در موارد مقرر قانونی منع می‌کند. کاربر نیز نباید از ابزارهای هماگرام برای تهدید، مزاحمت یا نقض حریم خصوصی استفاده کند.'),
  _PolicySection('۷. گزارش، بررسی و اقدامات حفاظتی', 'کاربران می‌توانند محتوا، پیام یا رفتار مشکوک را گزارش کنند. هماگرام گزارش را بررسی می‌کند و متناسب با شدت و تکرار تخلف، ممکن است محتوا را محدود یا حذف کند، قابلیت‌هایی را موقتاً ببندد یا حساب را تعلیق کند. تا حد امکان دلیل اقدام و مسیر درخواست بازبینی اعلام می‌شود؛ این اقدامات جایگزین صلاحیت مراجع قانونی نیست.'),
  _PolicySection('۸. مالکیت فکری و حقوق اشخاص ثالث', 'بارگذاری آثار دیگران فقط در صورت مالکیت، اجازه معتبر یا وجود مجوز قانونی مجاز است. دارنده حق یا نماینده قانونی او می‌تواند نشانی محتوا، شرح حق مورد ادعا و مدارک لازم را از طریق پشتیبانی ارسال کند. گزارش خلاف واقع یا سوءاستفاده از سازوکار گزارش نیز ممنوع است.'),
  _PolicySection('۹. دسترس‌پذیری و مسئولیت', 'ممکن است سرویس به‌دلیل نگهداری، اختلال اینترنت، رخدادهای امنیتی یا عوامل خارج از کنترل موقتاً در دسترس نباشد. هماگرام برای کاهش اختلال و حفاظت از داده‌ها تلاش متعارف انجام می‌دهد، اما دسترس‌پذیری بی‌وقفه یا امنیت مطلق را تضمین نمی‌کند. هیچ محدودیتی در این بند، مسئولیت غیرقابل‌اسقاط قانونی را از بین نمی‌برد.'),
  _PolicySection('۱۰. درخواست‌ها و حل اختلاف', 'برای پرسش، اعتراض به تصمیم مدیریتی یا درخواست مربوط به حساب، ابتدا از پشتیبانی داخل برنامه استفاده کنید. حق مراجعه به مراجع صالح و دادخواهی، مطابق اصل ۳۴ قانون اساسی، محفوظ است. قانون حاکم و مرجع رسیدگی با رعایت قواعد صلاحیت و مقررات آمره تعیین می‌شود.'),
  _PolicySection('۱۱. اصلاح شرایط و نسخه معتبر', 'تغییرات مهم شرایط از طریق اعلان درون‌برنامه‌ای یا روش مناسب اطلاع‌رسانی می‌شود. تاریخ بازبینی و نسخه جاری در همین بخش درج خواهد شد. ادامه استفاده پس از تاریخ اجرای تغییرات، تابع مقررات جدید در حدود قانون است.'),
];
const List<_PolicySection> _privacy = [
  _PolicySection('۱. دامنه و اصول حفاظت', 'هماگرام اطلاعات را برای ارائه و ایمن‌سازی خدمات اجتماعی و پیام‌رسانی پردازش می‌کند. این سیاست با توجه به اصول ۲۲ و ۲۵ قانون اساسی و مواد ۵۸ تا ۶۱ قانون تجارت الکترونیکی درباره حمایت از داده‌پیام‌های شخصی تدوین شده است.'),
  _PolicySection('۲. اطلاعاتی که پردازش می‌شود', 'بسته به قابلیت‌هایی که استفاده می‌کنید، اطلاعات حساب و احراز هویت، نام و شناسه کاربری، تصویر و معرفی پروفایل، پست‌ها، ریلزها، استوری‌ها، دیدگاه‌ها، پیام‌ها، فایل‌های ارسالی، فهرست ارتباطات، گزارش‌ها، تنظیمات و سوابق ضروری امنیتی ممکن است پردازش شوند.'),
  _PolicySection('۳. اطلاعات فنی و گزارش خطا', 'برای تشخیص خطا و حفاظت از سرویس ممکن است اطلاعاتی مانند مدل و نسخه سیستم‌عامل، نسخه برنامه، زمان رخداد، گزارش فنی و شناسه‌های لازم برای عیب‌یابی ثبت شوند. تصویر صفحه یا فایل پیوست فقط در صورتی ارسال می‌شود که کاربر آگاهانه آن را انتخاب و ارسال کند.'),
  _PolicySection('۴. هدف و حداقل‌گرایی', 'اطلاعات برای ساخت و اداره حساب، نمایش محتوا، پیام‌رسانی، اعلان‌ها، پشتیبانی، پیشگیری از سوءاستفاده، رسیدگی به گزارش‌ها و بهبود عملکرد استفاده می‌شود. مطابق ماده ۵۹ قانون تجارت الکترونیکی، هدف پردازش باید روشن باشد و داده‌ها نباید بیش از حد ضرورت یا برای هدف اعلام‌نشده استفاده شوند.'),
  _PolicySection('۵. اطلاعات حساس و رضایت', 'از ارسال اطلاعات حساس خود یا دیگران، مگر در صورت ضرورت واقعی و وجود مجوز قانونی، خودداری کنید. ماده ۵۸ قانون تجارت الکترونیکی پردازش برخی داده‌های حساس را بدون رضایت صریح شخص ممنوع می‌داند. هماگرام نباید از داده‌های حساس برای هدفی خارج از هدف اعلام‌شده استفاده کند.'),
  _PolicySection('۶. نمایش عمومی و ارتباط خصوصی', 'پست یا اطلاعاتی که عمومی منتشر می‌کنید ممکن است برای سایر کاربران قابل مشاهده و بازنشر باشد. پیام خصوصی فقط برای شرکت‌کنندگان همان گفتگو در دسترس طراحی شده است؛ با این حال گیرنده می‌تواند محتوایی را که دریافت کرده ذخیره یا گزارش کند. اطلاعات ورود و کدهای امنیتی را در پیام‌ها ارسال نکنید.'),
  _PolicySection('۷. اشتراک‌گذاری با ارائه‌دهندگان و مراجع قانونی', 'برای میزبانی، پایگاه داده، ذخیره فایل، احراز هویت و اعلان ممکن است از ارائه‌دهندگان زیرساخت استفاده شود و دسترسی آنان باید به اندازه ارائه خدمت محدود باشد. اطلاعات کاربران فروخته نمی‌شود. افشای اطلاعات به مراجع قانونی فقط در حدود درخواست معتبر و الزامات لازم‌الاجرا انجام می‌شود.'),
  _PolicySection('۸. نگهداری، حذف و نسخه‌های پشتیبان', 'اطلاعات تا زمانی نگهداری می‌شود که برای ارائه سرویس، امنیت، رسیدگی به اختلاف یا اجرای تکلیف قانونی لازم باشد. پس از درخواست حذف حساب، داده‌های قابل حذف در چرخه حذف قرار می‌گیرند؛ داده‌ای که نگهداری آن الزام قانونی یا ضرورت معتبر امنیتی داشته باشد، با دسترسی محدود و فقط برای همان هدف حفظ می‌شود. نسخه‌های پشتیبان نیز ممکن است تا پایان چرخه فنی نگهداری باقی بمانند.'),
  _PolicySection('۹. دسترسی، اصلاح و درخواست حذف', 'کاربر می‌تواند برای دسترسی به اطلاعات، اصلاح داده نادرست، دریافت نسخه یا درخواست حذف، از مسیر حساب یا پشتیبانی اقدام کند. ماده ۵۹ قانون تجارت الکترونیکی از جمله به دسترسی شخص به پرونده اطلاعاتی خود و امکان اصلاح یا درخواست محو آن اشاره دارد؛ رسیدگی با احراز مالکیت حساب و رعایت استثناهای قانونی انجام می‌شود.'),
  _PolicySection('۱۰. امنیت و کنترل دسترسی', 'اقدامات فنی و سازمانی متناسب مانند کنترل دسترسی، احراز هویت، ارتباط امن و ثبت رویدادهای ضروری برای حفاظت از اطلاعات به‌کار گرفته می‌شود. هیچ سامانه‌ای مصونیت کامل ندارد؛ در صورت مشاهده رخداد مشکوک، آن را از طریق پشتیبانی گزارش کنید.'),
  _PolicySection('۱۱. حقوق افراد کم‌سن', 'قابلیت‌ها و پردازش اطلاعات کاربران کم‌سن باید با رعایت قوانین مربوط و هرگونه لزوم رضایت یا نظارت ولی یا سرپرست قانونی انجام شود. کاربران نباید اطلاعات تماس، نشانی، مدرسه، موقعیت مکانی یا تصاویر خصوصی افراد کم‌سن را بدون مجوز منتشر کنند.'),
  _PolicySection('۱۲. مبانی قانونی و به‌روزرسانی', 'مبنای تدوین این متن، از جمله اصول ۲۲، ۲۵ و ۳۴ قانون اساسی، مواد ۹۵۶ تا ۹۶۰ قانون مدنی در موضوع اهلیت، مواد ۵۸ تا ۶۱ قانون تجارت الکترونیکی و مقررات مرتبط قانون جرایم رایانه‌ای است. تفسیر و اجرای این سیاست تابع متن معتبر و اصلاحات قوانین در زمان رسیدگی خواهد بود.'),
];
const List<_PolicySection> _community = [
  _PolicySection('احترام و امنیت', 'تهدید، تعقیب، آزار مستمر، تحقیر هدفمند، نفرت‌پراکنی و افشای نشانی یا اطلاعات تماس خصوصی ممنوع است.'),
  _PolicySection('محتوا و اصالت', 'جعل هویت، اسپم، کلاهبرداری، بدافزار، محتوای ناقض قانون، نقض مالکیت فکری و انتشار اطلاعات خصوصی بدون مجوز ممنوع است.'),
  _PolicySection('حفاظت از افراد کم‌سن', 'هرگونه بهره‌کشی، تهدید، درخواست محتوای جنسی یا تماس نامناسب با افراد زیر سن قانونی ممنوع است. محتوای سوءاستفاده از کودک را ذخیره یا بازنشر نکنید و فوراً گزارش دهید.'),
  _PolicySection('گزارش و اعتراض', 'گزارش‌ها باید صادقانه و با حسن نیت باشند. گزارش عمدی خلاف واقع یا استفاده از ابزار گزارش برای آزار دیگران می‌تواند موجب محدودیت حساب شود.'),
];
const List<_PolicySection> _copyright = [
  _PolicySection('حقوق آثار', 'موسیقی، عکس، ویدئو، متن و نشان تجاری ممکن است تحت حمایت حقوق مالکیت فکری باشند. فقط محتوایی را بارگذاری کنید که مالک آن هستید یا مجوز معتبر استفاده از آن را دارید.'),
  _PolicySection('درخواست رسیدگی', 'دارنده حق یا نماینده مجاز می‌تواند نشانی محتوا، شرح حق مورد ادعا، راه ارتباطی و مدارک لازم را از طریق پشتیبانی ارسال کند.'),
  _PolicySection('اقدام و بازبینی', 'پس از بررسی متناسب، محتوا ممکن است محدود یا حذف شود و در صورت تکرار تخلف، دسترسی حساب محدود گردد. کاربر متأثر می‌تواند توضیح و مدرک مخالف ارائه کند.'),
];
