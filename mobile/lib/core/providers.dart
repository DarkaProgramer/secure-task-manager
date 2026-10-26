/// Riverpod providers shared across features.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../features/auth/presentation/auth_controller.dart';
import 'network/api_client.dart';
import 'storage/token_store.dart';

/// Provides the secure token store.
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(const FlutterSecureStorage()),
);

/// Provides one shared HTTP client that is closed with the provider scope.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Provides the API client; failed refreshes sign the user out.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.read(httpClientProvider),
    ref.read(tokenStoreProvider),
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});
