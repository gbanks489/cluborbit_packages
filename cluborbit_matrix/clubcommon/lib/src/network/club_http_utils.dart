import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

class ClubHttpUtils {
  ClubHttpUtils({
    http.Client? client,
    this.retries = 2,
    this.timeout = const Duration(seconds: 10),
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: retries,
         whenError: _alwaysRetry,
       );

  final int retries;
  final Duration timeout;
  final RetryClient _client;

  static bool _alwaysRetry(Object error, StackTrace stackTrace) => true;

  void _logRequest(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
  }) {
    if (!kDebugMode) {
      return;
    }

    debugPrint('[ClubHttpUtils] $method $uri');
    if (headers != null && headers.isNotEmpty) {
      debugPrint('[ClubHttpUtils] headers: $headers');
    }
    if (body != null) {
      debugPrint('[ClubHttpUtils] body: $body');
    }
    if (fields != null && fields.isNotEmpty) {
      debugPrint('[ClubHttpUtils] fields: $fields');
      final payload = fields['body'];
      if (payload != null && payload.isNotEmpty) {
        debugPrint('[ClubHttpUtils] payload: $payload');
      }
    }
    if (files != null && files.isNotEmpty) {
      final fileNames = files
          .map((file) => file.filename ?? file.field)
          .toList();
      debugPrint('[ClubHttpUtils] files: $fileNames');
    }
  }

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    _logRequest('GET', uri, headers: headers);
    return _client.get(uri, headers: headers).timeout(timeout);
  }

  Future<http.Response> postJson(
    Uri uri, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    final resolvedHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };
    final payload = jsonEncode(body ?? <String, dynamic>{});
    _logRequest('POST', uri, headers: resolvedHeaders, body: payload);
    return _client
        .post(uri, headers: resolvedHeaders, body: payload)
        .timeout(timeout);
  }

  Future<http.Response> postMultipart(
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
  }) async {
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(
      <String, String>{'Accept': 'application/json', ...?headers}
        ..removeWhere((key, _) => key.toLowerCase() == 'content-type'),
    );

    if (fields != null && fields.isNotEmpty) {
      request.fields.addAll(fields);
    }
    if (files != null && files.isNotEmpty) {
      request.files.addAll(files);
    }

    _logRequest(
      'POST',
      uri,
      headers: request.headers,
      fields: fields,
      files: files,
    );

    final response = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(response);
  }

  Future<http.Response> putJson(
    Uri uri, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    final resolvedHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };
    final payload = jsonEncode(body ?? <String, dynamic>{});
    _logRequest('PUT', uri, headers: resolvedHeaders, body: payload);
    return _client
        .put(uri, headers: resolvedHeaders, body: payload)
        .timeout(timeout);
  }

  Future<http.Response> delete(Uri uri, {Map<String, String>? headers}) async {
    _logRequest('DELETE', uri, headers: headers);
    return _client.delete(uri, headers: headers).timeout(timeout);
  }

  static dynamic decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
