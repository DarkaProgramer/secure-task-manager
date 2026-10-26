/// Holds the signed-in or signed-out state of the application.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';

/// Provides the authentication repository.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.read(apiClientProvider),
    ref.read(tokenStoreProvider),
  ),
);

/// Whether a session exists on this device.
enum AuthStatus {
  /// Stored credentials have not been checked yet.
  unknown,

  /// No session; the login screen is shown.
  signedOut,

  /// A session exists; the task screen is shown.
  signedIn,
}

/// Immutable authentication state for the UI.
class AuthState {
  /// Creates an authentication state.
  const AuthState({
    required this.status,
    this.busy = false,
    this.errorMessage,
  });

  /// Current session status.
  final AuthStatus status;

  /// Whether a login, registration, or logout request is running.
  final bool busy;

  /// Safe message to show on the login screen, if any.
  final String? errorMessage;
}

/// Coordinates login, registration, logout, and session expiration.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState(status: AuthStatus.unknown);
  }

  Future<void> _restore() async {
    final hasSession = await ref.read(authRepositoryProvider).hasStoredSession();
    state = AuthState(
      status: hasSession ? AuthStatus.signedIn : AuthStatus.signedOut,
    );
  }

  /// Signs in with [email] and [password].
  Future<void> login(String email, String password) =>
      _authenticate(() => ref.read(authRepositoryProvider).login(email, password));

  /// Creates an account and signs in.
  Future<void> register(String email, String password) => _authenticate(
        () => ref.read(authRepositoryProvider).register(email, password),
      );

  Future<void> _authenticate(Future<void> Function() action) async {
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    try {
      await action();
      state = const AuthState(status: AuthStatus.signedIn);
    } on ApiException catch (error) {
      state = AuthState(status: AuthStatus.signedOut, errorMessage: error.message);
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.signedOut,
        errorMessage: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Revokes the session on the server (best effort) and clears local tokens.
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Called by the API client after a refresh fails and tokens were cleared.
  void sessionExpired() {
    state = const AuthState(
      status: AuthStatus.signedOut,
      errorMessage: 'Your session has expired. Please sign in again.',
    );
  }
}

/// Provides the authentication state and its actions.
final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
