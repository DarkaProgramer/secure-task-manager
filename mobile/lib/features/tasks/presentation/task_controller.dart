/// Holds task-list state outside the widget tree.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/task_repository.dart';
import '../domain/task.dart';

/// Provides the task repository.
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.read(apiClientProvider)),
);

/// Immutable state for the task list screen.
class TaskListState {
  /// Creates a task list state.
  const TaskListState({
    this.loading = false,
    this.tasks = const [],
    this.errorMessage,
  });

  /// Whether the first load is in progress.
  final bool loading;

  /// Tasks loaded from the API.
  final List<Task> tasks;

  /// Safe error message when loading failed.
  final String? errorMessage;
}

/// Loads and mutates the signed-in user's tasks.
class TaskController extends Notifier<TaskListState> {
  @override
  TaskListState build() {
    // Rebuilding on every auth change discards the previous user's tasks.
    final status = ref.watch(authControllerProvider.select((s) => s.status));
    if (status != AuthStatus.signedIn) return const TaskListState();
    Future.microtask(load);
    return const TaskListState(loading: true);
  }

  /// Loads the first page of tasks, replacing the current state.
  Future<void> load() async {
    state = const TaskListState(loading: true);
    try {
      final tasks = await ref.read(taskRepositoryProvider).list();
      state = TaskListState(tasks: tasks);
    } on ApiException catch (error) {
      state = TaskListState(errorMessage: error.message);
    } catch (_) {
      state = const TaskListState(
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Creates a task. Returns an error message, or null on success.
  Future<String?> add(String title, String? description) async {
    try {
      final task = await ref.read(taskRepositoryProvider).create(title, description);
      state = TaskListState(tasks: [task, ...state.tasks]);
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// Toggles completion. Returns an error message, or null on success.
  Future<String?> toggle(Task task) async {
    try {
      final updated =
          await ref.read(taskRepositoryProvider).setCompleted(task, !task.completed);
      state = TaskListState(
        tasks: [for (final t in state.tasks) t.id == updated.id ? updated : t],
      );
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// Deletes a task. Returns an error message, or null on success.
  Future<String?> remove(Task task) async {
    try {
      await ref.read(taskRepositoryProvider).delete(task.id);
      state = TaskListState(
        tasks: state.tasks.where((t) => t.id != task.id).toList(),
      );
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }
}

/// Provides the task list state and its actions.
final taskControllerProvider =
    NotifierProvider<TaskController, TaskListState>(TaskController.new);
