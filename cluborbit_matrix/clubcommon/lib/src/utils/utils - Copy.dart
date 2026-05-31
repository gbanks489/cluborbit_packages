class Utils {
  const Utils._();

  // PlayerUI response envelope is typically: { body: { result: ... } }
  static Map<String, dynamic>? resultMap(dynamic decoded) {
    final root = asMap(decoded);
    if (root == null) {
      return null;
    }

    final body = mapAtPath(root, const <String>['body']);
    if (body != null) {
      final result = asMap(body['result']);
      if (result != null) {
        return result;
      }
    }

    final directResult = asMap(root['result']);
    if (directResult != null) {
      return directResult;
    }

    return null;
  }

  static T? decodeFromResult<T>(
    dynamic decoded,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final result = resultMap(decoded);
    if (result == null) {
      return null;
    }
    try {
      return fromJson(result);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static Map<String, dynamic>? mapAtPath(
    Map<String, dynamic> root,
    List<String> path,
  ) {
    dynamic current = root;
    for (final segment in path) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return asMap(current);
  }

  static T? decodeAtPaths<T>(
    dynamic decoded,
    List<List<String>> paths,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final root = asMap(decoded);
    if (root == null) {
      return null;
    }

    for (final path in paths) {
      final candidate = path.isEmpty ? root : mapAtPath(root, path);
      if (candidate == null) {
        continue;
      }
      try {
        return fromJson(candidate);
      } catch (_) {
        // try next candidate path
      }
    }

    return null;
  }
}
