import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

class UserProfileEditScreen extends StatefulWidget {
  const UserProfileEditScreen({super.key, required this.profile});

  final User profile;

  @override
  State<UserProfileEditScreen> createState() => _UserProfileEditScreenState();
}

class _UserProfileEditScreenState extends State<UserProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _dobController;
  late final TextEditingController _genderController;
  late final TextEditingController _bioController;
  // late final TextEditingController _cityController;
  // late final TextEditingController _provinceController;
  // late final TextEditingController _countryController;

  final bool _showName = true;
  final bool _showAge = true;
  final bool _showGender = true;

  // final Map<String, bool> _activities = <String, bool>{
  //   'Pickleball': false,
  //   'Tennis': false,
  //   'Soccer': false,
  //   'Basketball': false,
  //   'Golf': false,
  // };

  Uint8List? _newImageBytes;
  Uint8List? _newCoverImageBytes;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;

    _firstNameController = TextEditingController(text: p.firstName ?? '');
    _lastNameController = TextEditingController(text: p.lastName ?? '');
    _displayNameController = TextEditingController(text: p.displayName);
    _dobController = TextEditingController(text: p.dateOfBirth.toString());
    _genderController = TextEditingController(
      text: p.gender == Gender.male ? "Male" : "Female",
    );

    _bioController = TextEditingController(text: p.bio ?? '');
    //  _cityController = TextEditingController(text: p.city ?? '');
    // _provinceController = TextEditingController(text: p.province ?? '');
    // _countryController = TextEditingController(text: p.country ?? '');

    // for (final item in _activities.keys) {
    //   _activities[item] = p.activities?.contains(item) ?? false;
    // }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _displayNameController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _bioController.dispose();
    // _cityController.dispose();
    // _provinceController.dispose();
    // _countryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isCover}) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              subtitle: const Text('System photo gallery picker'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Files / Google Photos'),
              subtitle: const Text('Open file providers including cloud apps'),
              onTap: () => Navigator.of(context).pop('files'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Google Photos'),
              subtitle: const Text('Open via Android documents provider'),
              onTap: () => Navigator.of(context).pop('google_photos'),
            ),
          ],
        ),
      ),
    );

    if (selection == null) {
      return;
    }

    Uint8List? bytes;
    if (selection == 'gallery') {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        imageQuality: 92,
      );
      if (file == null) {
        return;
      }
      bytes = await file.readAsBytes();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      bytes = result.files.first.bytes;
    }

    if (bytes == null || bytes.isEmpty) {
      return;
    }

    setState(() {
      if (isCover) {
        _newCoverImageBytes = bytes;
      } else {
        _newImageBytes = bytes;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final Set<UserViewPermission> viewPermissions = <UserViewPermission>{};
    if (_showAge) viewPermissions.add(UserViewPermission.age);
    if (_showGender) viewPermissions.add(UserViewPermission.gender);
    if (_showName) viewPermissions.add(UserViewPermission.fullName);

    final profile = User(
      uid: widget.profile.uid,
      email: widget.profile.email,
      gender: widget.profile.gender,
      // change gender
      displayName: _displayNameController.text,
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      coverPicUrl: widget.profile.coverPicUrl,
      profilePic: widget.profile.profilePic,
      bio: _bioController.text,
      activities: widget.profile.activities,
      permissions: viewPermissions,
    );

    // final profile = PlayerUserProfile(
    //   uid: widget.profile.uid,
    //   email: widget.profile.email,
    //   firstName: _firstNameController.text.trim(),
    //   lastName: _lastNameController.text.trim(),
    //   displayName: _displayNameController.text.trim(),
    //   dateOfBirth: _dobController.text.trim().isEmpty
    //       ? null
    //       : _dobController.text.trim(),
    //   gender: _genderController.text.trim().isEmpty
    //       ? null
    //       : _genderController.text.trim(),
    //   bio: _bioController.text.trim().isEmpty
    //       ? null
    //       : _bioController.text.trim(),
    //   city: _cityController.text.trim().isEmpty
    //       ? null
    //       : _cityController.text.trim(),
    //   province: _provinceController.text.trim().isEmpty
    //       ? null
    //       : _provinceController.text.trim(),
    //   country: _countryController.text.trim().isEmpty
    //       ? null
    //       : _countryController.text.trim(),
    //   photoUrl: widget.profile.photoUrl,
    //   coverUrl: widget.profile.coverUrl,
    //   phoneNumber: widget.profile.phoneNumber,
    //   accountType: widget.profile.accountType ?? 'user',
    //   userRole: widget.profile.userRole ?? 'member',
    //   activities: _activities.entries
    //       .where((entry) => entry.value)
    //       .map((entry) => entry.key)
    //       .toList(growable: false),
    //   active: widget.profile.active,
    //   createdAt: widget.profile.createdAt,
    //   updatedAt: DateTime.now(),
    // );

    await context.read<ChatController>().updateCurrentUserProfile(
      profile: profile,
      imageBytes: _newImageBytes,
      coverImageBytes: _newCoverImageBytes,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<ChatController>().loading;

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
          'Edit Profile',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: loading ? null : _save,
            child: Text(
              loading ? 'Saving...' : 'Save',
              style: const TextStyle(
                color: PlayerUiSignalTheme.primaryDarkColor,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ProfileTopWidget(
                profilePic: _newImageBytes,
                coverPic: _newCoverImageBytes,
                profileUrl: widget.profile.profilePic?.thumbnailURL,
                coverUrl: widget.profile.coverPicUrl,
                pageContext: ProfileTopContext.user,
                isEdit: true,
                avatarAlignment: Alignment.bottomLeft,
                onProfilePressed: (_) => _pickImage(isCover: false),
                onCoverPressed: (_) => _pickImage(isCover: true),
              ),
              const SizedBox(height: 16),
              _readOnlyTile(
                leadingAsset: 'assets/icon/ic_email.svg',
                label: 'Email',
                value: widget.profile.email,
              ),
              _formTile(
                leadingAsset: 'assets/icon/ic_fullname.svg',
                child: CommonWidgets.commonTextFieldForLoginSignUP(
                  context: context,
                  controller: _displayNameController,
                  hintText: 'Enter Display Name',
                  labelText: 'Display Name',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Display Name cannot be empty'
                      : null,
                ),
              ),
              _formTile(
                leadingAsset: 'assets/icon/ic_fullname.svg',
                child: Column(
                  children: [
                    CommonWidgets.commonTextFieldForLoginSignUP(
                      context: context,
                      controller: _firstNameController,
                      hintText: 'Enter First Name',
                      labelText: 'First Name',
                    ),
                    const SizedBox(height: 8),
                    CommonWidgets.commonTextFieldForLoginSignUP(
                      context: context,
                      controller: _lastNameController,
                      hintText: 'Enter Last Name',
                      labelText: 'Last Name',
                    ),
                  ],
                ),
              ),
              _formTile(
                leadingAsset: 'assets/icon/ic_gender.svg',
                child: CommonWidgets.commonTextFieldForLoginSignUP(
                  context: context,
                  controller: _genderController,
                  hintText: 'Select Gender',
                  labelText: 'Gender',
                ),
              ),
              // _formTile(
              //   leadingAsset: 'assets/icon/ic_dob.svg',
              //   child: CommonWidgets.commonTextFieldForLoginSignUP(
              //     context: context,
              //     controller: _dobController,
              //     hintText: 'Enter Date of Birth',
              //     labelText: 'Date of Birth',
              //   ),
              // ),
              _formTile(
                leadingAsset: 'assets/icon/ic_bio.svg',
                child: CommonWidgets.commonTextFieldForLoginSignUP(
                  context: context,
                  controller: _bioController,
                  hintText: 'Enter Bio',
                  labelText: 'Enter Bio',
                  maxLines: 5,
                  minLines: 2,
                  maxHeight: 150,
                ),
              ),
              //_activitiesTile(),
              // _formTile(
              // //   leadingAsset: 'assets/icon/ic_bio.svg',
              // //   child: CommonWidgets.commonTextFieldForLoginSignUP(
              // //     context: context,
              // //     controller: _cityController,
              // //     hintText: 'Enter City',
              // //     labelText: 'City',
              //   ),
              // ),
              // _formTile(
              //   leadingAsset: 'assets/icon/ic_bio.svg',
              //   child: CommonWidgets.commonTextFieldForLoginSignUP(
              //     context: context,
              //     controller: _provinceController,
              //     hintText: 'Enter Province',
              //     labelText: 'Province',
              //   ),
              // ),
              // _formTile(
              //   leadingAsset: 'assets/icon/ic_bio.svg',
              //   child: CommonWidgets.commonTextFieldForLoginSignUP(
              //     context: context,
              //     controller: _countryController,
              //     hintText: 'Enter Country',
              //     labelText: 'Country',
              //   ),
              // ),
              // const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readOnlyTile({
    required String leadingAsset,
    required String label,
    required String value,
  }) {
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
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }

  Widget _formTile({required String leadingAsset, required Widget child}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SvgPicture.asset(
        leadingAsset,
        package: 'clubcommon',
        width: 32,
        height: 32,
      ),
      title: child,
    );
  }

  // Widget _activitiesTile() {
  //   return ListTile(
  //     contentPadding: const EdgeInsets.symmetric(horizontal: 16),
  //     leading: Padding(
  //       padding: const EdgeInsets.only(left: 8),
  //       child: SvgPicture.asset(
  //         'assets/icon/ic_bio.svg',
  //         package: 'clubcommon',
  //         width: 28,
  //         height: 28,
  //       ),
  //     ),
  //     title: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         _activities.values.any((selected) => selected)
  //             ? Wrap(
  //                 spacing: 8,
  //                 runSpacing: 8,
  //                 children: _activities.entries
  //                     .where((entry) => entry.value)
  //                     .map(
  //                       (entry) => InputChip(
  //                         label: Text(entry.key),
  //                         onDeleted: () {
  //                           setState(() {
  //                             _activities[entry.key] = false;
  //                           });
  //                         },
  //                       ),
  //                     )
  //                     .toList(growable: false),
  //               )
  //             : const Text(
  //                 'Select activities',
  //                 style: TextStyle(color: PlayerUiSignalTheme.primaryDarkColor),
  //               ),
  //         const SizedBox(height: 8),
  //         // Wrap(
  //         //   spacing: 8,
  //         //   runSpacing: 8,
  //         //   children: _activities.entries
  //         //       .map(
  //         //         (entry) => FilterChip(
  //         //           selected: entry.value,
  //         //           label: Text(entry.key),
  //         //           onSelected: (selected) {
  //         //             setState(() {
  //         //               _activities[entry.key] = selected;
  //         //             });
  //         //           },
  //         //         ),
  //         //       )
  //         //       .toList(growable: false),
  //         // ),
  //       ],
  //     ),
  //   );
  // }
}
