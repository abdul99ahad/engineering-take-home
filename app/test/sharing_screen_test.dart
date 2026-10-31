import 'dart:convert';

import 'package:diary_app/api.dart';
import 'package:diary_app/main.dart';
import 'package:diary_app/sharing_screen.dart';
import 'package:diary_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const clinicians = [
  {'id': 1, 'name': 'Dr. Lena Hofmann', 'practice': 'Praxis Hofmann, München'},
  {'id': 2, 'name': 'Dr. Felix Braun', 'practice': 'Hausarztpraxis Schwabing'},
];
const activeShare = {
  'id': 1,
  'clinician_id': 1,
  'from_date': '2026-10-01',
  'to_date': '2026-10-07',
  'include_notes': false,
  'created_at': '2026-10-08T09:00:00Z',
  'revoked_at': null,
};
const stoppedShare = {
  'id': 2,
  'clinician_id': 2,
  'from_date': '2026-09-10',
  'to_date': '2026-09-20',
  'include_notes': true,
  'created_at': '2026-09-21T09:00:00Z',
  'revoked_at': '2026-09-22T10:00:00Z',
};
const entries = [
  {'id': 3, 'recorded_at': '2026-10-02T06:30:00Z', 'mood': 4, 'symptoms': [], 'note': null},
  {
    'id': 5,
    'recorded_at': '2026-10-04T06:30:00Z',
    'mood': 2,
    'symptoms': ['headache'],
    'note': 'Private',
  },
];
const visit = {
  'clinician_id': 1,
  'clinician_name': 'Dr. Lena Hofmann',
  'accessed_at': '2026-10-08T10:03:00Z',
  'entry_ids': [5, 3, 99],
};

/// A stand-in for the API with the given shares and access records.
ApiClient fakeApi(
  List<http.Request> requests, {
  List<Map<String, Object?>> shares = const [activeShare, stoppedShare],
  List<Map<String, Object?>> accessLog = const [visit],
}) {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  return ApiClient(
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/telemetry')) return http.Response('', 204);
      if (request.method == 'POST' && path.endsWith('/shares/1/revoke')) {
        return json({...activeShare, 'revoked_at': '2026-10-09T08:00:00Z'});
      }
      if (path.endsWith('/clinicians')) return json(clinicians);
      if (path.endsWith('/shares')) return json(shares);
      if (path.endsWith('/access-log')) return json(accessLog);
      if (path.endsWith('/entries')) return json(entries);
      return http.Response('Not found', 404);
    }),
  );
}

Future<void> openSharing(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SharingScreen(api: api),
    ),
  );
  await tester.pumpAndSettle();
}

bool sent(List<http.Request> requests, String method, String pathEnd) =>
    requests.any((r) => r.method == method && r.url.path.endsWith(pathEnd));

bool tracked(List<http.Request> requests, String event) =>
    requests.any((r) => r.url.path.endsWith('/telemetry') && r.body.contains('"$event"'));

void main() {
  testWidgets('opens sharing from the diary', (tester) async {
    final requests = <http.Request>[];
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DiaryApp(api: fakeApi(requests)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share with your doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Sharing'), findsOneWidget);
    expect(tracked(requests, 'sharing_opened'), isTrue);
  });

  testWidgets('lists active and stopped shares with doctor, days and data', (tester) async {
    await openSharing(tester, fakeApi([]));

    expect(find.text('Shared now'), findsOneWidget);
    expect(find.text('1 to 7 October · mood and symptoms'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.textContaining('10 to 20 September · mood, symptoms and notes'), findsOneWidget);
    expect(find.textContaining('stopped Tue 22 Sep'), findsOneWidget);
  });

  testWidgets('stopping a share asks first, then revokes', (tester) async {
    final requests = <http.Request>[];
    await openSharing(tester, fakeApi(requests));

    await tester.tap(find.widgetWithText(TextButton, 'Stop sharing'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sharing with Dr. Lena Hofmann?'), findsOneWidget);
    expect(sent(requests, 'POST', '/revoke'), isFalse);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Stop sharing')),
    );
    await tester.pumpAndSettle();

    expect(sent(requests, 'POST', '/shares/1/revoke'), isTrue);
    expect(tracked(requests, 'share_revoked'), isTrue);
  });

  testWidgets('keep sharing cancels the stop', (tester) async {
    final requests = <http.Request>[];
    await openSharing(tester, fakeApi(requests));

    await tester.tap(find.widgetWithText(TextButton, 'Stop sharing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep sharing'));
    await tester.pumpAndSettle();

    expect(sent(requests, 'POST', '/revoke'), isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a visit expands to show which entries the doctor saw', (tester) async {
    await openSharing(tester, fakeApi([]));
    expect(find.text("Your diary's visitors"), findsOneWidget);
    expect(find.textContaining('3 entries'), findsOneWidget);
    expect(find.text('Low'), findsNothing);

    await tester.tap(find.textContaining('3 entries'));
    await tester.pumpAndSettle();

    expect(find.text('Praxis Hofmann, München'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Headache'), findsOneWidget);
    expect(find.text('1 entry no longer in your diary'), findsOneWidget);
  });

  testWidgets('says so when nothing has been shared or seen yet', (tester) async {
    await openSharing(tester, fakeApi([], shares: [], accessLog: []));

    expect(find.textContaining("You haven't shared your diary yet."), findsOneWidget);
    expect(find.text('No doctor has opened your diary yet.'), findsOneWidget);
  });

  testWidgets('share diary opens the form', (tester) async {
    await openSharing(tester, fakeApi([]));

    await tester.tap(find.text('Share diary'));
    await tester.pumpAndSettle();

    expect(find.text('Share your diary'), findsOneWidget);
  });
}
