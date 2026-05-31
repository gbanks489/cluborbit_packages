import 'package:flutter/material.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:provider/provider.dart';

class CallSettingsScreen extends StatelessWidget {
  const CallSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        final settings = controller.incomingCallUxSettings;
        return Scaffold(
          backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
          appBar: AppBar(
            backgroundColor: PlayerUiSignalTheme.secondaryColor,
            title: const Text(
              'Call settings',
              style: TextStyle(color: PlayerUiSignalTheme.primaryDarkColor),
            ),
            iconTheme: const IconThemeData(
              color: PlayerUiSignalTheme.primaryDarkColor,
            ),
            actions: [
              TextButton(
                onPressed: controller.resetIncomingCallUxSettingsToDefaults,
                child: const Text(
                  'Reset',
                  style: TextStyle(
                    color: PlayerUiSignalTheme.primaryDarkColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            children: [
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                title: const Text(
                  'Auto-open full-screen incoming call',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'When disabled, keep only the compact top banner.',
                  style: TextStyle(color: Colors.white70),
                ),
                value: settings.autoOpenFullScreen,
                onChanged: controller.setAutoOpenIncomingFullScreen,
                activeThumbColor: PlayerUiSignalTheme.primaryDarkColor,
              ),
              const Divider(height: 1, color: Colors.white24),
              SwitchListTile.adaptive(
                title: const Text(
                  'Incoming ringtone',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Play alert sound while the call is ringing.',
                  style: TextStyle(color: Colors.white70),
                ),
                value: settings.ringtoneEnabled,
                onChanged: controller.setIncomingRingtoneEnabled,
                activeThumbColor: PlayerUiSignalTheme.primaryDarkColor,
              ),
              const Divider(height: 1, color: Colors.white24),
              SwitchListTile.adaptive(
                title: const Text(
                  'Incoming vibration',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Trigger haptic feedback for incoming calls.',
                  style: TextStyle(color: Colors.white70),
                ),
                value: settings.vibrationEnabled,
                onChanged: controller.setIncomingVibrationEnabled,
                activeThumbColor: PlayerUiSignalTheme.primaryDarkColor,
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}
