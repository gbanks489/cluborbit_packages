import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

import 'user_profile_edit_screen.dart';

class UserProfileViewScreen extends StatefulWidget {
  const UserProfileViewScreen({super.key});

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<ChatController>();
      if (controller.userProfile == null) {
        try {
          await controller.refreshCurrentUserProfile();
        } catch (_) {
          // ErrorNotifier already handles messaging.
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        final profile = controller.userProfile;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              icon: SvgPicture.asset(
                'assets/icon/ic_back.svg',
                package: 'clubcommon',
                width: 22,
                height: 22,
              ),
            ),
            title: const Text(
              'Profile',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            centerTitle: true,
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
            foregroundColor: PlayerUiSignalTheme.secondaryColor,
            onPressed: profile == null
                ? null
                : () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => UserProfileEditScreen(profile: profile),
                      ),
                    );
                    if (!context.mounted) return;
                    await context
                        .read<ChatController>()
                        .refreshCurrentUserProfile();
                  },
            child: const Icon(Icons.edit),
          ),
          body: profile == null
              ? const Center(child: Text('No profile data available.'))
              : SafeArea(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ProfileTopWidget(
                        profileUrl: profile.profilePic?.thumbnailURL,
                        coverUrl: profile.coverPicUrl,
                        pageContext: ProfileTopContext.user,
                        avatarAlignment: Alignment.bottomLeft,
                        isEdit: false,
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _displayName(profile),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      _detailTile(
                        leadingAsset: 'assets/icon/ic_email.svg',
                        label: 'Email',
                        value: profile.email,
                      ),
                      _detailTile(
                        leadingAsset: 'assets/icon/ic_fullname.svg',
                        label: 'Full Name',
                        value:
                            '${profile.firstName ?? ''} ${profile.lastName ?? ''}'
                                .trim(),
                      ),
                      _detailTile(
                        leadingAsset: 'assets/icon/ic_fullname.svg',
                        label: 'Display Name',
                        value: profile.displayName,
                      ),
                      _detailTile(
                        leadingAsset: 'assets/icon/ic_dob.svg',
                        label: 'Date of Birth',
                        value: _dateOfBirthText(profile),
                      ),
                      _detailTile(
                        leadingAsset: 'assets/icon/ic_gender.svg',
                        label: 'Gender',
                        value: _genderText(profile),
                      ),
                      _detailTile(
                        leadingAsset: 'assets/icon/ic_bio.svg',
                        label: 'Bio',
                        value: profile.bio,
                      ),
                      // _detailTile(
                      //   leadingAsset: 'assets/icon/ic_bio.svg',
                      //   label: 'City',
                      //   value: profile.city,
                      // ),
                      // _detailTile(
                      //   leadingAsset: 'assets/icon/ic_bio.svg',
                      //   label: 'Province',
                      //   value: profile.province,
                      // ),
                      // _detailTile(
                      //   leadingAsset: 'assets/icon/ic_bio.svg',
                      //   label: 'Country',
                      //   value: profile.country,
                      // ),
                      // _activitiesTile(profile.activities),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _detailTile({
    required String leadingAsset,
    required String label,
    required String? value,
  }) {
    final text = (value == null || value.trim().isEmpty) ? 'No data' : value;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SvgPicture.asset(
        leadingAsset,
        package: 'clubcommon',
        width: 32,
        height: 32,
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  String _displayName(User profile) {
    final display = profile.displayName.trim();
    if (display.isNotEmpty) {
      return display;
    }
    final full = '${profile.firstName ?? ''} ${profile.lastName ?? ''}'.trim();
    return full.isEmpty ? 'Profile' : full;
  }

  String? _dateOfBirthText(User profile) {
    final value = profile.dateOfBirth?.toIsoString();
    if (value == null || value.isEmpty) {
      return null;
    }

    final parts = value.split('T');
    return parts.first;
  }

  String? _genderText(User profile) {
    final value = profile.gender?.name;
    if (value == null || value.isEmpty) {
      return null;
    }
    return value[0].toUpperCase() + value.substring(1);
  }
}
