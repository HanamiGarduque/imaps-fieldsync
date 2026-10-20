/// Reads an ISO date/date-time as the stored calendar date, without applying a
/// timezone offset. Rejects malformed and overflowing dates instead of letting
/// DateTime normalize (for example) February 30 into March.
DateTime? parseLocalCalendarDate(Object? raw) {
  if (raw is! String) return null;
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?: ?[zZ]| ?[+-](\d{2})(?::?(\d{2}))?)?)?$',
  ).firstMatch(raw);
  if (parts == null) return null;
  // DateTime.tryParse also normalizes overflowing time/offset components.
  for (final (index, maximum) in [(4, 23), (5, 59), (6, 59), (7, 23), (8, 59)]) {
    if (int.parse(parts.group(index) ?? '0') > maximum) return null;
  }
  final year = int.parse(parts.group(1)!);
  final month = int.parse(parts.group(2)!);
  final day = int.parse(parts.group(3)!);
  final date = DateTime(year, month, day);
  return year > 0 && date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

/// Calendar days, not 24-hour periods (which differ across daylight saving).
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
