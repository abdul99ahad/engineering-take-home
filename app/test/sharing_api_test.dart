import 'dart:convert';

import 'package:diary_app/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const shareJson = {
  'id': 3,
  'clinician_id': 1,
  'from_date': '2026-10-24',
  'to_date': '2026-10-30',
  'include_notes': false,
  'created_at': '2026-10-30T09:12:00Z',
  'revoked_at': null,
};

/// Answers every request with [body] and remembers the requests it saw.
ApiClient apiReplying(Object body, int status, List<http.Request> requests) {
  return ApiClient(
    client: MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    }),
  );
}

void main() {
  test('createShare sends the period as calendar dates', () async {
    final requests = <http.Request>[];
    final api = apiReplying(shareJson, 201, requests);

    final share = await api.createShare(
      clinicianId: 1,
      from: DateTime(2026, 10, 24),
      to: DateTime(2026, 10, 30, 18, 0),
      includeNotes: false,
    );

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, endsWith('/shares'));
    expect(jsonDecode(requests.single.body), {
      'clinician_id': 1,
      'from_date': '2026-10-24',
      'to_date': '2026-10-30',
      'include_notes': false,
    });
    expect(share.id, 3);
    expect(share.isActive, isTrue);
  });

  test('createShare fails loudly when the API refuses', () async {
    final api = apiReplying({'detail': 'Unknown clinician'}, 422, []);

    expect(
      api.createShare(
        clinicianId: 99,
        from: DateTime(2026, 10, 24),
        to: DateTime(2026, 10, 30),
        includeNotes: false,
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('revokeShare posts to the share and returns it stopped', () async {
    final requests = <http.Request>[];
    final api = apiReplying({...shareJson, 'revoked_at': '2026-10-31T08:00:00Z'}, 200, requests);

    final share = await api.revokeShare(3);

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, endsWith('/shares/3/revoke'));
    expect(share.isActive, isFalse);
    expect(share.revokedAt, DateTime.utc(2026, 10, 31, 8));
  });

  test('listShares parses the share fields', () async {
    final api = apiReplying([shareJson], 200, []);

    final share = (await api.listShares()).single;

    expect(share.clinicianId, 1);
    expect(share.fromDate, DateTime(2026, 10, 24));
    expect(share.toDate, DateTime(2026, 10, 30));
    expect(share.includeNotes, isFalse);
    expect(share.createdAt, DateTime.utc(2026, 10, 30, 9, 12));
  });

  test('listAccessLog parses the API.md example', () async {
    final api = apiReplying(
      [
        {
          'clinician_id': 1,
          'clinician_name': 'Dr. Lena Hofmann',
          'accessed_at': '2026-10-08T10:03:00Z',
          'entry_ids': [3, 5],
        },
      ],
      200,
      [],
    );

    final record = (await api.listAccessLog()).single;

    expect(record.clinicianId, 1);
    expect(record.clinicianName, 'Dr. Lena Hofmann');
    expect(record.accessedAt, DateTime.utc(2026, 10, 8, 10, 3));
    expect(record.entryIds, [3, 5]);
  });

  test('listClinicians parses name and practice', () async {
    final api = apiReplying(
      [
        {'id': 1, 'name': 'Dr. Lena Hofmann', 'practice': 'Praxis Hofmann, München'},
      ],
      200,
      [],
    );

    final clinician = (await api.listClinicians()).single;

    expect(
      (clinician.id, clinician.name, clinician.practice),
      (1, 'Dr. Lena Hofmann', 'Praxis Hofmann, München'),
    );
  });
}
