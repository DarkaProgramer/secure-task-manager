/// The signed-in screen: task list, add dialog, delete confirmation, logout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../domain/task.dart';
import 'task_controller.dart';
import 'task_list_view.dart';

/// Shows the user's tasks and lets them add, complete, and delete tasks.
class TaskPage extends ConsumerWidget {
  /// Creates the task page.
  const TaskPage({super.key});

  void _showMessage(BuildContext context, String? message) {
    if (message == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String title, String? description})>(
      context: context,
      builder: (_) => const _NewTaskDialog(),
    );
    if (result == null) return;
    final error = await ref
        .read(taskControllerProvider.notifier)
        .add(result.title, result.description);
    if (context.mounted) _showMessage(context, error);
  }

  Future<void> _deleteTask(BuildContext context, WidgetRef ref, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.title}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await ref.read(taskControllerProvider.notifier).remove(task);
    if (context.mounted) _showMessage(context, error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskControllerProvider);
    final controller = ref.read(taskControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My tasks'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: TaskListView(
        loading: state.loading,
        tasks: state.tasks,
        errorMessage: state.errorMessage,
        onRetry: controller.load,
        onToggle: (task) async {
          final error = await controller.toggle(task);
          if (context.mounted) _showMessage(context, error);
        },
        onDelete: (task) => _deleteTask(context, ref, task),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => _addTask(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NewTaskDialog extends StatefulWidget {
  const _NewTaskDialog();

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final description = _description.text.trim();
    Navigator.pop(context, (
      title: _title.text.trim(),
      description: description.isEmpty ? null : description,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New task'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter a title.'
                  : null,
              textInputAction: TextInputAction.next,
            ),
            TextFormField(
              controller: _description,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
