import 'package:clubcommon/clubcommon.dart';

class UserProvider {
  const UserProvider();

  static const List<List<String>> _dtoPaths = <List<String>>[
    <String>['body', 'result'],
    <String>['body', 'result', 'userDto'],
    <String>[],
    <String>['data'],
    <String>['result'],
    <String>['data', 'result'],
  ];

  static const List<List<String>> _profilePaths = <List<String>>[
    <String>['body', 'result', 'user'],
    <String>['body', 'result'],
    <String>[],
    <String>['user'],
    <String>['data'],
    <String>['data', 'user'],
    <String>['result'],
    <String>['result', 'user'],
  ];

  UserDTO? userDtoFromResponse(dynamic decoded) {
    final resultFirst = Utils.decodeFromResult<UserDTO>(
      decoded,
      UserDTO.fromJson,
    );
    if (resultFirst != null && resultFirst.user.uid.isNotEmpty) {
      return resultFirst;
    }

    final parsed = Utils.decodeAtPaths<UserDTO>(
      decoded,
      _dtoPaths,
      UserDTO.fromJson,
    );
    if (parsed != null && parsed.user.uid.isNotEmpty) {
      return parsed;
    }

    final root = Utils.resultMap(decoded) ?? Utils.asMap(decoded);
    if (root == null) {
      return null;
    }

    final userMap =
        Utils.mapAtPath(root, const <String>['user']) ??
        Utils.mapAtPath(root, const <String>['data', 'user']) ??
        Utils.mapAtPath(root, const <String>['result', 'user']) ??
        Utils.mapAtPath(root, const <String>['body', 'result', 'user']);
    if (userMap == null) {
      return null;
    }

    final dtoMap = <String, dynamic>{
      'user': userMap,
      'userEntity': root['userEntity'] ?? userMap,
      'chatUser': root['chatUser'] ?? root['chatCredentials'],
    };

    try {
      final dto = UserDTO.fromJson(dtoMap);
      if (dto.user.uid.isEmpty) {
        return null;
      }
      return dto;
    } catch (_) {
      return null;
    }
  }

  /*
  // Update Userw
  Future<User?> updateUser(
    User user,
    Uint8List? profileImage,
    Uint8List? coverImage,
  ) async {
    try {
      List<ImageUploadObj> imageUploadObjs = [];

      if (profileImage != null) {
        ImageUploadObj profileImgObj = ImageUploadObj(
          fieldName: "profileImage",
          img: profileImage,
        );

        imageUploadObjs.add(profileImgObj);
      }

      if (coverImage != null) {
        ImageUploadObj coverImgObj = ImageUploadObj(
          fieldName: "coverImage",
          img: coverImage,
        );

        imageUploadObjs.add(coverImgObj);
      }

      _user = await Utils.postHttpXFilesAndBody<User>(
        hostname: hostname,
        https: https,
        unencodedPath: '${Environment.serverContextPath}/user',
        imgs: imageUploadObjs,
        body: jsonEncode(user),
        fromJson: (json) => User.fromJson(json),
      );

      notifyListeners();

      return _user;
    } on Exception catch (e) {
      throw HttpException("User could not be added \n$e");
    }
  }
*/

  User? profileFromResponse(dynamic decoded) {
    final dto = userDtoFromResponse(decoded);
    if (dto != null) {
      return profileFromUserDto(dto);
    }

    final resultFirst = Utils.decodeFromResult<User>(decoded, User.fromJson);
    if (resultFirst != null && resultFirst.uid.isNotEmpty) {
      return resultFirst;
    }

    final profile = Utils.decodeAtPaths<User>(
      decoded,
      _profilePaths,
      User.fromJson,
    );
    if (profile != null && profile.uid.isNotEmpty) {
      return profile;
    }

    return null;
  }

  User profileFromUserDto(UserDTO dto) {
    final user = dto.user;
    if (user.uid.isNotEmpty) {
      return user;
    }

    return User(
      uid: dto.userEntity.uid,
      email: user.email.isNotEmpty ? user.email : dto.userEntity.email,
      displayName: user.displayName.isNotEmpty
          ? user.displayName
          : dto.userEntity.displayName,
      dateOfBirth: user.dateOfBirth,
      gender: user.gender,
      profilePic: user.profilePic,
      coverPicUrl: user.coverPicUrl,
      chatToken: user.chatToken,
      chatUsername: user.chatUsername,
      bio: user.bio,
      firstName: user.firstName,
      lastName: user.lastName,
      activities: user.activities,
      permissions: user.permissions,
    );
  }

  String? matrixPasswordFromUserDto(UserDTO dto) {
    return dto.chatUser?.password.trim();
  }
}
