import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

import '../app/playerchat_router.dart';

class OnboardAddProfilePage extends StatefulWidget {
  const OnboardAddProfilePage({
    super.key,
    this.draft = const PlayerChatOnboardingDraft(),
  });

  final PlayerChatOnboardingDraft draft;

  @override
  State<OnboardAddProfilePage> createState() => _OnboardAddProfilePageState();
}

class _OnboardAddProfilePageState extends State<OnboardAddProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  late String _gender;

  @override
  void initState() {
    super.initState();
    _displayNameController.text = widget.draft.displayName;
    _gender = widget.draft.gender;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final controller = context.read<ChatController>();
    await controller.saveOnboardingProfile(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      gender: _gender,
      bio: null,
      dateOfBirth: null,
      imageBytes: widget.draft.imageBytes,
    );

    if (!mounted) {
      return;
    }

    unawaited(controller.connectMatrixUsingProfileInBackground());
    context.goNamed(PlayerChatRoutes.chats);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final error = context.watch<ErrorNotifier>().errorMessage;

    return Scaffold(
      backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
      body: SafeArea(
        child: ListView(
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
              'Build your profile',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Finish your public profile and then we will take you straight into the app.',
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Gender',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _GenderCard(
                            label: 'Male',
                            assetName: 'assets/images/img_boy.png',
                            imagePadding: const EdgeInsets.all(6),
                            imageFit: BoxFit.contain,
                            selected: _gender == 'male',
                            onTap: controller.loading
                                ? null
                                : () {
                                    setState(() {
                                      _gender = 'male';
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _GenderCard(
                            label: 'Female',
                            assetName: 'assets/images/img_girl.png',
                            selected: _gender == 'female',
                            onTap: controller.loading
                                ? null
                                : () {
                                    setState(() {
                                      _gender = 'female';
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    CommonWidgets.commonTextFieldForLoginSignUP(
                      context: context,
                      controller: _displayNameController,
                      labelText: 'Display Name',
                      hintText: 'Enter the name shown in chat',
                      prefix: const PlayerUiSvgPrefix(
                        assetName: 'assets/icon/ic_fullname.svg',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Display name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: CommonWidgets.commonTextFieldForLoginSignUP(
                            context: context,
                            controller: _firstNameController,
                            labelText: 'First Name',
                            hintText: 'First name',
                            prefix: const PlayerUiSvgPrefix(
                              assetName: 'assets/icon/ic_fullname.svg',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'First name is required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CommonWidgets.commonTextFieldForLoginSignUP(
                            context: context,
                            controller: _lastNameController,
                            labelText: 'Last Name',
                            hintText: 'Last name',
                            prefix: const PlayerUiSvgPrefix(
                              assetName: 'assets/icon/ic_fullname.svg',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Last name is required';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if ((error ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                          foregroundColor: PlayerUiSignalTheme.secondaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: controller.loading ? null : _finish,
                        child: controller.loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Enter App',
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
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.label,
    required this.assetName,
    required this.selected,
    required this.onTap,
    this.imagePadding = EdgeInsets.zero,
    this.imageFit = BoxFit.cover,
  });

  final String label;
  final String assetName;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsets imagePadding;
  final BoxFit imageFit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? PlayerUiSignalTheme.primaryDarkColor.withAlpha(36)
              : Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? PlayerUiSignalTheme.primaryDarkColor
                : Colors.white.withAlpha(18),
          ),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: imagePadding,
                  child: Image.asset(assetName, fit: imageFit),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
