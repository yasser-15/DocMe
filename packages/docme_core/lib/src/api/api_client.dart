import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../failure.dart';

class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
  });

  factory ApiConfig.fromEnvironment() {
    return ApiConfig(
      baseUrl: const String.fromEnvironment(
        'DOCME_API_BASE_URL',
        defaultValue: 'http://10.0.2.2:8000',
      ),
      timeout: const Duration(
        seconds: int.fromEnvironment(
          'DOCME_API_TIMEOUT_SECONDS',
          defaultValue: 30,
        ),
      ),
    );
  }

  final String baseUrl;
  final Duration timeout;
}

class ApiClient {
  ApiClient({
    ApiConfig? config,
    http.Client? client,
  })  : _config = config ?? ApiConfig.fromEnvironment(),
        _client = client ?? http.Client();

  final ApiConfig _config;
  final http.Client _client;

  Future<Map<String, String>> _headers({String? token}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer ';
    }
    return headers;
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final base = _config.baseUrl.endsWith('/')
        ? _config.baseUrl.substring(0, _config.baseUrl.length - 1)
        : _config.baseUrl;
    final uriPath = '';
    final uriPath = '\\';
  }
  Result<T> _handleResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic> data) mapper,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return Ok(mapper(data));
        }
        if (data is List<dynamic>) {
          return Ok(mapper({'results': data}));
        }
        return Ok(mapper(data as Map<String, dynamic>));
      } catch (e) {
        return Err(DocMeFailure(
          kind: DocMeFailureKind.server,
          message: 'Failed to parse response: ',
          cause: e,
        ));
      }
    }

    String message = 'Request failed';
    try {
      final error = jsonDecode(response.body);
      if (error is Map<String, dynamic>) {
        message = error['detail'] ?? error['message'] ?? error['error'] ?? message;
      }
    } catch (_) {}

    final kind = response.statusCode == 401
        ? DocMeFailureKind.unauthorized
        : response.statusCode == 403
            ? DocMeFailureKind.permissionDenied
            : response.statusCode == 404
                ? DocMeFailureKind.notFound
                : response.statusCode == 409
                    ? DocMeFailureKind.conflict
                    : response.statusCode >= 400 && response.statusCode < 500
                        ? DocMeFailureKind.validation
                        : DocMeFailureKind.server;

    return Err(DocMeFailure(
      kind: kind,
      message: message,
      code: response.statusCode.toString(),
    ));
  }

  Future<Result<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParams,
    String? token,
    T Function(Map<String, dynamic>)? mapper,
  }) async {
    try {
      final response = await _client
          .get(_buildUri(path, queryParams), headers: await _headers(token: token))
          .timeout(_config.timeout);
      if (mapper != null) {
        return _handleResponse(response, mapper);
      }
      return Ok(response.body as T);
    } catch (e) {
      return Err(DocMeFailure(
        kind: DocMeFailureKind.server,
        message: e.toString(),
        cause: e,
      ));
    }
  }

  Future<Result<T>> post<T>(
    String path, {
    Map<String, dynamic>? body,
    String? token,
    T Function(Map<String, dynamic>)? mapper,
  }) async {
    try {
      final response = await _client
          .post(
            _buildUri(path),
            headers: await _headers(token: token),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(_config.timeout);
      if (mapper != null) {
        return _handleResponse(response, mapper);
      }
      return Ok(response.body as T);
    } catch (e) {
      return Err(DocMeFailure(
        kind: DocMeFailureKind.server,
        message: e.toString(),
        cause: e,
      ));
    }
  }

  void dispose() {
    _client.close();
  }
}
