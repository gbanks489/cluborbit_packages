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
      context.read<ChatController>().refreshChatDetails();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatController>(
      builder: (context, controller, _) {
        final participants = controller.participants;
        final verifications = controller.verificationSessions;
        final roomTitle = controller.activeRoomTitle ?? 'Chat details';
        final roomAvatarUrl = controller.activeRoomAvatarUrl;
        final encryption = controller.activeRoomEncryptionStatus;

        return Scaffold(
          appBar: AppBar(title: Text(roomTitle)),
          body: ListView(
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
                                        color:
                                            PlayerUiSignalTheme.secondaryColor,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.photo_camera_outlined,
                                      size: 16,
                                      color: PlayerUiSignalTheme.secondaryColor,
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                const ListTile(title: Text('No member data loaded yet.')),
              for (final participant in participants)
                Card(
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundImage: participant.avatarUrl != null
                          ? NetworkImage(participant.avatarUrl!)
                          : null,
                      child: participant.avatarUrl == null
                          ? Text(
                              participant.displayName.isEmpty
                                  ? '?'
                                  : participant.displayName[0].toUpperCase(),
                            )
                          : null,
                    ),
                    title: Text(participant.displayName),
                    subtitle: Text(participant.membership),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text(_roleLabel(participant.level))),
                        IconButton(
                          onPressed: () async {
                            await controller.startKeyVerificationForUser(
                              participant.userId,
                            );
                          },
                          icon: const Icon(Icons.verified_user_outlined),
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
                const ListTile(title: Text('No active verification sessions.')),
              for (final session in verifications)
                Card(
                  child: ListTile(
                    title: Text(session.userId),
                    subtitle: Text('state: ${session.state}'),
                    trailing: session.isDone
                        ? const Chip(label: Text('Done'))
                        : Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                onPressed: () async {
                                  await controller.acceptVerification(
                                    session.id,
                                  );
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                tooltip: 'Accept verification',
                              ),
                              IconButton(
                                onPressed: () async {
                                  await controller.acceptSas(session.id);
                                },
                                icon: const Icon(Icons.tag_faces_outlined),
                                tooltip: 'Accept SAS',
                              ),
                              IconButton(
                                onPressed: () async {
                                  await controller.rejectVerification(
                                    session.id,
                                  );
                                },
                                icon: const Icon(Icons.cancel_outlined),
                                tooltip: 'Reject verification',
                              ),
                            ],
                          ),
                  ),
                ),
            ],
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
