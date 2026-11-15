String persianDate(DateTime date) {
  final gy = date.year;
  final gm = date.month;
  final gd = date.day;
  final a = (14 - gm) ~/ 12;
  final y = gy + 4800 - a;
  final m = gm + 12 * a - 3;
  final jdn = gd + ((153 * m + 2) ~/ 5) + 365 * y + (y ~/ 4) - (y ~/ 100) + (y ~/ 400) - 32045;
  var depoch = jdn - _jalaliToJdn(475, 1, 1);
  final cycle = depoch ~/ 1029983;
  final cyear = depoch % 1029983;
  int ycycle;
  if (cyear == 1029982) {
    ycycle = 2820;
  } else {
    final aux1 = cyear ~/ 366;
    final aux2 = cyear % 366;
    ycycle = ((2134 * aux1 + 2816 * aux2 + 2815) ~/ 1028522) + aux1 + 1;
  }
  var jy = ycycle + 2820 * cycle + 474;
  if (jy <= 0) jy -= 1;
  final jalaliNewYear = _jalaliToJdn(jy, 1, 1);
  final yday = jdn - jalaliNewYear + 1;
  final jm = yday <= 186 ? ((yday - 1) ~/ 31) + 1 : ((yday - 187) ~/ 30) + 7;
  final jd = yday <= 186 ? ((yday - 1) % 31) + 1 : ((yday - 187) % 30) + 1;
  final value = '${jy.toString().padLeft(4, '0')}/${jm.toString().padLeft(2, '0')}/${jd.toString().padLeft(2, '0')}';
  const digits = '۰۱۲۳۴۵۶۷۸۹';
  return value.replaceAllMapped(RegExp(r'[0-9]'), (match) => digits[int.parse(match.group(0)!)]);
}

int _jalaliToJdn(int jy, int jm, int jd) {
  final epbase = jy - (jy >= 0 ? 474 : 473);
  final epyear = 474 + (epbase % 2820);
  final monthDays = jm <= 7 ? (jm - 1) * 31 : (jm - 1) * 30 + 6;
  return jd + monthDays +
      ((epyear * 682 - 110) ~/ 2816) +
      (epyear - 1) * 365 +
      (epbase ~/ 2820) * 1029983 +
      1948320;
}


String persianTime(DateTime date) {
  final value = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  const digits = '۰۱۲۳۴۵۶۷۸۹';
  return value.replaceAllMapped(
    RegExp(r'[0-9]'),
    (match) => digits[int.parse(match.group(0)!)],
  );
}

String persianDateTime(DateTime date) => '${persianDate(date)} • ${persianTime(date)}';


/// Converts a user-entered Jalali date (for example ۱۳۸۳/۱۱/۱۴) to Gregorian.
DateTime? parsePersianDate(String input) {
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var normalized = input.trim();
  for (var i = 0; i < 10; i++) {
    normalized = normalized.replaceAll(persianDigits[i], '$i');
    normalized = normalized.replaceAll(arabicDigits[i], '$i');
  }
  final match = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2}).firstMatch(normalized);
  if (match == null) return null;
  final jy = int.parse(match.group(1)!);
  final jm = int.parse(match.group(2)!);
  final jd = int.parse(match.group(3)!);
  if (jy < 1300 || jy > 1600 || jm < 1 || jm > 12 || jd < 1) return null;
  final firstDay = _jalaliToJdn(jy, jm, 1);
  final nextMonth = jm == 12 ? _jalaliToJdn(jy + 1, 1, 1) : _jalaliToJdn(jy, jm + 1, 1);
  if (jd > nextMonth - firstDay) return null;
  final g = _jdnToGregorian(firstDay + jd - 1);
  final result = DateTime(g.$1, g.$2, g.$3);
  if (result.isAfter(DateTime.now())) return null;
  return result;
}

(int, int, int) _jdnToGregorian(int jdn) {
  var l = jdn + 68569;
  final n = (4 * l) ~/ 146097;
  l -= (146097 * n + 3) ~/ 4;
  final i = (4000 * (l + 1)) ~/ 1461001;
  l = l - (1461 * i) ~/ 4 + 31;
  final j = (80 * l) ~/ 2447;
  final day = l - (2447 * j) ~/ 80;
  l = j ~/ 11;
  final month = j + 2 - 12 * l;
  final year = 100 * (n - 49) + i + l;
  return (year, month, day);
}
).firstMatch(normalized);
  if (match == null) return null;
  final jy = int.parse(match.group(1)!);
  final jm = int.parse(match.group(2)!);
  final jd = int.parse(match.group(3)!);
  if (jy < 1300 || jy > 1600 || jm < 1 || jm > 12 || jd < 1) return null;
  final firstDay = _jalaliToJdn(jy, jm, 1);
  final nextMonth = jm == 12 ? _jalaliToJdn(jy + 1, 1, 1) : _jalaliToJdn(jy, jm + 1, 1);
  if (jd > nextMonth - firstDay) return null;
  final g = _jdnToGregorian(firstDay + jd - 1);
  final result = DateTime(g.$1, g.$2, g.$3);
  if (result.isAfter(DateTime.now())) return null;
  return result;
}

(int, int, int) _jdnToGregorian(int jdn) {
  var l = jdn + 68569;
  final n = (4 * l) ~/ 146097;
  l -= (146097 * n + 3) ~/ 4;
  final i = (4000 * (l + 1)) ~/ 1461001;
  l = l - (1461 * i) ~/ 4 + 31;
  final j = (80 * l) ~/ 2447;
  final day = l - (2447 * j) ~/ 80;
  l = j ~/ 11;
  final month = j + 2 - 12 * l;
  final year = 100 * (n - 49) + i + l;
  return (year, month, day);
}
