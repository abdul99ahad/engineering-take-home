import 'format.dart';
import 'models.dart';

/// The version of the consent wording below. The backend stores the same value with every share
/// (O.Cons_3), so change both together whenever the wording changes.
const consentVersion = '2026-10-v1';

enum Period { last7Days, last30Days }

/// The calendar days a preset covers, ending today. Whole local days, as the patient's diary
/// shows them.
({DateTime from, DateTime to}) periodRange(Period period, DateTime now) {
  final today = dayOf(now);
  final days = switch (period) {
    Period.last7Days => 7,
    Period.last30Days => 30,
  };
  return (from: DateTime(today.year, today.month, today.day - (days - 1)), to: today);
}

/// What the patient agrees to before sharing (O.Purp_1): who, which data and which days.
List<String> consentTerms({
  required Clinician clinician,
  required DateTime from,
  required DateTime to,
  required bool includeNotes,
}) => [
  '${clinician.name} (${clinician.practice}) may read your diary.',
  includeNotes
      ? 'They will see your mood, symptoms and notes.'
      : 'They will see your mood and symptoms. Your notes stay private.',
  'Only entries from ${formatDateRange(from, to)}, as the days appear in your diary.',
  'You can stop sharing at any time in Sharing. It takes effect straight away.',
  'Each time your doctor opens your diary, it is recorded and shown to you. '
      'These records are kept for 10 years.',
];
