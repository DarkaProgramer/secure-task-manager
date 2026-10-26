import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/tasks/data/task_repository.dart';
import 'package:mobile/features/tasks/domain/task.dart';

import 'support/fake_token_store.dart';

Map<String, dynamic> _taskJson({String id = 't1', bool completed = false, String? description}) => {
      'id': id,
      'title': 'Write tests',
      'description': description,
      'completed': completed,
      'ownerId': 'server-side-only',
    };

TaskRepository _repo(MockClientHandler handler) => TaskRepository(
      ApiClient(MockClient(handler), FakeTokenStore(accessToken: 'a', refreshToken: 'r')),
    );

void main() {
  test('Task.fromJson parses the API shape and ignores extra fields', () {
    final task = Task.fromJson(_taskJson(description: 'details'));
    expect(task.id, 't1');
    expect(task.description, 'details');
    expect(task.completed, isFalse);
  });

  test('Task.toWriteJson never includes an owner or user id', () {
    final json = Task.fromJson(_taskJson()).toWriteJson();
    expect(json.keys, unorderedEquals(['title', 'description', 'completed']));
  });

  test('list parses items', () async {
    final repo = _repo((request) async => http.Response(
          jsonEncode({'items': [_taskJson(), _taskJson(id: 't2')], 'page': 1, 'limit': 20}),
          200,
        ));
    final tasks = await repo.list();
    expect(tasks.map((t) => t.id), ['t1', 't2']);
  });

  test('list handles an empty result', () async {
    final repo = _repo((request) async => http.Response(jsonEncode({'items': []}), 200));
    expect(await repo.list(), isEmpty);
  });

  test('create omits a blank description and trims the title', () async {
    Map<String, dynamic>? sent;
    final repo = _repo((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'item': _taskJson()}), 201);
    });
    await repo.create('  Buy milk  ', '   ');
    expect(sent, {'title': 'Buy milk'});
  });

  test('setCompleted sends a PATCH with only the completed flag', () async {
    late http.Request seen;
    final repo = _repo((request) async {
      seen = request;
      return http.Response(jsonEncode({'item': _taskJson(completed: true)}), 200);
    });
    final updated = await repo.setCompleted(Task.fromJson(_taskJson()), true);
    expect(seen.method, 'PATCH');
    expect(seen.url.path, endsWith('/tasks/t1'));
    expect(jsonDecode(seen.body), {'completed': true});
    expect(updated.completed, isTrue);
  });

  test('delete sends DELETE and accepts 204', () async {
    late http.Request seen;
    final repo = _repo((request) async {
      seen = request;
      return http.Response('', 204);
    });
    await repo.delete('t1');
    expect(seen.method, 'DELETE');
  });

  test('a server error surfaces as ApiException', () async {
    final repo = _repo((request) async => http.Response('boom', 500));
    await expectLater(repo.list(), throwsA(isA<ApiException>()));
  });
}
