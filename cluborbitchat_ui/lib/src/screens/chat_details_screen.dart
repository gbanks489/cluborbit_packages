import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cluborbit_matrix/cluborbit_matrix.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

const Color _groupAvatarBackgroundColor = Color(0xFFE7EAED);
const Color _groupAvatarForegroundColor = Color(0xFFADB4BA);
const Color _adminGreen = Color(0xFF25A35A);

/// A chat's details, laid out compactly like WhatsApp's group info: the picture and name, the
/// encryption line, files admins posted for members, the members (admins first), and any key
/// verification in progress.
class ChatDetailsScreen extends StatefulWidget {
  const ChatDetailsScreen({super.key});

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  bool _uploadingAvatar = false;
  String? _openingFileId;

  static const _sectionGap = SizedBox(height: 8);

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
        final participants = _sortedMembers(controller.participants);
        final participantNameByUserId = <String, String>{
          for (final participant in participants)
            participant.userId: participant.displayName,
        };
        final verifications = controller.verificationSessions;
        final roomTitle = controller.activeRoomTitle ?? 'Chat details';
        final isAdmin = controller.isActiveRoomAdmin;
        final files = controller.roomFiles;

        return Scaffold(
          backgroundColor: PlayerUiSignalTheme.mobileBackgroundColor,
          appBar: AppBar(
            title: const Text('Group info', style: TextStyle(fontSize: 17)),
          ),
          body: SafeArea(
            child: ListView(
              children: [
                _buildHeader(controller, roomTitle, participants.length),
                _sectionGap,
                _buildEncryptionRow(controller.activeRoomEncryptionStatus),
                if (isAdmin || files.isNotEmpty) ...[
                  _sectionGap,
                  _buildFilesSection(controller, files, isAdmin),
                ],
                _sectionGap,
                _buildMembersSection(controller, participants),
                if (verifications.isNotEmpty) ...[
                  _sectionGap,
                  _buildVerificationSection(
                    controller,
                    verifications,
                    participantNameByUserId,
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Sections -------------------------------------------------------------------------------

  Widget _section({required List<Widget> children}) => Container(
    color: PlayerUiSignalTheme.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _sectionTitle(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PlayerUiSignalTheme.textMuted,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _buildHeader(
    ChatController controller,
    String roomTitle,
    int memberCount,
  ) {
    return _section(
      children: [
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _uploadingAvatar
                ? null
                : () => _pickAndUploadRoomAvatar(controller),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _RoomAvatar(
                  imageUrl: controller.activeRoomAvatarUrl,
                  radius: 40,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: PlayerUiSignalTheme.primaryDarkColor,
                    child: _uploadingAvatar
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PlayerUiSignalTheme.onAccent,
                            ),
                          )
                        : Icon(
                            Icons.photo_camera_outlined,
                            size: 13,
                            color: PlayerUiSignalTheme.onAccent,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            roomTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: PlayerUiSignalTheme.text,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Group · $memberCount ${memberCount == 1 ? 'member' : 'members'}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: PlayerUiSignalTheme.textMuted),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildEncryptionRow(ChatEncryptionStatus encryption) {
    final encrypted = encryption.isEncrypted;
    return _section(
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
            size: 20,
            color: encrypted ? _adminGreen : PlayerUiSignalTheme.textMuted,
          ),
          title: Text(
            encrypted ? 'Encrypted' : 'Not encrypted',
            style: TextStyle(fontSize: 14, color: PlayerUiSignalTheme.text),
          ),
          subtitle: Text(
            encrypted
                ? 'Messages are end-to-end encrypted.'
                : 'Messages in this older group are not end-to-end encrypted.',
            style: TextStyle(fontSize: 12, color: PlayerUiSignalTheme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildFilesSection(
    ChatController controller,
    List<ChatRoomFile> files,
    bool isAdmin,
  ) {
    return _section(
      children: [
        _sectionTitle(
          files.isEmpty ? 'Files' : 'Files · ${files.length}',
          trailing: isAdmin
              ? (controller.roomFilesBusy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Post a file for members',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.add,
                          size: 20,
                          color: PlayerUiSignalTheme.primaryDarkColor,
                        ),
                        onPressed: () => _addFile(controller),
                      ))
              : null,
        ),
        if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Post files here for members - schedules, rules, forms.',
              style: TextStyle(
                fontSize: 12,
                color: PlayerUiSignalTheme.textMuted,
              ),
            ),
          ),
        for (final file in files)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: _openingFileId == file.id
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _fileIcon(file),
                    size: 22,
                    color: PlayerUiSignalTheme.primaryDarkColor,
                  ),
            title: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: PlayerUiSignalTheme.text),
            ),
            subtitle: Text(
              _fileSubtitle(file),
              style: TextStyle(
                fontSize: 12,
                color: PlayerUiSignalTheme.textMuted,
              ),
            ),
            trailing: isAdmin
                ? IconButton(
                    tooltip: 'Remove file',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: PlayerUiSignalTheme.textMuted,
                    ),
                    onPressed: controller.roomFilesBusy
                        ? null
                        : () => _confirmRemoveFile(controller, file),
                  )
                : null,
            onTap: _openingFileId != null
                ? null
                : () => _openFile(controller, file),
          ),
      ],
    );
  }

  Widget _buildMembersSection(
    ChatController controller,
    List<ChatParticipant> participants,
  ) {
    return _section(
      children: [
        _sectionTitle(
          '${participants.length} ${participants.length == 1 ? 'member' : 'members'}',
        ),
        if (participants.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Loading members…',
              style: TextStyle(
                fontSize: 12,
                color: PlayerUiSignalTheme.textMuted,
              ),
            ),
          ),
        for (final participant in participants)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: PlayerUiSignalTheme.mobileSearchColor,
              backgroundImage: participant.avatarUrl != null
                  ? NetworkImage(participant.avatarUrl!)
                  : null,
              child: participant.avatarUrl == null
                  ? Text(
                      participant.displayName.isEmpty
                          ? '?'
                          : participant.displayName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        color: PlayerUiSignalTheme.text,
                      ),
                    )
                  : null,
            ),
            title: Text(
              participant.userId == controller.matrixUserId
                  ? 'You'
                  : participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: PlayerUiSignalTheme.text),
            ),
            subtitle: participant.membership == 'join'
                ? null
                : Text(
                    participant.membership == 'invite'
                        ? 'Invited'
                        : participant.membership,
                    style: TextStyle(
                      fontSize: 12,
                      color: PlayerUiSignalTheme.textMuted,
                    ),
                  ),
            trailing: _roleTag(participant.level),
            onTap: participant.userId == controller.matrixUserId
                ? null
                : () => _showMemberActions(controller, participant),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildVerificationSection(
    ChatController controller,
    List<VerificationSession> verifications,
    Map<String, String> participantNameByUserId,
  ) {
    return _section(
      children: [
        _sectionTitle('Key verification'),
        for (final session in verifications)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              _verificationStateIcon(session),
              size: 20,
              color: _verificationStateColor(session),
            ),
            title: Text(
              _verificationParticipantName(
                session.userId,
                participantNameByUserId,
              ),
              style: TextStyle(fontSize: 14, color: PlayerUiSignalTheme.text),
            ),
            subtitle: Text(
              _verificationStateDisplay(session.state),
              style: TextStyle(
                fontSize: 12,
                color: _verificationStateColor(session),
              ),
            ),
            trailing: session.isDone
                ? const Text(
                    'Verified',
                    style: TextStyle(fontSize: 12, color: _adminGreen),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _smallIconButton(
                        icon: Icons.check_circle_outline,
                        color: const Color(0xFF2E7D32),
                        tooltip: 'Accept verification',
                        onPressed: () =>
                            controller.acceptVerification(session.id),
                      ),
                      _smallIconButton(
                        icon: Icons.tag_faces_outlined,
                        color: const Color(0xFF43A047),
                        tooltip: 'Accept SAS',
                        onPressed: () => controller.acceptSas(session.id),
                      ),
                      _smallIconButton(
                        icon: Icons.cancel_outlined,
                        color: const Color(0xFFC62828),
                        tooltip: 'Reject verification',
                        onPressed: () =>
                            controller.rejectVerification(session.id),
                      ),
                    ],
                  ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _smallIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required Future<void> Function() onPressed,
  }) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    icon: Icon(icon, color: color),
    onPressed: () => unawaited(onPressed()),
  );

  // ---- Members --------------------------------------------------------------------------------

  static int _levelRank(ChatMemberLevel level) => switch (level) {
    ChatMemberLevel.owner => 0,
    ChatMemberLevel.admin => 1,
    ChatMemberLevel.moderator => 2,
    ChatMemberLevel.member => 3,
  };

  /// Admins (and the owner) first, then moderators, then everyone else - by name within each.
  List<ChatParticipant> _sortedMembers(List<ChatParticipant> participants) {
    return [...participants]..sort((a, b) {
      final byRank = _levelRank(a.level).compareTo(_levelRank(b.level));
      if (byRank != 0) return byRank;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  /// A small coloured label (WhatsApp's "Group admin"); nothing for ordinary members.
  Widget? _roleTag(ChatMemberLevel level) {
    final label = switch (level) {
      ChatMemberLevel.owner || ChatMemberLevel.admin => 'Group admin',
      ChatMemberLevel.moderator => 'Moderator',
      ChatMemberLevel.member => null,
    };
    if (label == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _adminGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _adminGreen,
        ),
      ),
    );
  }

  void _showMemberActions(ChatController controller, ChatParticipant member) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(
                member.displayName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.verified_user_outlined, size: 20),
              title: const Text(
                'Verify security keys',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(controller.startKeyVerificationForUser(member.userId));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---- Files ----------------------------------------------------------------------------------

  Future<void> _addFile(ChatController controller) async {
    final posted = await controller.pickAndAddRoomFile();
    if (posted && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('File posted for members.')),
        );
    }
  }

  Future<void> _confirmRemoveFile(
    ChatController controller,
    ChatRoomFile file,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove file?', style: TextStyle(fontSize: 17)),
        content: Text(
          '"${file.name}" will no longer be shown to members.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) await controller.removeRoomFile(file.id);
  }

  /// Downloads the file (signed in) to a temp file named after it and opens it in the device's
  /// viewer for that type. Opened via OpenFilex, which shares it through a content provider:
  /// handing another app a file:// link (url_launcher) is refused on Android 7+.
  Future<void> _openFile(ChatController controller, ChatRoomFile file) async {
    final url = file.downloadUrl;
    if (url == null) return;
    setState(() => _openingFileId = file.id);
    String? failure;
    try {
      final Uint8List bytes;
      try {
        bytes = await controller.resolveMediaBytes(url);
      } catch (e) {
        debugPrint('[chat-files] download failed for ${file.name}: $e');
        failure = kDebugMode
            ? 'Could not download the file: $e'
            : 'Could not download the file.';
        return;
      }
      final dir = await getTemporaryDirectory();
      final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path =
          '${dir.path}/co_file_${DateTime.now().microsecondsSinceEpoch}_$safeName';
      await File(path).writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(path, type: file.mimeType);
      switch (result.type) {
        case ResultType.done:
          break;
        case ResultType.noAppToOpen:
          failure = 'No app available to open this file.';
        default:
          debugPrint(
            '[chat-files] open failed: ${result.type} ${result.message}',
          );
          failure = kDebugMode
              ? 'Could not open the file: ${result.message}'
              : 'Could not open the file.';
      }
    } catch (e) {
      debugPrint('[chat-files] open failed for ${file.name}: $e');
      failure = kDebugMode
          ? 'Could not open the file: $e'
          : 'Could not open the file.';
    } finally {
      if (mounted) {
        setState(() => _openingFileId = null);
        if (failure != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure)),
          );
        }
      }
    }
  }

