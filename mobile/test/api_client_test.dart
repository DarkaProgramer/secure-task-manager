import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/network/api_client.dart';

import 'support/fake_token_store.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('refreshes once on 401 and retries the original request once', () async {
    var originalCalls = 0;
    var refreshCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return _json({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}, 200);
      }
      originalCalls++;
      if (originalCalls == 1) return http.Response('{}', 401);
      expect(request.headers['authorization'], 'Bearer new-access');
      return _json({'items': []}, 200);
    });
    final tokens = FakeTokenStore(accessToken: 'old-access', refreshToken: 'old-refresh');
    final client = ApiClient(mock, tokens);

    await client.send('GET', 'tasks');

    expect(refreshCalls, 1);
    expect(originalCalls, 2);
    expect(tokens.savedAccessToken, 'new-access');
    expect(tokens.savedRefreshToken, 'new-refresh');
  });

  test('keeps the query string intact instead of encoding the question mark', () async {
    Uri? seen;
    final mock = MockClient((request) async {
      seen = request.url;
      return _json({'items': []}, 200);
    });
    final client = ApiClient(mock, FakeTokenStore(accessToken: 'a', refreshToken: 'r'));

    await client.send('GET', 'tasks?page=2&limit=5');

    expect(seen!.path, endsWith('/api/v1/tasks'));
    expect(seen!.queryParameters, {'page': '2', 'limit': '5'});
  });

  test('concurrent 401 responses share a single refresh request', () async {
    var refreshCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _json({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}, 200);
      }
      if (request.headers['authorization'] == 'Bearer new-access') {
        return _json({'items': []}, 200);
      }
      return http.Response('{}', 401);
    });
    final tokens = FakeTokenStore(accessToken: 'old-access', refreshToken: 'old-refresh');
    final client = ApiClient(mock, tokens);

    await Future.wait([client.send('GET', 'tasks'), client.send('GET', 'tasks')]);

    expect(refreshCalls, 1);
  });

  test('a rejected refresh clears tokens, signs out, and throws a safe error', () async {
    var expired = 0;
    final mock = MockClient((request) async => http.Response('{}', 401));
    final tokens = FakeTokenStore(accessToken: 'old-access', refreshToken: 'old-refresh');
    final client = ApiClient(mock, tokens, onSessionExpired: () => expired++);

    await expectLater(
      client.send('GET', 'tasks'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );

    expect(expired, 1);
    expect(tokens.clearCalls, 1);
    expect(tokens.refreshToken, isNull);
  });

  test('a 401 after a successful refresh does not loop', () async {
    var refreshCalls = 0;
    var originalCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return _json({'accessToken': 'a2', 'refreshToken': 'r2'}, 200);
      }
      originalCalls++;
      return http.Response('{}', 401);
    });
    final client = ApiClient(mock, FakeTokenStore(accessToken: 'a', refreshToken: 'r'));

    await expectLater(client.send('GET', 'tasks'), throwsA(isA<ApiException>()));

    expect(refreshCalls, 1);
    expect(originalCalls, 2);
  });

  test('being offline during refresh does not sign the user out', () async {
    var expired = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) throw TimeoutException('offline');
      return http.Response('{}', 401);
    });
    final tokens = FakeTokenStore(accessToken: 'old-access', refreshToken: 'old-refresh');
    final client = ApiClient(mock, tokens, onSessionExpired: () => expired++);

    await expectLater(client.send('GET', 'tasks'), throwsA(isA<ApiException>()));

    expect(expired, 0);
    expect(tokens.refreshToken, 'old-refresh');
  });

  test('a failed login reports bad credentials and never tries to refresh', () async {
    var refreshCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) refreshCalls++;
      return http.Response('{}', 401);
    });
    final client = ApiClient(mock, FakeTokenStore(refreshToken: 'r'));

    await expectLater(
      client.send('POST', 'auth/login', body: {'email': 'a@b.co', 'password': 'x'}),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid email or password.')),
    );
    expect(refreshCalls, 0);
  });

  test('exceptions never contain tokens or the raw server body', () async {
    final mock = MockClient((request) async =>
        http.Response('SQL error near token secret-token-value', 500));
    final client = ApiClient(
      mock,
      FakeTokenStore(accessToken: 'secret-access', refreshToken: 'secret-refresh'),
    );

    try {
      await client.send('GET', 'tasks');
      fail('expected an ApiException');
    } on ApiException catch (error) {
      expect(error.message, isNot(contains('secret')));
      expect(error.message, isNot(contains('SQL')));
      expect(error.statusCode, 500);
    }
  });

  test('network failures become a safe connection message', () async {
    final mock = MockClient((request) async => throw Exception('socket: secret-access'));
    final client = ApiClient(mock, FakeTokenStore(accessToken: 'secret-access'));

    try {
      await client.send('GET', 'tasks');
      fail('expected an ApiException');
    } on ApiException catch (error) {
      expect(error.message, contains('Could not connect'));
      expect(error.message, isNot(contains('secret')));
    }
  });

  test('204 responses decode to an empty map', () async {
    final mock = MockClient((request) async => http.Response('', 204));
    final client = ApiClient(mock, FakeTokenStore(accessToken: 'a'));
    expect(await client.send('DELETE', 'tasks/abc'), isEmpty);
  });

  test('malformed JSON becomes a safe error', () async {
    final mock = MockClient((request) async => http.Response('<html>oops</html>', 200));
    final client = ApiClient(mock, FakeTokenStore(accessToken: 'a'));
    await expectLater(client.send('GET', 'tasks'), throwsA(isA<ApiException>()));
  });
}
