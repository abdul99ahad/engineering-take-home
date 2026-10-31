import 'dart:convert';

import 'package:diary_app/api.dart';
import 'package:diary_app/share_form_screen.dart';
import 'package:diary_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final today = DateTime(2026, 10, 30, 9, 0);

/// A stand-in for the API: two doctors, and sharing answers with [shareStatus].
ApiClient fakeApi(List<http.Request> requests, {int shareStatus = 201}) {
  return ApiClient(
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/clinicians')) {
        return http.Response(
          jsonEncode([
            {'id': 2, 'name': 'Dr. Felix Braun', 'practice': 'Hausarztpraxis Schwabing'},
            {'id': 1, 'name': 'Dr. Lena Hofmann', 'practice': 'Praxis Hofmann, München'},
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.method == 'POST' && path.endsWith('/shares')) {
        if (shareStatus != 201) return http.Response('{"detail":"Internal server error"}', 500);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({...body, 'id': 1, 'created_at': '2026-10-30T09:00:00Z', 'revoked_at': null}),
          201,
        );
      }
      if (request.method == 'POST' && path.endsWith('/telemetry')) return http.Response('', 204);
      return http.Response('Not found', 404);
    }),
  );
}

/// Opens the form from a button, like the app does, and keeps what the form returns.
Future<List<bool?>> openForm(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ShareFormScreen(api: api, now: () => today),
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

bool shareButtonEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Share my diary')).onPressed !=
    null;

const agreement = 'I agree to share my diary on these terms.';

void main() {
  testWidgets('share button is disabled until a doctor is chosen and consent is ticked', (
    tester,
  ) async {
    await openForm(tester, fakeApi([]));
    expect(shareButtonEnabled(tester), isFalse);
    expect(find.text("Choose your doctor to see what you're agreeing to."), findsOneWidget);

    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.pumpAndSettle();
    expect(shareButtonEnabled(tester), isFalse);

    await tester.tap(find.text(agreement));
    await tester.pumpAndSettle();
    expect(shareButtonEnabled(tester), isTrue);
  });

  testWidgets('consent panel names the doctor, the data and the days', (tester) async {
    await openForm(tester, fakeApi([]));

    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.pumpAndSettle();

    expect(find.text('Your consent'), findsOneWidget);
    expect(find.text('Dr. Lena Hofmann (Praxis Hofmann, München) may read your diary.'), findsOne);
    expect(find.text('They will see your mood and symptoms. Your notes stay private.'), findsOne);
    expect(
      find.text('Only entries from 24 to 30 October, as the days appear in your diary.'),
      findsOne,
    );
    expect(find.text('Version 2026-10-v1 of these terms'), findsOne);
  });

  testWidgets('choosing the last 30 days changes the consent', (tester) async {
    await openForm(tester, fakeApi([]));
    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();

    expect(
      find.text('Only entries from 1 to 30 October, as the days appear in your diary.'),
      findsOne,
    );
  });

  testWidgets('turning on notes changes the consent wording', (tester) async {
    await openForm(tester, fakeApi([]));
    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.tap(find.text('Include my notes'));
    await tester.pumpAndSettle();

    expect(find.text('They will see your mood, symptoms and notes.'), findsOne);
  });

  testWidgets('changing what is shared clears the consent tick', (tester) async {
    await openForm(tester, fakeApi([]));
    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(agreement));
    await tester.pumpAndSettle();
    expect(shareButtonEnabled(tester), isTrue);

    await tester.tap(find.text('Include my notes'));
    await tester.pumpAndSettle();

    expect(shareButtonEnabled(tester), isFalse);
  });

  testWidgets('shares with the chosen options, tracks it and closes', (tester) async {
    final requests = <http.Request>[];
    final results = await openForm(tester, fakeApi(requests));
    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(agreement));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share my diary'));
    await tester.pumpAndSettle();

    final sent = requests.singleWhere((r) => r.method == 'POST' && r.url.path.endsWith('/shares'));
    expect(jsonDecode(sent.body), {
      'clinician_id': 1,
      'from_date': '2026-10-24',
      'to_date': '2026-10-30',
      'include_notes': false,
    });
    expect(
      requests.where((r) => r.url.path.endsWith('/telemetry')).single.body,
      contains('share_created'),
    );
    expect(results, [true]);
  });

  testWidgets('shows an error and stays open when sharing fails', (tester) async {
    final results = await openForm(tester, fakeApi([], shareStatus: 500));
    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(agreement));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share my diary'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't share your diary. Try again."), findsOneWidget);
    expect(find.text('Share your diary'), findsOneWidget);
    expect(results, isEmpty);
    expect(shareButtonEnabled(tester), isTrue);
  });
}
