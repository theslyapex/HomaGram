# راه‌اندازی احراز هویت HomaGram

## تنظیمات لازم در Supabase Dashboard
در پروژه مستقل HomaGram، مسیر Authentication → URL Configuration، این مقدار را به Additional Redirect URLs اضافه کنید:
`homagram://auth-callback`

در Authentication → Providers → Email:
- ورود با Email و Password فعال باشد.
- Confirm email فعال باشد تا ثبت‌نام بدون تأیید ایمیل وارد نشست نشود.

این تنظیمات Dashboard از طریق اتصال فعلی قابل تغییر نبودند و باید در داشبورد اعمال و با ایمیل آزمایشی بررسی شوند.

## Android
پس از ساخت پلتفرم Android:
```bash
flutter create --platforms=android --project-name homagram --org com.homagram .
python3 tool/configure_android_manifest.py
```
Callback تأیید ایمیل و بازیابی رمز: `homagram://auth-callback`.

## اجرای محلی
```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```
فقط Publishable Key مجاز است در برنامه موبایل استفاده شود. هرگز Secret یا service_role key را در اپ یا مخزن قرار ندهید.

## مدل حساب
- ایمیل و رمز عبور
- تأیید ایمیل
- نام کاربری یکتا، ۳ تا ۲۴ نویسه: حروف کوچک انگلیسی، عدد و زیرخط
- نام نمایشی ۱ تا ۵۰ نویسه و بیو حداکثر ۱۶۰ نویسه
- ایجاد خودکار پروفایل و تنظیمات با Trigger دیتابیس
- ویرایش نام نمایشی و بیوگرافی
- تنظیم اولیه حساب خصوصی
- خروج از نشست فعلی یا سایر نشست‌ها
- بازیابی رمز از طریق ایمیل و callback اپلیکیشن

## محدودیت‌های فعلی
- نمایش عمومی پروفایل و اجرای کامل حریم خصوصی در مرحله شبکه اجتماعی تکمیل می‌شود.
- نام کاربری در این نسخه قابل تغییر نیست.
- فهرست جزئی نشست‌ها (نام دستگاه و زمان هر نشست) هنوز ساخته نشده؛ فعلاً خروج از سایر نشست‌ها ممکن است.
- تست انتها‌به‌انتها با ایمیل واقعی پس از ثبت Redirect URL و تنظیم Email Provider لازم است.
