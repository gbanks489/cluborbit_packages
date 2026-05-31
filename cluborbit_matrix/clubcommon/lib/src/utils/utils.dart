import 'dart:io';
import 'dart:convert' as convert;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:logger/logger.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'auth_state_cache.dart';
import 'error_notifier.dart';

Logger logger = Logger(printer: PrettyPrinter(), output: ConsoleOutput());

// class FileLogOutput extends LogOutput {
//   late final File _file;
//   bool _initialized = false;

//   FileLogOutput(String filename) {
//     _init(filename);
//   }

//   Future<void> _init(String filename) async {
//     try {
//       final dir = await getApplicationDocumentsDirectory();
//       _file = File('${dir.path}/$filename');
//       _initialized = true;
//     } catch (e, s) {
//       debugPrint("FileLogOutput init failed: $e\n$s");
//       _initialized = false;
//     }
//   }

//   @override
//   void output(OutputEvent event) {
//     if (!_initialized) {
//       debugPrint("FileLogOutput not ready, skipping log");
//       return;
//     }

//     try {
//       for (var line in event.lines) {
//         _file.writeAsStringSync('$line\n', mode: FileMode.append);
//       }
//     } catch (e, s) {
//       debugPrint("FileLogOutput write failed: $e\n$s");
//     }
//   }
// }

class FileLogOutput extends LogOutput {
  late final File _file;
  bool _initialized = false;

  FileLogOutput(String filename) {
    _init(filename);
  }

  Future<void> _init(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/$filename');
      _initialized = true;
    } catch (e, s) {
      debugPrint('FileLogOutput init failed: $e\n$s');
      _initialized = false;
    }
  }

  @override
  void output(OutputEvent event) {
    if (!_initialized) return;
    try {
      for (var line in event.lines) {
        _file.writeAsStringSync('$line\n', mode: FileMode.append);
      }
    } catch (e, s) {
      debugPrint('FileLogOutput write failed: $e\n$s');
    }
  }
}

Future<void> initLogger() async {
  try {
    logger = Logger(
      printer: PrettyPrinter(),
      output: MultiOutput([
        ConsoleOutput(),
        FileLogOutput("app.log"), // 👈 your class takes a filename string
      ]),
    );
  } catch (e, s) {
    debugPrint("Logger init failed: $e\n$s");
    logger = Logger(printer: PrettyPrinter(), output: ConsoleOutput());
  }
}

class ImageUploadObj {
  final String fieldName;
  final XFile? file;
  final Uint8List? img;

  ImageUploadObj({required this.fieldName, this.file, this.img});
}

final int httpTimeout = 60;

