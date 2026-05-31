import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

import '../theme/playerui_theme.dart';

class CommonWidgets {
  static Widget appIconsSvg({
    required String assetName,
    double? width,
    double? height,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          assetName,
          height: height ?? 24.px,
          width: width ?? 24.px,
          colorFilter: color == null
              ? null
              : ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ],
    );
  }

  static Widget commonTextFieldForLoginSignUP({
    double? elevation,
    String? hintText,
    String? labelText,
    String? errorText,
    String? title,
    TextStyle? titleStyle,
    EdgeInsetsGeometry? contentPadding,
    TextEditingController? controller,
    int? maxLines = 1,
    double? cursorHeight,
    bool wantBorder = false,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
    Color? fillColor,
    Color? initialBorderColor,
    double? initialBorderWidth,
    TextInputType? keyboardType,
    double borderRadius = 15,
    double? maxHeight,
    TextStyle? hintStyle,
    TextStyle? style,
    TextStyle? labelStyle,
    TextStyle? errorStyle,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autofocus = false,
    bool readOnly = false,
    bool hintTextColor = false,
    Widget? suffixIcon,
    VoidCallback? suffixIconOnTap,
    String? prefixIcon,
    Color? prefixIconColor,
    Color? suffixIconColor,
    AutovalidateMode? autoValidateMode,
    int? maxLength,
    GestureTapCallback? onTap,
    bool obscureText = false,
    FocusNode? focusNode,
    MaxLengthEnforcement? maxLengthEnforcement,
    bool? filled,
    required BuildContext context,
    bool isCard = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
    int? minLines,
    Widget? prefix,
  }) {
    final child = Container(
      decoration: BoxDecoration(
        color: (fillColor ?? const Color(0xffF7F8F8)).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: initialBorderColor ?? const Color(0xFFF7F8F8),
          width: initialBorderWidth ?? 0.5.px,
        ),
      ),
      child: Padding(
        padding: contentPadding ?? EdgeInsets.symmetric(horizontal: 16.px),
        child: Row(
          children: [
            if (prefix != null)
              Padding(
                padding: EdgeInsets.only(right: 8.px),
                child: SizedBox(
                  width: 24.px,
                  height: 24.px,
                  child: Center(child: prefix),
                ),
              )
            else if (prefixIcon != null)
              Padding(
                padding: EdgeInsets.only(right: 8.px),
                child: SizedBox(
                  width: 24.px,
                  height: 24.px,
                  child: Center(
                    child: appIconsSvg(
                      assetName: prefixIcon,
                      color: prefixIconColor,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: TextFormField(
                focusNode: focusNode,
                maxLengthEnforcement: maxLengthEnforcement,
                obscureText: obscureText,
                onTap: onTap,
                minLines: minLines,
                maxLines: maxLines,
                maxLength: maxLength,
                cursorHeight: cursorHeight,
                cursorColor: PlayerUiSignalTheme.primaryDarkColor,
                autovalidateMode: autoValidateMode,
                controller: controller,
                onChanged: onChanged,
                validator: validator,
                keyboardType: keyboardType ?? TextInputType.text,
                textInputAction: textInputAction,
                onFieldSubmitted: onFieldSubmitted,
                readOnly: readOnly,
                autofocus: autofocus,
                inputFormatters: inputFormatters,
                textCapitalization: textCapitalization,
                style:
                    style ??
                    Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  errorText: errorText,
                  counterText: '',
                  errorStyle:
                      errorStyle ??
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  hintText: hintText,
                  labelText: labelText,
                  labelStyle:
                      labelStyle ??
                      const TextStyle(
                        fontFamily: 'Poppins',
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontSize: 14,
                      ),
                  fillColor: Colors.transparent,
                  filled: filled ?? false,
                  hintStyle:
                      hintStyle ??
                      Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: PlayerUiSignalTheme.primaryDarkColor,
                      ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
              ),
            ),
            if (suffixIcon != null)
              GestureDetector(onTap: suffixIconOnTap, child: suffixIcon),
          ],
        ),
      ),
    );

    if (maxHeight != null) {
      return SizedBox(height: maxHeight, child: child);
    }
    return child;
  }
}

class CommonTextWidget extends StatelessWidget {
  const CommonTextWidget({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.onTap,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.contentPadding,
    this.filled = true,
    this.borderRadius = 15,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? minLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final EdgeInsetsGeometry? contentPadding;
  final bool filled;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return CommonWidgets.commonTextFieldForLoginSignUP(
      context: context,
      controller: controller,
      hintText: hintText,
      labelText: labelText,
      validator: validator,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: minLines,
      readOnly: readOnly,
      onTap: onTap,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      focusNode: focusNode,
      autofocus: autofocus,
      contentPadding: contentPadding,
      filled: filled,
      borderRadius: borderRadius,
      suffixIcon: suffixIcon,
      prefix: prefixIcon,
    );
  }
}
