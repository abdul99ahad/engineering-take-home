const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime dayOf(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String formatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// "Tuesday, 13 October"
String formatLongDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${day.day} ${_months[day.month - 1]}';

/// "Today", "Yesterday" or "Sat 10 Oct"
String formatDayHeading(DateTime day, DateTime today) {
  final daysAgo = dayOf(today).difference(day).inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1].substring(0, 3)} ${day.day} '
      '${_months[day.month - 1].substring(0, 3)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "2026-10-01": the calendar date the API expects.
String isoDate(DateTime day) => '${day.year}-${_two(day.month)}-${_two(day.day)}';

/// "24 to 30 October", "28 September to 4 October" or "5 October".
String formatDateRange(DateTime from, DateTime to) {
  final end = '${to.day} ${_months[to.month - 1]}';
  if (dayOf(from) == dayOf(to)) return end;
  if (from.year == to.year && from.month == to.month) return '${from.day} to $end';
  return '${from.day} ${_months[from.month - 1]} to $end';
}

/// "Thu 8 Oct, 12:03", in local time.
String formatShortDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_weekdays[local.weekday - 1].substring(0, 3)} ${local.day} '
      '${_months[local.month - 1].substring(0, 3)}, ${formatTime(local)}';
}
