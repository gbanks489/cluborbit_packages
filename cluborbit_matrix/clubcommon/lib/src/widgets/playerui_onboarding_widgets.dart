import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

import 'common_text_widget.dart';
import '../theme/playerui_theme.dart';

class PlayerUiPickedImage {
  const PlayerUiPickedImage({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

Future<PlayerUiPickedImage?> pickPlayerUiProfileImage() async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 90,
  );
  if (file == null) {
    return null;
  }

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }

  return PlayerUiPickedImage(bytes: bytes, filename: file.name);
}

class PlayerUiSvgPrefix extends StatelessWidget {
  const PlayerUiSvgPrefix({
    super.key,
    required this.assetName,
    this.color,
    this.size = 22,
  });

  final String assetName;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetName,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

class PlayerUiSelectorField extends StatelessWidget {
  const PlayerUiSelectorField({
    super.key,
    required this.label,
    required this.child,
    this.prefix,
    this.onTap,
  });

  final String label;
  final Widget child;
  final Widget? prefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: const Color(0xffF7F8F8).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFF7F8F8), width: 0.5.px),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.px, vertical: 4.px),
        child: Row(
          children: [
            if (prefix != null)
              Padding(
                padding: EdgeInsets.only(right: 8.px),
                child: prefix,
              ),
            Expanded(
              child: InputDecorator(
                decoration:
                    const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ).copyWith(
                      labelText: label,
                      labelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontSize: 14,
                      ),
                    ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}

class PlayerUiDateOfBirthField extends StatelessWidget {
  const PlayerUiDateOfBirthField({
    super.key,
    required this.value,
    required this.onTap,
  });

  final DateTime value;
  final VoidCallback onTap;

  String get _formattedDob {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PlayerUiSelectorField(
      label: 'Date of Birth',
      onTap: onTap,
      prefix: const PlayerUiSvgPrefix(
        assetName: 'packages/clubcommon/assets/icon/ic_dob.svg',
        color: PlayerUiSignalTheme.primaryDarkColor,
      ),
      child: Text(
        _formattedDob,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontFamily: 'Poppins'),
      ),
    );
  }
}

class PlayerUiProfileUploadCard extends StatelessWidget {
  const PlayerUiProfileUploadCard({
    super.key,
    this.imageBytes,
    this.filename,
    this.onPickImage,
    this.enabled = true,
  });

  final Uint8List? imageBytes;
  final String? filename;
  final VoidCallback? onPickImage;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: PlayerUiSignalTheme.primaryDarkColor,
            ),
            child: CircleAvatar(
              radius: 52,
              backgroundColor: Colors.white12,
              backgroundImage: imageBytes == null
                  ? null
                  : MemoryImage(imageBytes!),
              child: imageBytes == null
                  ? ClipOval(
                      child: Image.asset(
                        'packages/clubcommon/assets/images/blank_profile_pic.png',
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: enabled ? onPickImage : null,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(
            imageBytes == null ? 'Choose Photo' : 'Change Photo',
            style: const TextStyle(fontFamily: 'Poppins'),
          ),
        ),
      ],
    );
  }
}

class PlayerUiPasswordField extends StatelessWidget {
  const PlayerUiPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.onToggle,
    this.hintText,
    this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final VoidCallback onToggle;
  final String? hintText;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return CommonWidgets.commonTextFieldForLoginSignUP(
      context: context,
      controller: controller,
      labelText: label,
      hintText: hintText ?? 'Enter $label',
      obscureText: obscureText,
      readOnly: !enabled,
      prefix: const PlayerUiSvgPrefix(
        assetName: 'packages/clubcommon/assets/icon/ic_lock.svg',
        color: Colors.white,
      ),
      suffixIcon: SvgPicture.asset(
        obscureText
            ? 'packages/clubcommon/assets/icon/ic_hide_pass.svg'
            : 'packages/clubcommon/assets/icon/ic_eye.svg',
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        width: 18,
        height: 18,
      ),
      suffixIconOnTap: enabled ? onToggle : null,
      validator: validator,
    );
  }
}