class Utils {
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
        // Try the next candidate path.
      }
    }

    return null;
  }

  static Future<void> _handleUnauthorized(dynamic trace) async {
    final message = trace?.toString().trim();
    AuthStateCache.instance.clear();
    if (message != null && message.isNotEmpty) {
      ErrorNotifier().setError(message);
    }
  }

  static Future<Map<String, String>> getRequestHeader() async {
    final token = AuthStateCache.instance.token ?? '';

    return {
      'Authorization': 'Bearer $token', // Add the token to the headers
      'Content-Type': 'application/json; charset=UTF-8',
    };
  }

  static void logFull(String text) {
    // const int chunkSize = 800;
    // for (var i = 0; i < text.length; i += chunkSize) {
    //   print(
    //     text.substring(
    //       i,
    //       i + chunkSize > text.length ? text.length : i + chunkSize,
    //     ),
    //   );
    // }

    if (kDebugMode) {
      logger.d(text);
    }
    //debugPrint(text, wrapWidth: null);
  }

  static void setAppVersion(dynamic headers) {
    // 1. Extract version headers
    final minAppVersion = Platform.isAndroid
        ? headers['x-min-app-version-android']
        : headers['x-min-app-version-ios'];
    final latestAppVersion = Platform.isAndroid
        ? headers['x-latest-app-version-android']
        : headers['x-latest-app-version-ios'];

    if (minAppVersion != null && latestAppVersion != null) {
      AuthStateCache.instance.setVersions(
        minVersion: minAppVersion.toString(),
        maxVersion: latestAppVersion.toString(),
      );
    }
  }

  // ignore: strict_top_level_inference
  static Future<T?> processNullableResults<T>(responseString, fromJson) async {
    if (kDebugMode) {
      // ignore: prefer_interpolation_to_compose_strings
      Utils.logFull("Response: " + responseString.body);
    }

    setAppVersion(responseString.headers);

    var json = convert.jsonDecode(responseString.body);
    var jsonResult = json['body'] as Map<String, dynamic>;

    if (json["statusCodeValue"] == HttpStatus.ok ||
        json["statusCode"] == HttpStatus.ok) {
      var result = jsonResult['result'] as List<dynamic>?;
      if (result != null) {
        return fromJson(result);
      } else {
        return null;
      }
    } else if (json["statusCodeValue"] == HttpStatus.unauthorized ||
        json["statusCode"] == HttpStatus.unauthorized) {
      await _handleUnauthorized(jsonResult["trace"]);
      return Future.error(HttpException(jsonResult["trace"].toString()));
    } else {
      // Handle error
      throw HttpException(jsonResult["trace"]);
    }
  }

  static Future<T> fetchHttpDataAsMap<T>({
    required String hostname,
    required bool https,
    required String unencodedPath,
    int? timeout,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      var url = https == true
          ? Uri.https(hostname, unencodedPath, queryParameters)
          : Uri.http(hostname, unencodedPath, queryParameters);

      Map<String, String> headers = await getRequestHeader();

      if (kDebugMode) {
        Utils.logFull("Request: $headers");
        Utils.logFull("URL: $url");
      }

      var response = await http
          .get(url, headers: headers)
          .timeout(
            Duration(seconds: timeout ?? httpTimeout),
            onTimeout: () {
              // Handle timeout
              return Future.error(
                'Timeout exceeded of $httpTimeout seconds connecting to $url',
              );
            },
          );

      if (kDebugMode) {
        Utils.logFull("Response: ${response.body}");
      }

      setAppVersion(response.headers);

      var json = convert.jsonDecode(response.body);
      var jsonResult = json['body'] as Map<String, dynamic>;

      if (json["statusCodeValue"] == HttpStatus.ok) {
        var result = jsonResult['result'] as Map<String, dynamic>;
        T obj = fromJson(result);
        return obj;
      } else if (json["statusCodeValue"] == HttpStatus.unauthorized ||
          json["statusCode"] == HttpStatus.unauthorized) {
        await _handleUnauthorized(jsonResult["trace"]);
        return Future.error(HttpException(jsonResult["trace"].toString()));
      } else {
        return Future.error(
          "${T.toString()} Error occurred sending data.\n${HttpException(jsonResult.toString())}\n",
        );
      }
    } on Exception catch (e) {
      return Future.error("${T.toString()} not able to be serialized\n$e\n");
      //throw HttpException("${T.toString()} not able to be serialized\n$e");
    }
  }

  static Future<T?> fetchHttpDataAsList<T>({
    required String hostname,
    required bool https,
    required String unencodedPath,
    Map<String, dynamic>? queryParameters,
    int? timeout,
    required T Function(List<dynamic>) fromJson,
  }) async {
    try {
      Map<String, String> headers = await getRequestHeader();
      var url = https == true
          ? Uri.https(hostname, unencodedPath, queryParameters)
          : Uri.http(hostname, unencodedPath, queryParameters);

      if (kDebugMode) {
        Utils.logFull("Request: $headers");
        Utils.logFull("URL: $url");
      }

      var response = await http
          .get(url, headers: headers)
          .timeout(
            Duration(seconds: timeout ?? httpTimeout),
            onTimeout: () {
              // Handle timeout
              return Future.error(
                'Timeout exceeded of $httpTimeout seconds connecting to $url',
              );
            },
          );

      ErrorNotifier().clearError();

      return processNullableResults(response, fromJson);
    } catch (e) {
      return Future.error(
        "${T.toString()} Data not able to be retrieved\n$e\n",
      );
    }
  }

  static Future<T?> postHttpData<T>({
    required String hostname,
    required bool https,
    required String unencodedPath,
    int? timeout,
    Object? body,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      var url = https == true
          ? Uri.https(hostname, unencodedPath)
          : Uri.http(hostname, unencodedPath);
      Map<String, String> headers = await getRequestHeader();

      if (kDebugMode) {
        Utils.logFull("Request: $headers");
        Utils.logFull("URL: $url");
        print("Body: $body");
      }

      var response = await http.post(url, headers: headers, body: body);

      if (kDebugMode) {
        Utils.logFull("Response: ${response.body}");
      }

      final dynamic json = convert.jsonDecode(response.body);
      final int statusCodeValue =
          (json is Map<String, dynamic> && json['statusCodeValue'] is int)
          ? json['statusCodeValue'] as int
          : response.statusCode;
      final dynamic jsonBody = (json is Map<String, dynamic>)
          ? json['body']
          : null;

      if (statusCodeValue == HttpStatus.ok) {
        ErrorNotifier().clearError();

        if (fromJson == null) {
          return null;
        }

        final dynamic result = (jsonBody is Map<String, dynamic>)
            ? jsonBody['result']
            : null;
        if (result is Map<String, dynamic>) {
          return fromJson(result);
        }

        return Future.error(
          "${T.toString()} Error occurred sending data.\nUnexpected response body format.\n",
        );
      } else {
        return Future.error(
          "${T.toString()} Error occurred sending data.\n${HttpException((jsonBody ?? json).toString())}\n",
        );
      }
    } catch (e) {
      return Future.error("${T.toString()} Error occurred sending data.\n$e\n");
    }
  }

  static Future<T?> postHttpDataGetList<T>({
    required String hostname,
    required bool https,
    required String unencodedPath,
    int? timeout,
    Object? body,
    required T Function(List<dynamic>) fromJson,
  }) async {
    try {
      Map<String, String> headers = await getRequestHeader();
      var url = https == true
          ? Uri.https(hostname, unencodedPath)
          : Uri.http(hostname, unencodedPath);

      if (kDebugMode) {
        Utils.logFull("Request: $headers");
        Utils.logFull("URL: $url");
        print("Body: $body");
      }

      var response = await http.post(url, headers: headers, body: body);

      if (kDebugMode) {
        Utils.logFull("Response: ${response.body}");
      }

      var json = convert.jsonDecode(response.body);
      var jsonResult = json['body'] as Map<String, dynamic>;

      if (json["statusCodeValue"] == HttpStatus.ok) {
        ErrorNotifier().clearError();
        var result = jsonResult['result'] as List<dynamic>?;
        if (result != null) {
          return fromJson(result);
        } else {
          return null;
        }
      } else {
        throw HttpException(jsonResult["trace"]);
      }
    } catch (e) {
      return Future.error("${T.toString()} Error occurred sending data.\n$e\n");
    }
  }

  static Future<T?> postHttpXFilesAndBody<T>({
    required String hostname,
    required bool https,
    required String unencodedPath,
    required List<ImageUploadObj> imgs,
    int? timeout,
    Object? body,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    const Uuid uuid = Uuid();

    try {
      //Map<String, String> headers = getRequestHeader();
      var url = https == true
          ? Uri.https(hostname, unencodedPath)
          : Uri.http(hostname, unencodedPath);

      final token = AuthStateCache.instance.token ?? '';

      var request = http.MultipartRequest('POST', url);

      // Add the authentication token to headers
      request.headers['Authorization'] = 'Bearer $token';
      //   request.headers['Content-Type'] = 'multipart/form-data';
      request.headers['Accept'] = 'application/json';

      if (kDebugMode) {
        Utils.logFull("URL: $url");
        Utils.logFull("Request: ${request.headers}");
        // print("Body: " + body.toString());
      }

      for (var img in imgs) {
        // Generate a random UUID for each image file name
        String uniqueId = uuid.v4();
        String fileName = '$uniqueId.jpg';

        if (img.file != null) {
          // Add each image file to the request
          //   MultipartFile mpFile =
          request.files.add(
            await http.MultipartFile.fromPath(
              img.fieldName,
              img.file!.path,
              filename: fileName,
              contentType: MediaType(
                'image',
                'jpeg',
              ), //MediaType('image', 'jpeg'), //()  http.Headers({'Content-Type': 'image/jpeg'}) //http.ContentType('image', 'jpeg'),
            ),
          );
        } else if (img.img != null) {
          Uuid uuid = Uuid();
          String fileName = "${uuid.v4()}.jpg";

          request.files.add(
            http.MultipartFile.fromBytes(
              img.fieldName,
              img.img!,
              filename: fileName,
              contentType: MediaType(
                'image',
                'jpeg',
              ), //MediaType('image', 'jpeg'), //()  http.Headers({'Content-Type': 'image/jpeg'}) //http.ContentType('image', 'jpeg'),
            ),
          );
        }
      }

      // String formattedJson = convert
      //     .jsonEncode(body)
      //     .replaceAll(r'\"', '"') // ✅ Removes escaped quotes
      //     .replaceAll(r"\n", "") // ✅ Removes escaped newlines
      //     .replaceAll(RegExp(r'^"|"$'), "");

      // request.files.add(
      //   http.MultipartFile.fromString(
      //     'body',
      //     //convert.jsonEncode(body), // Convert object to JSON string
      //     formattedJson,
      //     filename: 'body.json',
      //     contentType: MediaType('application', 'json'), // ✅ Force JSON type
      //   ),
      // );

      // String inputjson = convert.jsonEncode(body);
      String inputjson = body is String ? body : convert.jsonEncode(body);

      if (kDebugMode) {
        Utils.logFull("Body: $inputjson");
      }

      request.files.add(
        http.MultipartFile.fromString(
          'body',
          inputjson,
          //   filename: 'body.json',
          contentType: MediaType('application', 'json'),
        ),
      );

      // Attach JSON body as a field
      //    request.fields['body'] = convert.jsonEncode(body);

      // final streamedResponse = await request.send();
      // final http.Response response = await http.Response.fromStream(streamedResponse);

      // return processNullableResults(response, fromJson);

      // Send the request
      var streamedResponse = await request.send();
      var responseString = await streamedResponse.stream.bytesToString();
      // return processNullableResults(responseString, fromJson);

      if (kDebugMode) {
        Utils.logFull("Response: $responseString");
      }

      var json = convert.jsonDecode(responseString);
      var jsonResult = json['body'] as Map<String, dynamic>;

      if (json["statusCodeValue"] == HttpStatus.ok) {
        ErrorNotifier().clearError();
        var result = jsonResult['result'] as Map<String, dynamic>;

        if (fromJson != null) {
          return fromJson(result);
        } else {
          return null;
        }
      } else if (json["statusCodeValue"] == HttpStatus.unauthorized ||
          json["statusCode"] == HttpStatus.unauthorized) {
        await _handleUnauthorized(jsonResult["trace"]);
        return Future.error(HttpException(jsonResult["trace"].toString()));
      } else {
        return Future.error(
          "${T.toString()} Error occurred sending data.\n${HttpException(jsonResult.toString())}\n",
        );
      }
    } catch (e) {
      return Future.error("${T.toString()} Error occurred sending data.\n$e\n");
    }
  }

  static Future<T?> postHttpXFilesGetList<T>({
    required String hostname,
    required bool https,
    required String unencodedPath,
    required List<XFile> xfiles,
    int? timeout,
    required T Function(List<dynamic>) fromJson,
  }) async {
    const Uuid uuid = Uuid();

    try {
      //Map<String, String> headers = getRequestHeader();
      var url = https == true
          ? Uri.https(hostname, unencodedPath)
          : Uri.http(hostname, unencodedPath);

      final token = AuthStateCache.instance.token ?? '';

      var request = http.MultipartRequest('POST', url);

      // Add the authentication token to headers
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'multipart/form-data';

      if (kDebugMode) {
        Utils.logFull(url.toString());
        Utils.logFull(request.headers.toString());
      }

      for (var xfile in xfiles) {
        // Generate a random UUID for each image file name
        String uniqueId = uuid.v4();
        String fileName = '$uniqueId.jpg';

        // Add each image file to the request
        //   MultipartFile mpFile =
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            xfile.path,
            filename: fileName,
            contentType: MediaType(
              'image',
              'jpeg',
            ), //MediaType('image', 'jpeg'), //()  http.Headers({'Content-Type': 'image/jpeg'}) //http.ContentType('image', 'jpeg'),
          ),
        );
      }

      // Send the request
      var streamedResponse = await request.send();
      var responseString = await streamedResponse.stream.bytesToString();

      if (kDebugMode) {
        Utils.logFull(responseString);
      }

      var json = convert.jsonDecode(responseString);
      var jsonResult = json['body'] as Map<String, dynamic>;

      if (json["statusCodeValue"] == HttpStatus.ok) {
        ErrorNotifier().clearError();

        var result = jsonResult['result'] as List<dynamic>?;
        if (result != null) {
          return fromJson(result);
        } else {
          return null;
        }
      } else if (json["statusCodeValue"] == HttpStatus.unauthorized ||
          json["statusCode"] == HttpStatus.unauthorized) {
        await _handleUnauthorized(jsonResult["trace"]);
        return Future.error(HttpException(jsonResult["trace"].toString()));
      } else {
        return Future.error(
          "${T.toString()} Error occurred sending data.\n${HttpException(jsonResult.toString())}\n",
        );
      }
    } catch (e) {
      return Future.error("${T.toString()} Error occurred sending data.\n$e\n");
    }
  }

  static Future<bool> httpDelete({
    required String hostname,
    required bool https,
    required String unencodedPath,
    int? timeout,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      Map<String, String> headers = await getRequestHeader();

      var url = https == true
          ? Uri.https(hostname, unencodedPath, queryParameters)
          : Uri.http(hostname, unencodedPath, queryParameters);

      if (kDebugMode) {
        Utils.logFull(url.toString());
      }

      var response = await http.delete(url, headers: headers);
      if (kDebugMode) {
        Utils.logFull(response.body);
      }

      var json = convert.jsonDecode(response.body);

      if (json["statusCodeValue"] == HttpStatus.ok) {
        ErrorNotifier().clearError();
        return true;
      } else {
        return Future.error(
          "Error occurred deleting data.\n${HttpException(response.body)}",
        );
      }
    } on Exception catch (e) {
      return Future.error("Error occurred deleting data\n$e\n");
    }
  }

  // Extracts the inner text from an HTML anchor tag.
  // Example: `<a href="...">罗小凌</a>` → "罗小凌"
  static String extractAnchorText(String htmlAnchor) {
    var unescape = HtmlUnescape();

    final regex = RegExp(r'>(.*?)<\/a>', caseSensitive: false);
    final match = regex.firstMatch(htmlAnchor);
    return unescape.convert(match != null ? match.group(1) ?? '' : '');
  }
}

void showSnackBar(String content, BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(content)));
}

Future<Uint8List> uint8ListFromUrl(String url) async {
  try {
    Uint8List bytes = (await NetworkAssetBundle(
      Uri.parse(url),
    ).load(url)).buffer.asUint8List();

    return bytes;
  } catch (e) {
    rethrow;
  }
}
