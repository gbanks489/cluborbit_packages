import 'dart:typed_data';

import 'package:clubcommon/clubcommon.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/playerchat_router.dart';

class OnboardAddPhotoPage extends StatefulWidget {
  const OnboardAddPhotoPage({super.key});

  @override
  State<OnboardAddPhotoPage> createState() => _OnboardAddPhotoPageState();
}

class _OnboardAddPhotoPageState extends State<OnboardAddPhotoPage> {
  Uint8List? _imageBytes;
  String? _imageFilename;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await pickPlayerUiProfileImage();
    if (picked == null) {
      return;
    }

    setState(() {
      _imageBytes = picked.bytes;
      _imageFilename = picked.filename;
    });
  }

  void _continue() {
    context.pushNamed(
      PlayerChatRoutes.onboardingProfile,
      extra: PlayerChatOnboardingDraft(
        imageBytes: _imageBytes,
        imageFilename: _imageFilename,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            Center(
              child: Image.asset(
                'assets/images/logo_icon.png',
                width: 88,
                height: 88,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add your photo',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the image people will see when they find you in the app.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'Poppins',
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withAlpha(24)),
              ),
              child: Column(
                children: [
                  PlayerUiProfileUploadCard(
                    imageBytes: _imageBytes,
                    filename: _imageFilename,
                    onPickImage: _pickImage,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                        foregroundColor: PlayerUiSignalTheme.secondaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _continue,
                      child: const Text(
                        'Next',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
