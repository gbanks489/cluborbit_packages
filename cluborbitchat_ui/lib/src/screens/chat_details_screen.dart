import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:provider/provider.dart';

const Color _groupAvatarBackgroundColor = Color(0xFFE7EAED);
const Color _groupAvatarForegroundColor = Color(0xFFADB4BA);

class ChatDetailsScreen extends StatefulWidget {
  const ChatDetailsScreen({super.key});

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        context.read<ChatController>().refreshChatDetails().catchError((_) {}),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        final participants = controller.participants;
        final participantNameByUserId = <String, String>{
          for (final participant in participants)
            participant.userId: participant.displayName,
        };
        final verifications = controller.verificationSessions;
        final roomTitle = controller.activeRoomTitle ?? 'Chat details';
        final roomAvatarUrl = controller.activeRoomAvatarUrl;
        final encryption = controller.activeRoomEncryptionStatus;

        return Scaffold(
          appBar: AppBar(title: Text(roomTitle)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _uploadingAvatar
                            ? null
                            : () => _pickAndUploadRoomAvatar(controller),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _RoomAvatar(imageUrl: roomAvatarUrl, radius: 46),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    PlayerUiSignalTheme.primaryDarkColor,
                                child: _uploadingAvatar
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: PlayerUiSignalTheme
                                              .secondaryColor,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.photo_camera_outlined,
                                        size: 16,
                                        color:
                                            PlayerUiSignalTheme.secondaryColor,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _uploadingAvatar
                            ? null
                            : () => _pickAndUploadRoomAvatar(controller),
                        child: const Text('Change group avatar'),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: PlayerUiSignalTheme.mobileBackgroundColor,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: encryption.isEncrypted
                                ? const Color(0xFF44CC77)
                                : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              encryption.isEncrypted
                                  ? Icons.lock_outline
                                  : Icons.lock_open_outlined,
                              size: 18,
                              color: encryption.isEncrypted
                                  ? const Color(0xFF44CC77)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              encryption.isEncrypted
                                  ? 'End-to-end encrypted'
                                  : 'Not end-to-end encrypted',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((encryption.algorithm ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          encryption.algorithm!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      const Text(
                        'Verification sessions only appear after a key verification request starts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (!encryption.isEncrypted) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'This room does not currently expose an m.room.encryption state event. Older groups stay unencrypted unless the room was created or configured with encryption enabled.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Members',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (participants.isEmpty)
                  ListTile(
                    tileColor: PlayerUiSignalTheme.mobileSearchColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    title: const Text(
                      'No member data loaded yet.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                for (final participant in participants)
                  Card(
                    color: PlayerUiSignalTheme.mobileSearchColor,
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor:
                            PlayerUiSignalTheme.mobileBackgroundColor,
                        backgroundImage: participant.avatarUrl != null
                            ? NetworkImage(participant.avatarUrl!)
                            : null,
                        child: participant.avatarUrl == null
                            ? Text(
                                participant.displayName.isEmpty
                                    ? '?'
                                    : participant.displayName[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              )
                            : null,
                      ),
                      title: Text(
                        participant.displayName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        participant.membership,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          Chip(
                            backgroundColor:
                                PlayerUiSignalTheme.mobileBackgroundColor,
                            label: Text(
                              _roleLabel(participant.level),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              await controller.startKeyVerificationForUser(
                                participant.userId,
                              );
                            },
                            icon: const Icon(
                              Icons.verified_user_outlined,
                              color: PlayerUiSignalTheme.primaryDarkColor,
                            ),
                            tooltip: 'Start key verification',
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Key Verification Sessions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (verifications.isEmpty)
                  ListTile(
                    tileColor: PlayerUiSignalTheme.mobileSearchColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    title: const Text(
                      'No active verification sessions.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                for (final session in verifications)
                  Card(
                    color: PlayerUiSignalTheme.mobileSearchColor,
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _verificationStateColor(
                          session,
                        ).withValues(alpha: 0.18),
                        child: Icon(
                          _verificationStateIcon(session),
                          color: _verificationStateColor(session),
                        ),
                      ),
                      title: Text(
                        _verificationParticipantName(
                          session.userId,
                          participantNameByUserId,
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _verificationStateDisplay(session.state),
                        style: TextStyle(
                          color: _verificationStateColor(session),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: session.isDone
                          ? const Chip(
                              backgroundColor: Color(0xFF2E7D32),
                              label: Text(
                                'Verified',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  onPressed: () async {
                                    await controller.acceptVerification(
                                      session.id,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  tooltip: 'Accept verification',
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await controller.acceptSas(session.id);
                                  },
                                  icon: const Icon(
                                    Icons.tag_faces_outlined,
                                    color: Color(0xFF43A047),
                                  ),
                                  tooltip: 'Accept SAS',
                                ),
                                IconButton(
                                  onPressed: () async {
                                    await controller.rejectVerification(
                                      session.id,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    color: Color(0xFFC62828),
                                  ),
                                  tooltip: 'Reject verification',
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _roleLabel(ChatMemberLevel level) {
    switch (level) {
      case ChatMemberLevel.owner:
        return 'owner';
      case ChatMemberLevel.admin:
        return 'admin';
      case ChatMemberLevel.moderator:
        return 'moderator';
      case ChatMemberLevel.member:
        return 'member';
    }
  }

  String _verificationParticipantName(
    String userId,
    Map<String, String> participantNameByUserId,
  ) {
    final displayName = (participantNameByUserId[userId] ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return 'Unknown participant';
  }

  String _verificationStateDisplay(String rawState) {
    final normalized = rawState.trim();
    if (normalized.isEmpty) {
      return 'Pending';
    }
    final words = normalized
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    return words;
  }

  Color _verificationStateColor(VerificationSession session) {
    final state = session.state.toLowerCase();
    if (session.isDone ||
        state.contains('done') ||
        state.contains('complete')) {
      return const Color(0xFF2E7D32);
    }
    if (state.contains('reject') ||
        state.contains('cancel') ||
        state.contains('declin') ||
        state.contains('fail') ||
        state.contains('error')) {
      return const Color(0xFFC62828);
    }
    return const Color(0xFF43A047);
  }

  IconData _verificationStateIcon(VerificationSession session) {
    final state = session.state.toLowerCase();
    if (session.isDone ||
        state.contains('done') ||
        state.contains('complete')) {
      return Icons.verified_rounded;
    }
    if (state.contains('reject') ||
        state.contains('cancel') ||
        state.contains('declin') ||
        state.contains('fail') ||
        state.contains('error')) {
      return Icons.gpp_bad_outlined;
    }
    return Icons.verified_user_outlined;
  }

  Future<void> _pickAndUploadRoomAvatar(ChatController controller) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 92,
    );
    if (file == null) {
      return;
    }

    final bytes = await file.readAsBytes();
    if (!mounted || bytes.isEmpty) {
      return;
    }

    setState(() => _uploadingAvatar = true);
    try {
      await controller.updateActiveRoomAvatar(
        avatarBytes: bytes,
        filename: file.name.isEmpty ? 'group-avatar.jpg' : file.name,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not update avatar: $e')));
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }
}

class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({required this.imageUrl, required this.radius});

  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _groupAvatarBackgroundColor,
      child: ClipOval(
        child: (imageUrl ?? '').trim().isEmpty
            ? _fallbackIcon
            : Image.network(
                imageUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallbackIcon,
              ),
      ),
    );
  }

  Widget get _fallbackIcon {
    return Icon(
      Icons.groups_rounded,
      size: radius * 0.8,
      color: _groupAvatarForegroundColor,
    );
  }
}