  IconData _fileIcon(ChatRoomFile file) {
    final type = (file.mimeType ?? '').toLowerCase();
    final name = file.name.toLowerCase();
    if (type.startsWith('image/')) return Icons.image_outlined;
    if (type.startsWith('video/')) return Icons.movie_outlined;
    if (type.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (type == 'application/pdf' || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (name.endsWith('.xls') || name.endsWith('.xlsx') || name.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _fileSubtitle(ChatRoomFile file) {
    final parts = <String>[];
    final size = file.size;
    if (size != null) {
      if (size >= 1024 * 1024) {
        parts.add('${(size / (1024 * 1024)).toStringAsFixed(1)} MB');
      } else if (size >= 1024) {
        parts.add('${(size / 1024).round()} KB');
      } else {
        parts.add('$size B');
      }
    }
    final postedAt = file.postedAt;
    if (postedAt != null) {
      final d = postedAt.toLocal();
      parts.add('${d.day}/${d.month}/${d.year}');
    }
    return parts.join(' · ');
  }

  // ---- Verification helpers -------------------------------------------------------------------

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
    return normalized
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _isVerificationFailed(String state) =>
      state.contains('reject') ||
      state.contains('cancel') ||
      state.contains('declin') ||
      state.contains('fail') ||
      state.contains('error');

  Color _verificationStateColor(VerificationSession session) {
    final state = session.state.toLowerCase();
    if (session.isDone ||
        state.contains('done') ||
        state.contains('complete')) {
      return const Color(0xFF2E7D32);
    }
    if (_isVerificationFailed(state)) {
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
    if (_isVerificationFailed(state)) {
      return Icons.gpp_bad_outlined;
    }
    return Icons.verified_user_outlined;
  }

  // ---- Avatar ---------------------------------------------------------------------------------

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
