import 'package:diary_app/format.dart';
import 'package:diary_app/models.dart';
import 'package:diary_app/sharing_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const lena = Clinician(id: 1, name: 'Dr. Lena Hofmann', practice: 'Praxis Hofmann, München');

void main() {
  group('periodRange', () {
    test('last 7 days is today and the 6 days before, as whole days', () {
      final range = periodRange(Period.last7Days, DateTime(2026, 10, 30, 23, 59));

      expect(range.from, DateTime(2026, 10, 24));
      expect(range.to, DateTime(2026, 10, 30));
    });

    test('last 30 days crosses into the previous month', () {
      final range = periodRange(Period.last30Days, DateTime(2026, 10, 30, 8, 0));

      expect(range.from, DateTime(2026, 10, 1));
      expect(range.to, DateTime(2026, 10, 30));
    });
  });

  group('dates', () {
    test('isoDate is the calendar date the API expects', () {
      expect(isoDate(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
    });

    test('formatDateRange reads naturally', () {
      expect(formatDateRange(DateTime(2026, 10, 24), DateTime(2026, 10, 30)), '24 to 30 October');
      expect(
        formatDateRange(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
        '28 September to 4 October',
      );
      expect(formatDateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 5)), '5 October');
    });

    test('formatShortDateTime shows day, date and time', () {
      expect(formatShortDateTime(DateTime(2026, 10, 8, 12, 3)), 'Thu 8 Oct, 12:03');
    });
  });

  group('consentTerms', () {
    test('without notes, says notes stay private', () {
      expect(
        consentTerms(
          clinician: lena,
          from: DateTime(2026, 10, 24),
          to: DateTime(2026, 10, 30),
          includeNotes: false,
        ),
        [
          'Dr. Lena Hofmann (Praxis Hofmann, München) may read your diary.',
          'They will see your mood and symptoms. Your notes stay private.',
          'Only entries from 24 to 30 October, as the days appear in your diary.',
          'You can stop sharing at any time in Sharing. It takes effect straight away.',
          'Each time your doctor opens your diary, it is recorded and shown to you. '
              'These records are kept for 10 years.',
        ],
      );
    });

    test('with notes, says notes are shared', () {
      final terms = consentTerms(
        clinician: lena,
        from: DateTime(2026, 10, 24),
        to: DateTime(2026, 10, 30),
        includeNotes: true,
      );

      expect(terms[1], 'They will see your mood, symptoms and notes.');
    });

    test('the consent version matches the backend', () {
      expect(consentVersion, '2026-10-v1');
    });
  });
}
