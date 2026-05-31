import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/playerui_theme.dart';

enum ProfileTopContext { user, club }

class ProfileTopWidget extends StatelessWidget {
  const ProfileTopWidget({
    super.key,
    this.profilePic,
    this.coverPic,
    this.profileUrl,
    this.coverUrl,
    this.isEdit = false,
    this.onProfilePressed,
    this.onCoverPressed,
    this.pageContext = ProfileTopContext.user,
    this.avatarAlignment = Alignment.bottomCenter,
  });

  final Uint8List? profilePic;
  final Uint8List? coverPic;
  final String? profileUrl;
  final String? coverUrl;
  final bool isEdit;
  final void Function(Uint8List?)? onProfilePressed;
  final void Function(Uint8List?)? onCoverPressed;
  final ProfileTopContext pageContext;
  final Alignment avatarAlignment;

  static const double _coverHeight = 200;
  static const double _avatarRadius = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _coverHeight + _avatarRadius + 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(bottom: _avatarRadius, child: _buildCover()),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: Align(alignment: avatarAlignment, child: _buildAvatar()),
          ),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final content = coverPic != null && coverPic!.isNotEmpty
        ? Image.memory(
            coverPic!,
            width: double.infinity,
            height: _coverHeight,
            fit: BoxFit.cover,
          )
        : (coverUrl != null && coverUrl!.isNotEmpty)
        ? Image.network(
            coverUrl!,
            width: double.infinity,
            height: _coverHeight,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              'assets/images/club_placeholder.png',
              package: 'clubcommon',
              width: double.infinity,
              height: _coverHeight,
              fit: BoxFit.cover,
            ),
          )
        : Image.asset(
            'assets/images/club_placeholder.png',
            package: 'clubcommon',
            width: double.infinity,
            height: _coverHeight,
            fit: BoxFit.cover,
          );

    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          child: content,
        ),
        if (isEdit)
          Positioned(
            right: 8,
            top: 8,
            child: IconButton.filledTonal(
              onPressed: () => onCoverPressed?.call(null),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    Widget avatar;

    if (profilePic != null && profilePic!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: _avatarRadius + 3,
        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
        child: CircleAvatar(
          radius: _avatarRadius,
          backgroundImage: MemoryImage(profilePic!),
        ),
      );
    } else if (profileUrl != null && profileUrl!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: _avatarRadius + 3,
        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
        child: CircleAvatar(
          radius: _avatarRadius,
          backgroundColor: PlayerUiSignalTheme.mobileSearchColor,
          child: ClipOval(
            child: Image.network(
              profileUrl!,
              width: _avatarRadius * 2,
              height: _avatarRadius * 2,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Image.asset(
                _avatarFallbackAsset,
                package: 'clubcommon',
                width: _avatarRadius * 2,
                height: _avatarRadius * 2,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: _avatarRadius + 3,
        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
        child: CircleAvatar(
          radius: _avatarRadius,
          backgroundImage: AssetImage(
            _avatarFallbackAsset,
            package: 'clubcommon',
          ),
        ),
      );
    }

    if (!isEdit) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -4,
          bottom: -4,
          child: IconButton.filled(
            onPressed: () => onProfilePressed?.call(null),
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        ),
      ],
    );
  }

  String get _avatarFallbackAsset => pageContext == ProfileTopContext.club
      ? 'assets/images/club_profile.jpg'
      : 'assets/images/blank_profile_pic.png';
}
