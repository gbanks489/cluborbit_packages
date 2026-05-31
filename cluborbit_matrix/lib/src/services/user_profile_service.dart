import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clubcommon/clubcommon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/playerchat_config.dart';
import 'auth_service.dart';

class MatrixProfileCredentials {
  const MatrixProfileCredentials({
    required this.matrixUserId,
    required this.matrixPassword,
    required this.profile,
  });

  final String matrixUserId;
  final String matrixPassword;
  final User profile;
}

class UserProfileService {
  UserProfileService({
    required PlayerChatConfig config,
    required AuthService authService,
    ClubHttpUtils? http,
    UserProvider? userProvider,
  }) : _config = config,
       _authService = authService,
       _http = http ?? ClubHttpUtils(),
       _userProvider = userProvider ?? const UserProvider();

  final PlayerChatConfig _config;
  final AuthService _authService;
  final ClubHttpUtils _http;
  final UserProvider _userProvider;

  static File? _logFile;

  Future<User?> fetchCurrentUserProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      return null;
    }

    final decoded = await _fetchProfileResponseBody(uid: user.uid);
    if (decoded == null) {
      return null;
    }
    final profile = _userProvider.profileFromResponse(decoded);
    if (profile == null) {
      return null;
    }
    return _normalizedProfile(profile);
  }

  Future<MatrixProfileCredentials> fetchMatrixCredentialsFromProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('Firebase user is not logged in.');
    }

    final decoded = await _fetchProfileResponseBody(uid: user.uid);
    if (decoded == null) {
      throw Exception('User profile not found on server.');
    }

    final dto = _userProvider.userDtoFromResponse(decoded);
    final profile = _userProvider.profileFromResponse(decoded);
    if (profile == null || profile.uid.trim().isEmpty) {
      throw Exception('User profile payload is missing uid at expected path.');
    }

    final password = dto == null
        ? null
        : _userProvider.matrixPasswordFromUserDto(dto);
    if (password == null || password.trim().isEmpty) {
      throw Exception(
        'Chat password was not found in userDto.chatUser from SERVER_HOST.',
      );
    }

    final userId = profile.uid.trim();
    if (userId.isEmpty) {
      throw Exception(
        'Profile uid is empty and cannot be used for Matrix login.',
      );
    }

    return MatrixProfileCredentials(
      matrixUserId: userId,
      matrixPassword: password.trim(),
      profile: _normalizedProfile(profile),
    );
  }

  Future<User> saveCurrentUserProfile({
    required User profile,
    Uint8List? imageBytes,
    Uint8List? coverImageBytes,
  }) async {
    final files = <http.MultipartFile>[];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      files.add(
        http.MultipartFile.fromBytes(
          'profileImage',
          imageBytes,
          filename: 'profile.jpg',
        ),
      );
    }
    if (coverImageBytes != null && coverImageBytes.isNotEmpty) {
      files.add(
        http.MultipartFile.fromBytes(
          'coverImage',
          coverImageBytes,
          filename: 'cover.jpg',
        ),
      );
    }

    final uri = _buildUri('/user');
    final response = await _http.postMultipart(
      uri,
      headers: await _headers(),
      fields: _multipartFields(profile),
      files: files.isEmpty ? null : files,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to save user profile (${response.statusCode}): ${response.body}',
      );
    }

    if (response.body.trim().isEmpty) {
      return profile;
    }

    final dynamic decoded = ClubHttpUtils.decodeBody(response);
    final savedProfile = _userProvider.profileFromResponse(decoded);
    if (savedProfile == null) {
      return profile;
    }
    return _normalizedProfile(savedProfile);
  }

  User _normalizedProfile(User profile) {
    final photoUrl = _normalizedPhotoUrl(profile.profilePic?.thumbnailURL);
    final coverUrl = _normalizedPhotoUrl(profile.coverPicUrl);
    if (photoUrl == profile.profilePic?.thumbnailURL &&
        coverUrl == profile.coverPicUrl) {
      return profile;
    }

    return User(
      uid: profile.uid,
      email: profile.email,
      firstName: profile.firstName,
      lastName: profile.lastName,
      displayName: profile.displayName,
      dateOfBirth: profile.dateOfBirth,
      gender: profile.gender,
      bio: profile.bio,
      coverPicUrl: profile.coverPicUrl,
      profilePic: profile.profilePic,
    );
  }

  String? _normalizedPhotoUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      return value;
    }

    final host = ClubEnvironment.serverHost(
      read: dotenv.maybeGet,
      fallback: _config.serverHost,
    );
    if (host.isEmpty) {
      return value;
    }

    final isHttps = ClubEnvironment.serverHttps(
      read: dotenv.maybeGet,
      fallback: _config.useHttps,
    );
    final path = value.startsWith('/') ? value : '/$value';
    return Uri(
      scheme: isHttps ? 'https' : 'http',
      host: host,
      path: path,
    ).toString();
  }

  Future<UserDTO> getUserDTO(String userUid) {
    try {
      Map<String, dynamic> queryParameters = <String, dynamic>{};

      queryParameters.addAll({'uid': userUid});

      final host = ClubEnvironment.serverHost(
        read: dotenv.maybeGet,
        fallback: _config.serverHost,
      );
      if (host.isEmpty) {
        throw Exception(
          'SERVER_HOST is not configured. Set it in ENV_FILE or PlayerChatConfig.',
        );
      }

      final isHttps = ClubEnvironment.serverHttps(
        read: dotenv.maybeGet,
        fallback: _config.useHttps,
      );

      final contextPath = ClubEnvironment.serverContextPath(
        read: dotenv.maybeGet,
      );

      return Utils.fetchHttpDataAsMap<UserDTO>(
        hostname: host,
        https: isHttps ? true : false,
        unencodedPath: '$contextPath/user',
        queryParameters: queryParameters,
        fromJson: (json) => UserDTO.fromJson(json),
      );
    } on Exception catch (e) {
      throw HttpException("User was not able to be retrieved \n$e");
    }
  }

  Uri _buildUri(String path, {Map<String, String>? query}) {
    final host = ClubEnvironment.serverHost(
      read: dotenv.maybeGet,
      fallback: _config.serverHost,
    );
    if (host.isEmpty) {
      throw Exception(
        'SERVER_HOST is not configured. Set it in ENV_FILE or PlayerChatConfig.',
      );
    }

    final isHttps = ClubEnvironment.serverHttps(
      read: dotenv.maybeGet,
      fallback: _config.useHttps,
    );
    final contextPath = ClubEnvironment.serverContextPath(
      read: dotenv.maybeGet,
    );
    final normalizedPath =
        '${contextPath.endsWith('/') ? contextPath.substring(0, contextPath.length - 1) : contextPath}${path.startsWith('/') ? path : '/$path'}';

    return Uri(
      scheme: isHttps ? 'https' : 'http',
      host: host,
      path: normalizedPath,
      queryParameters: query,
    );
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Accept': 'application/json'};

    final token = await _authService.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, String> _multipartFields(User profile) {
    final source = _playerUiUserFromProfile(profile).toJson()
      ..removeWhere((_, value) {
        if (value == null) {
          return true;
        }
        if (value is String) {
          return value.trim().isEmpty;
        }
        if (value is List || value is Set || value is Map) {
          return value.isEmpty;
        }
        return false;
      });

    return <String, String>{'body': jsonEncode(source)};
  }

  User _playerUiUserFromProfile(User profile) {
    final authEmail = _authService.currentUser?.email;

    return User(
      email: (profile.email.isNotEmpty ? profile.email : (authEmail ?? ''))
          .trim(),
      uid: profile.uid,
      displayName: profile.displayName.trim(),
      gender: _playerUiGender(profile.gender),
      dateOfBirth: profile.dateOfBirth,
      coverPicUrl: _trimOrNull(profile.coverPicUrl),
      bio: _trimOrNull(profile.bio),
      firstName: _trimOrNull(profile.firstName),
      lastName: _trimOrNull(profile.lastName),
      profilePic: profile.profilePic,
      activities: profile.activities,
      permissions: profile.permissions,
    );
  }

  Gender? _playerUiGender(Gender? raw) {
    return raw;
  }

  String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<dynamic> _fetchProfileResponseBody({required String uid}) async {
    final uri = _buildUri('/user', query: <String, String>{'uid': uid});
    final headers = await _headers();
    await _appendAppLog(
      'REQUEST ${uri.toString()}\nheaders: ${jsonEncode(headers)}',
    );

    http.Response response;
    try {
      response = await _http.get(uri, headers: headers);
    } catch (error, stackTrace) {
      await _appendAppLog(
        'REQUEST ERROR ${uri.toString()}\nerror: $error\nstackTrace: $stackTrace',
      );
      rethrow;
    }

    await _appendAppLog(
      'RESPONSE ${uri.toString()}\nstatus: ${response.statusCode}\nheaders: ${jsonEncode(response.headers)}\nbody: ${response.body}',
    );

    if (response.statusCode == 404 || response.body.trim().isEmpty) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to fetch user profile (${response.statusCode}): ${response.body}',
      );
    }

    return ClubHttpUtils.decodeBody(response);
  }

  Future<void> _appendAppLog(String message) async {
    try {
      final file = await _resolveLogFile();
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Keep network flow intact if file logging is unavailable.
    }
  }

  Future<File> _resolveLogFile() async {
    final existing = _logFile;
    if (existing != null) {
      return existing;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final file = File(p.join(supportDirectory.path, 'app.log'));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    debugPrint('UserProfileService app.log path: ${file.path}');
    _logFile = file;
    return file;
  }
}
