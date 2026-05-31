import 'package:flutter/material.dart';

const mobileBackgroundColor = Color.fromRGBO(12, 29, 54, 1);
const webBackgroundColor = Color.fromRGBO(12, 29, 54, 1);
const mobileSearchColor = Color.fromRGBO(38, 38, 38, 1);
const primaryDarkColor = Color.fromRGBO(249, 204, 11, 1);
const blueColor = Color.fromRGBO(0, 149, 246, 1);
const primaryColor = Color.fromRGBO(0, 149, 246, 1);
const secondaryColor = Color.fromRGBO(12, 29, 54, 1);
const textColorDark = Colors.black;

extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get text => theme.textTheme;
  double get deviceHeight => MediaQuery.of(this).size.height;
  double get deviceWidth => MediaQuery.of(this).size.width;
}