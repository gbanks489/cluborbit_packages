import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/call_settings_screen.dart';
import '../screens/chat_list_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/create_chat_screen.dart';
import '../screens/firebase_matrix_login_screen.dart';
import '../screens/onboard_add_photo_page.dart';
import '../screens/onboard_add_profile_page.dart';
import '../screens/signup_screen.dart';
import '../screens/user_profile_view_screen.dart';

abstract final class PlayerChatRoutes {
  static const String login = 'login';
  static const String chats = 'chats';
  static const String signup = 'signup';
  static const String createChat = 'create-chat';
  static const String profile = 'profile';
  static const String callSettings = 'call-settings';
  static const String chat = 'chat';
  static const String onboardingPhoto = 'onboarding-photo';
  static const String onboardingProfile = 'onboarding-profile';

  static const String loginPath = '/';
  static const String chatsPath = '/chats';
  static const String signupPath = '/signup';
  static const String createChatPath = '/chats/new';
  static const String profilePath = '/profile';
  static const String callSettingsPath = '/call-settings';
  static const String chatPath = '/chat';
  static const String onboardingPhotoPath = '/onboarding/photo';
  static const String onboardingProfilePath = '/onboarding/profile';
}

class PlayerChatChatRouteData {
  const PlayerChatChatRouteData({required this.title, this.avatarUrl});

  final String title;
  final String? avatarUrl;
}

class PlayerChatOnboardingDraft {
  const PlayerChatOnboardingDraft({
    this.displayName = '',
    this.gender = 'male',
    this.imageBytes,
    this.imageFilename,
  });

  final String displayName;
  final String gender;
  final Uint8List? imageBytes;
  final String? imageFilename;
}

GoRouter createPlayerChatRouter() {
  return GoRouter(
    initialLocation: PlayerChatRoutes.loginPath,
    routes: <RouteBase>[
      GoRoute(
        path: PlayerChatRoutes.loginPath,
        name: PlayerChatRoutes.login,
        builder: (context, state) => const FirebaseMatrixLoginScreen(),
      ),
      GoRoute(
        path: PlayerChatRoutes.chatsPath,
        name: PlayerChatRoutes.chats,
        builder: (context, state) => const ChatListScreen(),
      ),
      GoRoute(
        path: PlayerChatRoutes.signupPath,
        name: PlayerChatRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: PlayerChatRoutes.createChatPath,
        name: PlayerChatRoutes.createChat,
        builder: (context, state) => const CreateChatScreen(),
      ),
      GoRoute(
        path: PlayerChatRoutes.profilePath,
        name: PlayerChatRoutes.profile,
        builder: (context, state) => UserProfileViewScreen(),
      ),
      GoRoute(
        path: PlayerChatRoutes.callSettingsPath,
        name: PlayerChatRoutes.callSettings,
        builder: (context, state) => CallSettingsScreen(),
      ),
      GoRoute(
        path: PlayerChatRoutes.chatPath,
        name: PlayerChatRoutes.chat,
        builder: (context, state) {
          final data = state.extra;
          if (data is! PlayerChatChatRouteData) {
            return const _MissingChatRouteDataScreen();
          }
          return ChatScreen(title: data.title, avatarUrl: data.avatarUrl);
        },
      ),
      GoRoute(
        path: PlayerChatRoutes.onboardingPhotoPath,
        name: PlayerChatRoutes.onboardingPhoto,
        builder: (context, state) => const OnboardAddPhotoPage(),
      ),
      GoRoute(
        path: PlayerChatRoutes.onboardingProfilePath,
        name: PlayerChatRoutes.onboardingProfile,
        builder: (context, state) {
          final data = state.extra;
          return OnboardAddProfilePage(
            draft: data is PlayerChatOnboardingDraft
                ? data
                : const PlayerChatOnboardingDraft(),
          );
        },
      ),
    ],
  );
}

class _MissingChatRouteDataScreen extends StatelessWidget {
  const _MissingChatRouteDataScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Chat route is missing navigation data.')),
    );
  }
}
