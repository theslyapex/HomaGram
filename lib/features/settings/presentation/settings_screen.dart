import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/app_theme.dart';
import '../../notifications/presentation/notifications_screen.dart';

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

  void _open(BuildContext context, String title, List<_PolicySection> sections) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PolicyScreen(title: title, sections: sections)));
  }
  @override
  Widget build(BuildContext context) {
    final entries = <_SettingEntry>[
      _SettingEntry(Icons.password_rounded, 'بازیابی رمز عبور', 'ارسال لینک امن به ایمیل حساب',
        () => _sendPasswordReset(context)),
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
      _SettingEntry(Icons.info_outline_rounded, 'درباره هماگرام', 'اطلاعات و پشتیبانی',
        () => _open(context, 'درباره هماگرام', const [
          _PolicySection('درباره سرویس', 'هماگرام بستری برای انتشار محتوا، ارتباط و گفت‌وگو است. قابلیت‌ها ممکن است تغییر کنند یا برای نگهداری موقتاً در دسترس نباشند.'),
          _PolicySection('پشتیبانی', 'برای گزارش خطا یا درخواست بررسی از گفت‌وگوی پشتیبانی داخل برنامه استفاده کنید.'),
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
        const Text('این متن‌ها پیش‌نویس حقوقی محصول هستند؛ پیش از انتشار عمومی باید با قوانین کشور محل فعالیت و نظر مشاور حقوقی تطبیق داده شوند.',
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
  _PolicySection('پذیرش و صلاحیت استفاده', 'با ایجاد حساب یا استفاده از هماگرام، موافقت می‌کنید شرایط استفاده و سیاست حریم خصوصی را رعایت کنید. استفاده باید مطابق سن قانونی و مقررات لازم‌الاجرا در محل اقامت شما باشد. اگر رضایت ولی یا سرپرست لازم است، بدون آن از سرویس استفاده نکنید.'),
  _PolicySection('حساب و امنیت', 'اطلاعات ثبت‌نام باید صحیح و به‌روز باشد. مسئولیت حفاظت از رمز عبور و دستگاه بر عهده شماست. دسترسی مشکوک را فوراً گزارش کنید. خریدوفروش حساب، جعل هویت و دور زدن محدودیت‌های امنیتی ممنوع است.'),
  _PolicySection('رفتار و محتوای ممنوع', 'تهدید، آزار، نفرت‌پراکنی، افشای اطلاعات خصوصی، جعل هویت، کلاهبرداری، هرزنامه، نقض حقوق دیگران و محتوای غیرقانونی ممنوع است. هرگونه محتوای بهره‌کشانه یا جنسی مرتبط با افراد زیر سن قانونی به‌طور مطلق ممنوع است.'),
  _PolicySection('محتوای کاربران', 'مالکیت محتوای ایجادشده نزد شما باقی می‌ماند؛ با این حال برای نمایش، ذخیره، انتقال و پشتیبان‌گیری در چارچوب عملکرد سرویس، مجوزی محدود و غیرانحصاری به هماگرام می‌دهید. مسئولیت داشتن مجوز لازم برای عکس، موسیقی و آثار دیگر بر عهده منتشرکننده است.'),
  _PolicySection('گزارش و تعدیل', 'کاربران می‌توانند محتوای مشکوک را گزارش کنند. هماگرام می‌تواند برای امنیت کاربران، رعایت قانون یا اجرای مقررات، محتوا را محدود یا حذف و در موارد لازم حساب را تعلیق کند. امکان درخواست بازبینی از مسیر پشتیبانی فراهم است.'),
  _PolicySection('دسترس‌پذیری و مسئولیت', 'سرویس ممکن است به‌دلیل نگهداری، اختلال شبکه یا عوامل خارج از کنترل موقتاً قطع شود. سرویس بدون تضمین بی‌وقفه یا عاری از خطا ارائه می‌شود. هیچ بندی از این متن مسئولیت غیرقابل‌اسقاطی را که قانون مقرر کرده حذف نمی‌کند.'),
  _PolicySection('تغییر شرایط و تماس', 'نسخه و تاریخ اجرای شرایط باید در انتشار نهایی درج شود. تغییرات اساسی از طریق اعلان درون‌برنامه‌ای اطلاع‌رسانی می‌شود. برای اعتراض یا درخواست بررسی از پشتیبانی استفاده کنید.'),
];
const List<_PolicySection> _privacy = [
  _PolicySection('داده‌های دریافت‌شده', 'برای ارائه سرویس ممکن است شناسه حساب، نام نمایشی، نام کاربری، ایمیل در صورت ثبت، تصویر نمایه، محتوا، پیام‌ها، ارتباطات، گزارش‌ها و تنظیمات حریم خصوصی پردازش شوند.'),
  _PolicySection('داده‌های فنی و فعالیت', 'اطلاعات فنی مانند نوع دستگاه، نسخه برنامه، گزارش خطا و زمان درخواست‌ها ممکن است برای امنیت و رفع اشکال ثبت شوند. داده‌های فعالیت باید فقط به‌اندازه نیاز و با دوره نگهداری مشخص جمع‌آوری شوند.'),
  _PolicySection('هدف پردازش', 'داده‌ها برای ایجاد حساب، نمایش محتوا، ارسال پیام و اعلان، پشتیبانی، امنیت، رسیدگی به گزارش‌ها و بهبود سرویس استفاده می‌شوند. استفاده تبلیغاتی یا اشتراک‌گذاری ثانویه باید جداگانه و شفاف اعلام شود.'),
  _PolicySection('دسترسی و اشتراک‌گذاری', 'محتوایی که عمومی منتشر می‌کنید برای دیگر کاربران قابل مشاهده است. داده خصوصی فقط در حد لازم برای ارائه سرویس، رسیدگی به درخواست معتبر قانونی یا حفاظت از امنیت کاربران در اختیار اشخاص مجاز قرار می‌گیرد.'),
  _PolicySection('نگهداری و حذف', 'داده‌ها فقط برای مدت لازم نگهداری می‌شوند. حذف حساب باید فرآیند روشن داشته باشد؛ داده‌هایی که قانوناً باید برای رسیدگی به اختلاف یا جلوگیری از تقلب حفظ شوند، با محدودیت دسترسی نگهداری می‌شوند.'),
  _PolicySection('حقوق کاربر و امنیت', 'در حدود قانون محل فعالیت می‌توانید درخواست دسترسی، اصلاح، دریافت نسخه یا حذف اطلاعات را ثبت کنید. تدابیر فنی متناسب برای حفاظت از داده‌ها به‌کار می‌رود، اما هیچ سامانه‌ای مصونیت مطلق ندارد.'),
  _PolicySection('ارائه‌دهندگان زیرساخت', 'برای میزبانی، ذخیره‌سازی، احراز هویت و ارسال اعلان ممکن است از ارائه‌دهندگان فنی استفاده شود. دسترسی این ارائه‌دهندگان باید در حد ارائه خدمت و مطابق تعهدات قراردادی و امنیتی محدود باشد.'),
  _PolicySection('اعلان‌ها و کنترل کاربر', 'اعلان‌های دستگاه ممکن است از طریق سرویس اعلان سیستم‌عامل ارسال شوند. می‌توانید اعلان‌ها را از تنظیمات دستگاه مدیریت کنید؛ خاموش‌کردن اعلان‌ها ممکن است باعث از دست رفتن هشدارهای فوری شود.'),
  _PolicySection('به‌روزرسانی سیاست', 'هر نسخه نهایی باید شماره نسخه، تاریخ آخرین بازبینی و تاریخ اجرا داشته باشد. تغییرات مهم باید پیش از اجرا به‌صورت روشن اطلاع‌رسانی شوند.'),
];
const List<_PolicySection> _community = [
  _PolicySection('احترام و امنیت', 'تهدید، تعقیب، آزار مستمر، تحقیر هدفمند و افشای نشانی یا اطلاعات تماس خصوصی ممنوع است.'),
  _PolicySection('محتوا و اصالت', 'جعل هویت، اسپم، کلاهبرداری، بدافزار، محتوای ناقض قانون و نقض حقوق دیگران ممنوع است.'),
  _PolicySection('حفاظت از افراد کم‌سن', 'هرگونه بهره‌کشی، درخواست محتوای جنسی، تهدید یا تماس نامناسب با افراد زیر سن قانونی ممنوع است. محتوای سوءاستفاده از کودک را بازنشر نکنید و فوراً گزارش دهید.'),
  _PolicySection('گزارش و اعتراض', 'گزارش‌ها باید صادقانه و با حسن نیت باشند. گزارش دروغین و عمدی یا استفاده از ابزار گزارش برای آزار دیگران می‌تواند موجب محدودیت حساب شود.'),
];
const List<_PolicySection> _copyright = [
  _PolicySection('حقوق آثار', 'موسیقی، عکس، ویدئو، متن و نشان تجاری ممکن است تحت حمایت حقوق مالکیت فکری باشند. فقط محتوایی را بارگذاری کنید که مالک آن هستید یا مجوز معتبر استفاده از آن را دارید.'),
  _PolicySection('درخواست رسیدگی', 'دارنده حق یا نماینده مجاز می‌تواند با ارائه نشانی محتوا، شرح حق مورد ادعا و اطلاعات تماس، درخواست بررسی ثبت کند.'),
  _PolicySection('اقدام در برابر تخلف', 'پس از بررسی متناسب، محتوا ممکن است محدود یا حذف شود و در صورت تکرار تخلف، دسترسی حساب محدود گردد. کاربر متأثر می‌تواند توضیح و مدرک مخالف ارائه کند.'),
];