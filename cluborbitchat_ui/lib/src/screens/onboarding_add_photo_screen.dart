import 'dart:typed_data';

import 'package:clubcommon/clubcommon.dart';
import 'package:flutter/material.dart';

import 'onboarding_additional_info_screen.dart';

class OnboardingAddPhotoScreen extends StatefulWidget {
  const OnboardingAddPhotoScreen({super.key});

  @override
  State<OnboardingAddPhotoScreen> createState() =>
      _OnboardingAddPhotoScreenState();
}

class _OnboardingAddPhotoScreenState extends State<OnboardingAddPhotoScreen> {
  Uint8List? _imageBytes;
  String? _filename;

  Future<void> _pickImage() async {
    final pickedImage = await pickPlayerUiProfileImage();
    if (pickedImage == null) {
      return;
    }

    setState(() {
      _imageBytes = pickedImage.bytes;
      _filename = pickedImage.filename;
    });
  }

  Future<void> _continue() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OnboardingAdditionalInfoScreen(imageBytes: _imageBytes),
      ),
    );

    if (!mounted) {
      return;
    }
    if (completed == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboarding')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add a profile photo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This matches PlayerUI onboarding and helps others identify you in ClubOrbit Chat.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            const SizedBox(height: 24),
            PlayerUiProfileUploadCard(
              imageBytes: _imageBytes,
              filename: _filename,
              onPickImage: _pickImage,
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                foregroundColor: PlayerUiSignalTheme.secondaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _continue,
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
