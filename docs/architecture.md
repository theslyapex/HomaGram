# معماری اولیه HomaGram

## اصول
- پروژه و زیرساخت HomaGram مستقل از Alishams و هر پروژه دیگر باقی می‌مانند.
- اپلیکیشن با Flutter و Dart توسعه می‌یابد.
- Supabase تنها بک‌اند متصل به پروژه مستقل HomaGram است.
- ماژول‌های محصول از یکدیگر جدا نگه داشته می‌شوند.

## ساختار فعلی
```text
lib/
  main.dart
  app/
    homagram_app.dart
    theme/app_theme.dart
  features/
    auth/
      data/auth_service.dart
      domain/auth_constants.dart
      presentation/
        auth_gate.dart
        auth_screen.dart
        password_recovery_screen.dart
        profile_home_screen.dart
    bootstrap/presentation/bootstrap_screen.dart
test/
docs/
supabase/migrations/
tool/
```

## اتصال Supabase
مقادیر از طریق Dart defines دریافت می‌شوند: `SUPABASE_URL` و `SUPABASE_PUBLISHABLE_KEY`.
کلید Publishable/Anon برای کلاینت است؛ کلید Secret و service_role فقط سمت سرور مجاز هستند. احراز هویت از PKCE استفاده می‌کند.

## حساب و پروفایل
- Supabase Auth مسئول اعتبارسنجی ایمیل و رمز عبور است.
- Trigger هنگام ایجاد حساب، پروفایل و تنظیمات پایه می‌سازد.
- شناسه پروفایل به `auth.users.id` متصل است.
- نام کاربری یکتا و نرمال‌شده است.
- RLS فعال است و کاربر فقط ردیف خودش را می‌خواند یا ویرایش می‌کند.
- مجوز UPDATE فقط برای ستون‌های مجاز داده شده؛ شناسه، نام کاربری و timestamp از کلاینت قابل تغییر نیست.

## تصمیم‌های باز
- انتخاب نهایی state management پس از شکل‌گیری جریان‌های واقعی اپ
- نمایش پروفایل عمومی و enforcement کامل privacy در مرحله شبکه اجتماعی
- پردازش و ذخیره‌سازی رسانه پیش از انتشار محتوا
- تماس‌ها و رمزنگاری سرتاسری به‌عنوان پروژه‌های فنی مستقل
