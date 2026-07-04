import 'dart:convert';

import 'package:clubcommon/clubcommon.dart';

class ConnectivityService {
  ConnectivityService(this._matrixHomeserver)
    : _http = ClubHttpUtils(retries: 3, timeout: const Duration(seconds: 4));

  final String _matrixHomeserver;
  final ClubHttpUtils _http;

  Future<bool> isMatrixReachable() async {
    final uri = _buildVersionsUri();
    if (uri == null) {
      return false;
    }
    try {
      final response = await _http.get(uri);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Uri? _buildVersionsUri() {
    final raw = _matrixHomeserver.trim();
    if (raw.isEmpty) {
      return null;
    }

    final baseValue = (raw.startsWith('http://') || raw.startsWith('https://'))
        ? raw
        : 'https://$raw';

    final base = Uri.tryParse(baseValue);
    if (base == null || base.host.isEmpty) {
      return null;
    }

    final normalizedBasePath = base.path.replaceAll(RegExp(r'/+$'), '');
    final versionsPath = '$normalizedBasePath/_matrix/client/versions';
    return base.replace(path: versionsPath);
  }

  Future<String?> detectCountryCode() async {
    final endpoints = <Uri>[
      Uri.parse('https://ipwho.is/'),
      Uri.parse('https://ipapi.co/json/'),
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await _http.get(endpoint);
        if (response.statusCode != 200) {
          continue;
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final candidate = (body['country_code'] ?? body['countryCode'])
            ?.toString();
        if (candidate != null && candidate.isNotEmpty) {
          return candidate.toUpperCase();
        }
      } catch (_) {
        // Ignore lookup failure and continue to next endpoint.
      }
    }

    return null;
  }
}
