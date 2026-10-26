/// Sends authenticated requests to the versioned Task Manager API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../storage/token_store.dart';

/// A safe API failure with a user-displayable message.
class ApiException implements Exception {
  /// Creates an API exception.
  const ApiException(this.message, {this.statusCode});

  /// A safe message that does not contain server internals.
  final String message;

  /// HTTP status code, when available.
  final int? statusCode;

  @override
  String toString() => message;
}

const String _sessionExpiredMessage =
    'Your session has expired. Please sign in again.';

/// Builds requests, attaches tokens, and performs one refresh-and-retry cycle.
class ApiClient {
  /// Creates a client with injectable HTTP and token-storage dependencies.
  ApiClient(this._http, this._tokens, {this.onSessionExpired});

  final http.Client _http;
  final TokenStore _tokens;

  /// Called after refresh fails and local credentials have been cleared.
  final VoidCallback? onSessionExpired;

  Future<bool>? _refreshInFlight;

  static const Set<String> _authPaths = {
    'auth/refresh',
    'auth/login',
    'auth/register',
    'auth/logout',
  };

  /// Builds a fresh request so the request can safely be retried.
  ///
  /// [path] may include a query string, for example `tasks?page=1&limit=20`.
  Future<http.Request> _buildRequest(
    String method,
    String path,
    Map<String, dynamic>? body, {
    bool withAuth = true,
  }) async {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final relative = Uri.parse(path);
    final joinedPath = '${base.path}/${relative.path}'.replaceAll(RegExp(r'/+'), '/');
    final uri = base.replace(
      path: joinedPath,
      query: relative.hasQuery ? relative.query : null,
    );
    final request = http.Request(method, uri)
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = 'application/json';

    if (withAuth) {
      final token = await _tokens.readAccessToken();
      if (token != null) request.headers['authorization'] = 'Bearer $token';
    }
    if (body != null) request.body = jsonEncode(body);
    return request;
  }

  /// Sends a JSON request and returns its decoded response object.
  ///
  /// A protected request that receives 401 may refresh once and retry once.
  /// Throws [ApiException] for unsuccessful responses or malformed JSON.
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final isAuthPath = _authPaths.contains(path);
    var response = await _sendRequest(
      await _buildRequest(method, path, body, withAuth: !isAuthPath),
    );

    if (response.statusCode == 401 && !isAuthPath) {
      if (!await _refreshTokens()) {
        throw const ApiException(_sessionExpiredMessage, statusCode: 401);
      }
      response = await _sendRequest(await _buildRequest(method, path, body));
      if (response.statusCode == 401) {
        // A freshly issued token was rejected, so the session cannot continue.
        await _expireSession();
        throw const ApiException(_sessionExpiredMessage, statusCode: 401);
      }
    }

    return _decodeResponse(response, path);
  }

  Future<http.Response> _sendRequest(http.Request request) async {
    try {
      final streamed = await _http.send(request).timeout(
            const Duration(seconds: 15),
          );
      return await http.Response.fromStream(streamed);
    } catch (_) {
      throw const ApiException(
        'Could not connect to the server. Check your connection and try again.',
      );
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response, String path) {
    final status = response.statusCode;
    if (status == 401) {
      throw ApiException(
        path == 'auth/login'
            ? 'Invalid email or password.'
            : _sessionExpiredMessage,
        statusCode: 401,
      );
    }
    if (status == 409) {
      throw ApiException(
        'An account with this email already exists.',
        statusCode: status,
      );
    }
    if (status == 400) {
      throw ApiException(
        'Check the values you entered and try again.',
        statusCode: status,
      );
    }
    if (status == 429) {
      throw ApiException(
        'Too many attempts. Please wait a few minutes and try again.',
        statusCode: status,
      );
    }
    if (status < 200 || status >= 300) {
      throw ApiException(
        'The request could not be completed. Try again.',
        statusCode: status,
      );
    }
    if (status == 204 || response.body.isEmpty) return {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through to the generic message below.
    }
    throw const ApiException('The server returned unexpected data.');
  }

  /// Refreshes credentials once; concurrent callers share the same operation.
  Future<bool> _refreshTokens() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _performRefresh().whenComplete(() => _refreshInFlight = null);
    _refreshInFlight = refresh;
    return refresh;
  }

  /// Returns true when new tokens were saved and false when the session ended.
  ///
  /// Network failures and server errors throw [ApiException] and keep the
  /// stored tokens, so being offline does not sign the user out.
  Future<bool> _performRefresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null) return _expireSession();

    final response = await _sendRequest(
      await _buildRequest(
        'POST',
        'auth/refresh',
        {'refreshToken': refreshToken},
        withAuth: false,
      ),
    );

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final accessToken = decoded['accessToken'];
          final newRefreshToken = decoded['refreshToken'];
          if (accessToken is String && newRefreshToken is String) {
            await _tokens.saveTokens(accessToken, newRefreshToken);
            return true;
          }
        }
      } on FormatException {
        // Treated as an invalid response below.
      }
      return _expireSession();
    }
    if (status == 400 || status == 401 || status == 403) {
      return _expireSession();
    }
    throw ApiException(
      'The server is unavailable. Try again later.',
      statusCode: status,
    );
  }

  Future<bool> _expireSession() async {
    await _tokens.clear();
    onSessionExpired?.call();
    return false;
  }
}
