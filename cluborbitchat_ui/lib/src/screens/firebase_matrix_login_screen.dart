import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

import '../app/playerchat_router.dart';

class FirebaseMatrixLoginScreen extends StatefulWidget {
  const FirebaseMatrixLoginScreen({super.key});

  @override
  State<FirebaseMatrixLoginScreen> createState() =>
      _FirebaseMatrixLoginScreenState();
}

class _FirebaseMatrixLoginScreenState extends State<FirebaseMatrixLoginScreen> {
  bool _showCanadaFlag = false;
  bool _checkingAutoLogin = true;

  @override
  void initState() {
    super.initState();
    _detectCanadaFromIp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptAutoLogin();
    });
  }

  Future<void> _attemptAutoLogin() async {
    if (!mounted) {
      return;
    }
    final controller = context.read<ChatController>();
    if (controller.matrixUserId.isNotEmpty) {
      await _openChatIfConnected();
      return;
    }
    final connected = await controller.tryAutoLoginAndConnect();
    if (!mounted) {
      return;
    }
    if (connected) {
      await _openChatIfConnected();
      return;
    }
    setState(() {
      _checkingAutoLogin = false;
    });
  }

  Future<void> _detectCanadaFromIp() async {
    final countryCode = await context
        .read<ConnectivityService>()
        .detectCountryCode();
    if (!mounted) {
      return;
    }

    setState(() {
      _showCanadaFlag = countryCode == 'CA';
    });
  }

  Future<void> _openChatIfConnected() async {
    if (!mounted) {
      return;
    }
    context.goNamed(PlayerChatRoutes.chats);
  }

  void _showErrorSnackBar([Object? error]) {
    if (!mounted) {
      return;
    }
    final notifierMessage = context.read<ErrorNotifier>().errorMessage?.trim();
    final fallback = error?.toString().trim();
    final message = (notifierMessage != null && notifierMessage.isNotEmpty)
        ? notifierMessage
        : ((fallback != null && fallback.isNotEmpty)
              ? fallback.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '')
              : 'Sign in failed');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final error = context.watch<ErrorNotifier>().errorMessage;

    if (_checkingAutoLogin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PlayerUiLoginPage(
      loading: controller.loading,
      error: error,
      showCanadaFlag: _showCanadaFlag,
      onOpenSignup: () {
        context.pushNamed(PlayerChatRoutes.signup);
      },
      onLogin: (email, password) async {
        try {
          await controller.signInAndConnectWithEmail(
            email: email,
            password: password,
          );
          await _openChatIfConnected();
        } catch (error) {
          _showErrorSnackBar(error);
        }
      },
      onGoogle: () async {
        try {
          await controller.signInAndConnectWithGoogle();
          await _openChatIfConnected();
        } catch (error) {
          _showErrorSnackBar(error);
        }
      },
    );
  }
}
