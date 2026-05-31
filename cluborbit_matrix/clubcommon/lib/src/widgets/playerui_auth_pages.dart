import 'dart:typed_data';

import 'package:clubcommon/clubcommon.dart';
import 'package:clubcommon/src/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

enum SigninMethod { password, google }

class PlayerUiLoginPage extends StatefulWidget {
  const PlayerUiLoginPage({
    super.key,
    required this.loading,
    this.error,
    required this.onLogin,
    required this.onGoogle,
    required this.onOpenSignup,
    this.onResetPassword,
    this.showCanadaFlag = false,
  });

  final bool loading;
  final String? error;
  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function() onGoogle;
  final VoidCallback onOpenSignup;
  final VoidCallback? onResetPassword;
  final bool showCanadaFlag;

  @override
  State<PlayerUiLoginPage> createState() => _PlayerUiLoginPageState();
}

class _PlayerUiLoginPageState extends State<PlayerUiLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  //bool _obscurePassword = true;
  bool _isLoading = false;
  bool _obscurePasswordText = true;
  bool _showCanadaFlag = false;

  @override
  void initState() {
    super.initState();
    _showCanadaFlag = widget.showCanadaFlag;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void navigateToSignUp() {
    if (_isLoading || widget.loading) {
      return;
    }
    widget.onOpenSignup();
  }

  void navigateToResetPassword() {
    if (_isLoading || widget.loading) {
      return;
    }
    widget.onResetPassword?.call();
  }

  Future<void> loginUser(SigninMethod method) async {
    if (_isLoading || widget.loading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (method == SigninMethod.password) {
        await widget.onLogin(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await widget.onGoogle();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 25.px),
          child: ListView(
            children: [
              SizedBox(height: 64.px),
              Center(
                child: SizedBox(
                  width: context.deviceWidth * 0.5,
                  height: context.deviceHeight * 0.06,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Image.asset(
                          'assets/images/logo_full2.png',
                          height: context.deviceHeight * 0.05,
                          width: context.deviceWidth * 0.5,
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (_showCanadaFlag)
                        const Positioned(
                          right: 0,
                          bottom: 0,
                          child: Text('🇨🇦', style: TextStyle(fontSize: 16)),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 50.px),
              // SizedBox(height: 50.px),
              Text(
                "Login",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: "Poppins",
                ),
              ),
              SizedBox(height: 5.px),
              Text(
                "Enter your email and password",
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontFamily: "Poppins"),
              ),
              SizedBox(height: 20.px),
              CommonWidgets.commonTextFieldForLoginSignUP(
                context: context,
                controller: _emailController,
                labelText: "Email",
                keyboardType: TextInputType.emailAddress,
                prefixIcon: "assets/icon/ic_mail.svg",
                prefixIconColor: PlayerUiSignalTheme.primaryDarkColor,
              ),
              SizedBox(height: 24.px),
              PlayerUiPasswordField(
                controller: _passwordController,
                label: "Password",
                obscureText: _obscurePasswordText,
                enabled: !_isLoading && !widget.loading,
                onToggle: () {
                  setState(() {
                    _obscurePasswordText = !_obscurePasswordText;
                  });
                },
              ),
              SizedBox(height: 10.px),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: navigateToResetPassword,
                    child: Text(
                      "Forgot Password ?",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: "Poppins",
                        fontSize: 13,
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    "Don't have an account?",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(width: 2),
                  GestureDetector(
                    onTap: navigateToSignUp,
                    child: Text(
                      "Sign up",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24.px),
              InkWell(
                onTap: () {
                  loginUser(SigninMethod.password);
                },
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: const ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    color: PlayerUiSignalTheme.primaryDarkColor,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PlayerUiSignalTheme.secondaryColor,
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: "Poppins",
                          ),
                        ),
                ),
              ),
              SizedBox(height: 30.px),
              Align(
                alignment: Alignment.center,
                child: Text(
                  "Or",
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontFamily: "Poppins"),
                ),
              ),
              SizedBox(height: 30.px),
              Theme.of(context).platform != TargetPlatform.iOS
                  ? GestureDetector(
                      onTap: () {
                        loginUser(SigninMethod.google);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xffF7F8F8).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(15.px),
                          border: Border.all(
                            color: const Color(0xFFF7F8F8),
                            width: 0.5.px,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 35.px,
                          vertical: 15.px,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              "assets/icon/ic_google.png",
                              height: 25.px,
                              width: 25.px,
                            ),
                            SizedBox(width: 5),
                            Text(
                              "Google",
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontFamily: "Poppins",
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        loginUser(SigninMethod.google);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xffF7F8F8).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(15.px),
                          border: Border.all(
                            color: const Color(0xFFF7F8F8),
                            width: 0.5.px,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 35.px,
                          vertical: 15.px,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              "assets/icon/ic_apple.png",
                              height: 25.px,
                              width: 25.px,
                            ),
                            SizedBox(width: 5),
                            Text(
                              "Apple",
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontFamily: "Poppins",
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
    /*
    return 
    SafeArea(
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ListView(
            children: [
              const SizedBox(height: 56),
              Center(
                child: SizedBox(
                  width: 220,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        children: const [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 42,
                            color: PlayerUiSignalTheme.primaryDarkColor,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'ClubOrbit',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          Text(
                            'PlayerUI Secure Messaging',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                      if (widget.showCanadaFlag)
                        const Positioned(
                          right: 20,
                          top: 0,
                          child: Text('🇨🇦', style: TextStyle(fontSize: 18)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 42),
              const Text(
                'Login',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter your email and password',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                  foregroundColor: PlayerUiSignalTheme.secondaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: widget.loading
                    ? null
                    : () => widget.onLogin(
                        _emailController.text.trim(),
                        _passwordController.text,
                      ),
                child: widget.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Login',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: widget.loading ? null : widget.onGoogle,
                icon: const Icon(Icons.g_mobiledata),
                label: const Text(
                  'Continue with Google',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: widget.loading ? null : widget.onOpenSignup,
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if ((widget.error ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    widget.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ); */
  }
}

class PlayerUiSignupData {
  const PlayerUiSignupData({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.gender,
    required this.dateOfBirth,
    this.imageBytes,
  });

  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String displayName;
  final String gender;
  final DateTime dateOfBirth;
  final Uint8List? imageBytes;
}

class PlayerUiSignupPage extends StatefulWidget {
  const PlayerUiSignupPage({
    super.key,
    required this.loading,
    this.error,
    required this.onSignup,
    required this.onBackToLogin,
  });

  final bool loading;
  final String? error;
  final Future<void> Function(PlayerUiSignupData data) onSignup;
  final VoidCallback onBackToLogin;

  @override
  State<PlayerUiSignupPage> createState() => _PlayerUiSignupPageState();
}

class _PlayerUiSignupPageState extends State<PlayerUiSignupPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageFilename;
  DateTime _dob = DateTime(2000, 1, 1);
  String _gender = 'male';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _displayNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dob,
      firstDate: DateTime(1930, 1, 1),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() {
        _dob = selected;
      });
    }
  }

  Future<void> _pickImage() async {
    final pickedImage = await pickPlayerUiProfileImage();
    if (pickedImage == null) {
      return;
    }

    setState(() {
      _imageBytes = pickedImage.bytes;
      _imageFilename = pickedImage.filename;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.onSignup(
      PlayerUiSignupData(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        displayName: _displayNameController.text.trim(),
        gender: _gender,
        dateOfBirth: _dob,
        imageBytes: _imageBytes,
      ),
    );
  }

  Widget _requiredField(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    Widget? prefix,
  }) {
    return CommonWidgets.commonTextFieldForLoginSignUP(
      context: context,
      controller: controller,
      keyboardType: keyboardType,
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Onboarding')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Create your account',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This matches the PlayerUI onboarding flow so profile setup and account creation use the same shared components.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontFamily: 'Poppins'),
              ),
              const SizedBox(height: 24),
              PlayerUiProfileUploadCard(
                imageBytes: _imageBytes,
                filename: _imageFilename,
                enabled: !widget.loading,
                onPickImage: _pickImage,
              ),
              const SizedBox(height: 20),
              _requiredField(
                _firstNameController,
                'First Name',
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_fullname.svg',
                  color: PlayerUiSignalTheme.primaryDarkColor,
                ),
              ),
              const SizedBox(height: 10),
              _requiredField(
                _lastNameController,
                'Last Name',
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_fullname.svg',
                  color: PlayerUiSignalTheme.primaryDarkColor,
                ),
              ),
              const SizedBox(height: 10),
              _requiredField(
                _displayNameController,
                'Display Name',
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_fullname.svg',
                  color: PlayerUiSignalTheme.primaryDarkColor,
                ),
              ),
              const SizedBox(height: 10),
              _requiredField(
                _emailController,
                'Email',
                keyboardType: TextInputType.emailAddress,
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_email.svg',
                  color: PlayerUiSignalTheme.primaryDarkColor,
                ),
              ),
              const SizedBox(height: 10),
              PlayerUiSelectorField(
                label: 'Gender',
                prefix: const PlayerUiSvgPrefix(
                  assetName: 'packages/clubcommon/assets/icon/ic_gender.svg',
                  color: PlayerUiSignalTheme.primaryDarkColor,
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
                    ],
                    onChanged: widget.loading
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _gender = value;
                              });
                            }
                          },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PlayerUiDateOfBirthField(
                value: _dob,
                onTap: widget.loading ? () {} : _pickDob,
              ),
              const SizedBox(height: 10),
              PlayerUiPasswordField(
                controller: _passwordController,
                label: 'Password',
                obscureText: _obscurePassword,
                enabled: !widget.loading,
                onToggle: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              PlayerUiPasswordField(
                controller: _confirmController,
                label: 'Confirm Password',
                obscureText: _obscureConfirm,
                enabled: !widget.loading,
                onToggle: () {
                  setState(() {
                    _obscureConfirm = !_obscureConfirm;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              if ((widget.error ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    widget.error!,
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
                onPressed: widget.loading ? null : _submit,
                child: widget.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: widget.loading ? null : widget.onBackToLogin,
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: PlayerUiSignalTheme.primaryDarkColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
