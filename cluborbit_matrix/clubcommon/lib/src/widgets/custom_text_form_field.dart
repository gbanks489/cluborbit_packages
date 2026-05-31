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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xffF7F8F8).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFF7F8F8), width: 0.5.px),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.px),
        child: Row(
          children: [
            if (prefixIcon != null)
              Padding(
                padding: EdgeInsets.only(right: 8.px),
                child: appIconsSvg(
                  assetName: prefixIcon,
                  color: prefixIconColor,
                ),
              ),
            Expanded(
              child: TextFormField(
                focusNode: focusNode,
                maxLengthEnforcement: maxLengthEnforcement,
                obscureText: obscureText,
                onTap: onTap,
                maxLines: maxLines,
                maxLength: maxLength,
                cursorHeight: cursorHeight,
                cursorColor: Color(0xFFF7F8F8),
                autovalidateMode: autoValidateMode,
                controller: controller,
                onChanged:
                    onChanged ??
                    (value) {
                      value = value.trim();
                      if (value.isEmpty || value.replaceAll(" ", "").isEmpty) {
                        controller?.text = "";
                      }
                    },
                validator: validator,
                keyboardType: keyboardType ?? TextInputType.streetAddress,
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
                    ).textTheme.headlineSmall?.copyWith(fontSize: 14.px),
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
                  labelStyle: TextStyle(
                    fontFamily: "Poppins",
                    color: PlayerUiSignalTheme.primaryDarkColor,
                    fontSize: 14,
                  ),
                  fillColor: fillColor ?? Theme.of(context).primaryColor,
                  filled: filled ?? false,
                  hintStyle:
                      hintStyle ??
                      TextStyle(
                        fontFamily: "Poppins",
                        fontSize: 12,
                        color: PlayerUiSignalTheme.primaryDarkColor,
                      ),
                  disabledBorder: InputBorder.none,
                  border: InputBorder.none,
                  errorBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            if (suffixIcon != null)
              GestureDetector(onTap: suffixIconOnTap, child: suffixIcon),
          ],
        ),
      ),
    );
  }
}
