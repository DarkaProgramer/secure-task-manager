import 'package:mobile/core/storage/token_store.dart';

/// In-memory [TokenStore] that records what the client saves.
class FakeTokenStore implements TokenStore {
  FakeTokenStore({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;
  String? savedAccessToken;
  String? savedRefreshToken;
  int clearCalls = 0;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    savedAccessToken = accessToken;
    savedRefreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    clearCalls++;
  }
}
