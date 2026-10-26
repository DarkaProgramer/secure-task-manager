import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/tasks/domain/task.dart';
import 'package:mobile/features/tasks/presentation/task_list_view.dart';

Widget _wrap({
  bool loading = false,
  List<Task> tasks = const [],
  String? errorMessage,
  VoidCallback? onRetry,
  ValueChanged<Task>? onToggle,
  ValueChanged<Task>? onDelete,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TaskListView(
        loading: loading,
        tasks: tasks,
        errorMessage: errorMessage,
        onRetry: onRetry ?? () {},
        onToggle: onToggle ?? (_) {},
        onDelete: onDelete ?? (_) {},
      ),
    ),
  );
}

void main() {
  const sample = Task(id: '1', title: 'Write tests', description: 'All of them', completed: false);

  testWidgets('shows a progress indicator while loading', (tester) async {
    await tester.pumpWidget(_wrap(loading: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the empty state', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.text('No tasks yet. Add your first task.'), findsOneWidget);
  });

  testWidgets('shows the error message and retries', (tester) async {
    var retried = 0;
    await tester.pumpWidget(_wrap(errorMessage: 'Could not connect', onRetry: () => retried++));
    expect(find.text('Could not connect'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('shows tasks and reports toggle and delete taps', (tester) async {
    Task? toggled;
    Task? deleted;
    await tester.pumpWidget(_wrap(
      tasks: [sample],
      onToggle: (task) => toggled = task,
      onDelete: (task) => deleted = task,
    ));
    expect(find.text('Write tests'), findsOneWidget);
    expect(find.text('All of them'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byTooltip('Delete task'));
    expect(toggled?.id, '1');
    expect(deleted?.id, '1');
  });
}
