import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

class OnboardingAdditionalInfoScreen extends StatefulWidget {
  const OnboardingAdditionalInfoScreen({super.key, this.imageBytes});

  final Uint8List? imageBytes;

  @override
  State<OnboardingAdditionalInfoScreen> createState() =>
      _OnboardingAdditionalInfoScreenState();
}

class _OnboardingAdditionalInfoScreenState
    extends State<OnboardingAdditionalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  // final _cityController = TextEditingController();
  // final _provinceController = TextEditingController();
  // final _countryController = TextEditingController(text: 'Canada');

  String? _gender;
  final Map<String, bool> _activities = <String, bool>{
    'Pickleball': false,
    'Tennis': false,
    'Soccer': false,
    'Basketball': false,
    'Golf': false,
  };

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    // _cityController.dispose();
    // _provinceController.dispose();
    // _countryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final controller = context.read<ChatController>();
    final selectedActivities = _activities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);

    await controller.saveOnboardingProfile(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      gender: _gender,
      // bio: _bioController.text.trim().isEmpty
      //     ? null
      //     : _bioController.text.trim(),
      // city: _cityController.text.trim().isEmpty
      //     ? null
      //     : _cityController.text.trim(),
      // province: _provinceController.text.trim().isEmpty
      //     ? null
      //     : _provinceController.text.trim(),
      // country: _countryController.text.trim().isEmpty
      //     ? null
      //     : _countryController.text.trim(),
      activities: selectedActivities,
      imageBytes: widget.imageBytes,
    );

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<ChatController>().loading;
    final error = context.watch<ErrorNotifier>().errorMessage;

    return Scaffold(
      appBar: AppBar(title: const Text('Tell us about you')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Complete your profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your profile is saved to the same PlayerUI user schema and used by ClubOrbit Chat.',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              const SizedBox(height: 20),
              _requiredField(
                _firstNameController,
                'First name',
                prefix: const Icon(
                  Icons.person_outline,
                  color: PlayerUiSignalTheme.primaryDarkColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              _requiredField(
                _lastNameController,
                'Last name',
                prefix: const Icon(
                  Icons.person_outline,
                  color: PlayerUiSignalTheme.primaryDarkColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              _requiredField(
                _displayNameController,
                'Display name',
                prefix: const Icon(
                  Icons.person_outline,
                  color: PlayerUiSignalTheme.primaryDarkColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              PlayerUiSelectorField(
                label: 'Gender',
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_gender.svg',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _gender,
                    isExpanded: true,
                    dropdownColor: PlayerUiSignalTheme.secondaryColor,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(fontFamily: 'Poppins'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                      DropdownMenuItem(
                        value: 'prefer_not_to_say',
                        child: Text('Prefer not to say'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _gender = value),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              CommonWidgets.commonTextFieldForLoginSignUP(
                context: context,
                controller: _bioController,
                minLines: 2,
                maxLines: 4,
                labelText: 'Bio (optional)',
                hintText: 'Tell people about yourself',
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_bio.svg',
                ),
              ),
              // const SizedBox(height: 10),
              // CommonWidgets.commonTextFieldForLoginSignUP(
              //   context: context,
              //   controller: _cityController,
              //   labelText: 'City (optional)',
              //   hintText: 'Enter city',
              // ),
              // const SizedBox(height: 10),
              // CommonWidgets.commonTextFieldForLoginSignUP(
              //   context: context,
              //   controller: _provinceController,
              //   labelText: 'Province (optional)',
              //   hintText: 'Enter province',
              // ),
              // const SizedBox(height: 10),
              // CommonWidgets.commonTextFieldForLoginSignUP(
              //   context: context,
              //   controller: _countryController,
              //   labelText: 'Country (optional)',
              //   hintText: 'Enter country',
              // ),
              const SizedBox(height: 18),
              const Text(
                'Activities',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _activities.entries
                    .map((entry) {
                      return FilterChip(
                        selected: entry.value,
                        label: Text(entry.key),
                        onSelected: (selected) {
                          setState(() {
                            _activities[entry.key] = selected;
                          });
                        },
                      );
                    })
                    .toList(growable: false),
              ),
              if (error != null && error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                  foregroundColor: PlayerUiSignalTheme.secondaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: loading ? null : _save,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Profile',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requiredField(
    TextEditingController controller,
    String label, {
    Widget? prefix,
  }) {
    return CommonWidgets.commonTextFieldForLoginSignUP(
      context: context,
      controller: controller,
      labelText: label,
      hintText: 'Enter $label',
      prefix: prefix,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label is required';
        }
        return null;
      },
    );
  }
}
