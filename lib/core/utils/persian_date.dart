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
  return '${jy.toString().padLeft(4, '0')}/${jm.toString().padLeft(2, '0')}/${jd.toString().padLeft(2, '0')}';
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
