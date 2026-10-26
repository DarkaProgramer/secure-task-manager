import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/tasks/presentation/task_page.dart';

void main() {
  runApp(const ProviderScope(child: TaskManagerApp()));
}

/// Root widget: shows the login or task screen depending on the session.
class TaskManagerApp extends StatelessWidget {
  /// Creates the application.
  const TaskManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authControllerProvider.select((s) => s.status));
    return switch (status) {
      AuthStatus.unknown =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.signedOut => const LoginPage(),
      AuthStatus.signedIn => const TaskPage(),
    };
  }
}
